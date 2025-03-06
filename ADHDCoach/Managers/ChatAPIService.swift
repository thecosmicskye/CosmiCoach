import Foundation

/**
 * ChatAPIService handles all communication with the Claude API.
 *
 * This service is responsible for:
 * - Sending messages to Claude with appropriate context
 * - Processing streaming responses
 * - Handling tool use requests from Claude
 * - Managing API authentication and error handling
 */
class ChatAPIService {
    /// Callback for processing tool use requests from Claude
    /// Parameters:
    /// - toolName: The name of the tool to use
    /// - toolId: The unique ID of the tool use request
    /// - toolInput: The input parameters for the tool
    /// Returns: The result of the tool use as a string
    var processToolUseCallback: ((String, String, [String: Any]) async -> String)?
    
    /// Store tool use results for feedback to Claude in the next message
    private var pendingToolResults: [ToolUseResult] = []
    
    /// Variables to track tool use chunks during streaming
    private var currentToolName: String?
    private var currentToolId: String?
    private var currentToolInputJson = ""
    
    /// Retrieves the Claude API key from UserDefaults
    private var apiKey: String {
        return UserDefaults.standard.string(forKey: "claude_api_key") ?? ""
    }
    
    /// The URL endpoint for Claude's streaming API
    private let streamingURL = URL(string: "https://api.anthropic.com/v1/messages")!
    
    /// Cache performance tracking metrics
    private var cacheMetrics = CachePerformanceMetrics(cacheCreationTokens: 0, cacheReadTokens: 0, inputTokens: 0)
    
    /// System prompt that defines Claude's role
    private(set) var systemPrompt = """
    You are an empathic ADHD coach assistant that helps the user manage their tasks, calendar, and daily life. Your goal is to help them overcome overwhelm and make decisions about what to focus on.

    Guidelines:
    1. Be concise and clear in your responses
    2. Ask only one question at a time to minimize decision fatigue
    3. Proactively suggest task prioritization
    4. Check on daily basics (medicine, eating, drinking water)
    5. Analyze patterns in task completion over time
    6. Use the provided calendar events and reminders to give context-aware advice
    7. IMPORTANT: You MUST use the provided tools to create, modify, or delete calendar events, reminders, and memories
       - Use the appropriate tools for calendar events, reminders, and memories
       - DO NOT respond with text saying you've created a calendar event or reminder - use the tools
    8. Be empathetic and understanding of ADHD challenges
    9. Maintain important user information in structured memory categories
    10. When location information is provided, use it for context, but only mention it when relevant
        - For example, if the user said they're commuting and you see they're at a transit hub, you can acknowledge they're on track
        - Don't explicitly comment on location unless it's helpful in context

    You have access to the user's memory which contains information about them that persists between conversations. This information is organized into categories:
    - Personal Information: Basic information about the user
    - Preferences: User preferences and likes/dislikes
    - Behavior Patterns: Patterns in user behavior and task completion
    - Daily Basics: Tracking of daily basics like eating and drinking water
    - Medications: Medication information and tracking
    - Goals: Short and long-term goals
    - Miscellaneous Notes: Other information to remember

    Important guidelines for working with user memory:
    - Memories with higher importance (4-5) are most critical to refer to
    - Don't add redundant memories - check existing memories first 
    - Update memories when information changes rather than creating duplicates
    - Delete outdated information in memories
    - When adding specific facts, add them as separate memory items instead of combining multiple facts
    - The memory content is visible at the top of each conversation under USER MEMORY INFORMATION
    - DO NOT add calendar events or reminders as memories - this information is already provided in the context
    - Calendar events and reminders should only be managed with their respective tools, not stored in memory
    - Avoid duplicating memories
    """
    
    /// Store the last assistant message with tool use for follow-up requests
    private var lastAssistantMessageWithToolUse: [String: Any]?
    
    /// Store the last text content before tool use to provide context for follow-up
    private var lastTextContentBeforeToolUse: String = ""
    
    /// Store the complete conversation history including all tool uses and results
    private var completeConversationHistory: [[String: Any]] = []
    
    // Store the context from the initial request to use in follow-up requests
    private var lastMemoryContent: String = ""
    private var lastCalendarContext: String = ""
    private var lastRemindersContext: String = ""
    private var lastLocationContext: String = ""
    private var lastConversationHistory: String = ""
    
    /**
     * Sends a message to Claude with all necessary context and handles the streaming response.
     *
     * @param userMessage The user's message to send to Claude
     * @param conversationHistory Recent conversation history formatted as a string
     * @param memoryContent The user's memory content
     * @param calendarContext The user's calendar events formatted as a string
     * @param remindersContext The user's reminders formatted as a string
     * @param locationContext The user's location information (if available)
     * @param toolDefinitions Array of tool definitions that Claude can use
     * @param updateStreamingMessage Callback to update the UI with streaming content
     * @param finalizeStreamingMessage Callback to finalize the message when streaming is complete
     * @param isProcessingCallback Callback to update the processing state
     */
    func sendMessageToClaude(
        userMessage: String,
        conversationHistory: String,
        memoryContent: String,
        calendarContext: String,
        remindersContext: String,
        locationContext: String,
        toolDefinitions: [[String: Any]],
        updateStreamingMessage: @escaping (String) -> String,
        finalizeStreamingMessage: @escaping () -> Void,
        isProcessingCallback: @escaping (Bool) -> Void
    ) async {
        // Store context for use in follow-up requests
        self.lastMemoryContent = memoryContent
        self.lastCalendarContext = calendarContext
        self.lastRemindersContext = remindersContext
        self.lastLocationContext = locationContext
        self.lastConversationHistory = conversationHistory
        // Reset the complete conversation history for a new conversation
        if conversationHistory.isEmpty {
            completeConversationHistory = []
        }
        
        // Create message components using the APIRequestBuilder
        let contextMessage = APIRequestBuilder.createContextMessage(
            memoryContent: lastMemoryContent,
            calendarContext: lastCalendarContext,
            remindersContext: lastRemindersContext,
            locationContext: lastLocationContext,
            conversationHistory: lastConversationHistory
        )
        
        let assistantGreeting = APIRequestBuilder.createAssistantGreeting()
        let userMessageObj = APIRequestBuilder.createUserMessage(text: userMessage)
        
        // If this is a new conversation, initialize the complete conversation history
        if completeConversationHistory.isEmpty {
            completeConversationHistory.append(contextMessage)
            completeConversationHistory.append(assistantGreeting)
            completeConversationHistory.append(userMessageObj)
        } else {
            // If we're continuing a conversation, just add the new user message
            completeConversationHistory.append(userMessageObj)
        }
        
        // Use the complete conversation history for the messages array
        var messages = completeConversationHistory
        
        // Add any pending tool results as tool_result blocks
        // This handles the case when a previous message resulted in a tool use
        if !pendingToolResults.isEmpty {
            print("Including \(pendingToolResults.count) tool results in the request")
            
            // Only include tool results if we have actual tool use in previous messages
            // This prevents the 400 error "tool_result block(s) provided when previous message does not contain any tool_use blocks"
            
            // Check for actual tool_use blocks in previous messages
            // Simply checking message count isn't reliable
            var hasToolUseInPreviousMessages = false
            
            // Check if previous assistant messages contained tool use
            for msg in messages {
                if let content = msg["content"] as? [[String: Any]] {
                    for block in content {
                        if let type = block["type"] as? String, type == "tool_use" {
                            hasToolUseInPreviousMessages = true
                            break
                        }
                    }
                }
                if hasToolUseInPreviousMessages {
                    break
                }
            }
            
            if hasToolUseInPreviousMessages {
                // Create a tool results message and add it to the conversation
                let toolResultsMessage = APIRequestBuilder.createToolResultsMessage(toolResults: pendingToolResults)
                messages.append(toolResultsMessage)
                print("Added tool results to messages array")
            } else {
                // Even if there are no explicit tool_use blocks, we should still create
                // a synthetic assistant message with a tool_use so the tool results can be displayed
                print("Creating synthetic tool use message for tool results")
                
                // Create a synthetic assistant message with the tool uses
                var assistantToolUseBlocks: [[String: Any]] = []
                
                for result in pendingToolResults {
                    // Create a tool use block for each pending result
                    assistantToolUseBlocks.append([
                        "type": "tool_use",
                        "id": result.toolId,
                        "name": result.toolId.contains("add_memory") ? "add_memory" : "unknown_tool",
                        "input": ["content": "Auto-added tool use for result processing"]
                    ])
                }
                
                if !assistantToolUseBlocks.isEmpty {
                    // Add the synthetic assistant message with tool uses
                    let assistantMessage: [String: Any] = [
                        "role": "assistant",
                        "content": assistantToolUseBlocks
                    ]
                    messages.append(assistantMessage)
                    
                    // Now add the tool results message
                    let toolResultsMessage = APIRequestBuilder.createToolResultsMessage(toolResults: pendingToolResults)
                    messages.append(toolResultsMessage)
                    print("Added synthetic tool use and results to messages array")
                }
            }
            
            // Clear the pending results after adding them
            pendingToolResults = []
        }
        
        // Create the request body with system as a top-level parameter and tools
        let requestBody = APIRequestBuilder.buildRequestBodyWithCaching(
            systemPrompt: systemPrompt,
            toolDefinitions: toolDefinitions,
            messages: messages
        )
        
        print("💡 REQUEST CONTAINS \(toolDefinitions.count) TOOLS")
        for tool in toolDefinitions {
            if let name = tool["name"] as? String {
                print("💡 TOOL DEFINED: \(name)")
            }
        }
        
        // Create the request
        var request = URLRequest(url: streamingURL)
        APIRequestBuilder.configureRequestHeaders(for: &request, apiKey: apiKey)
        
        do {
            let requestData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = requestData
            
            // Print the actual request JSON for debugging
            if let requestStr = String(data: requestData, encoding: .utf8) {
                print("💡 FULL API REQUEST: \(String(requestStr.prefix(1000))) [...]") // Only print first 1000 chars
            }
            
            // Create a URLSession data task with delegate
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                isProcessingCallback(false)
                return
            }
            
            print("💡 API RESPONSE STATUS CODE: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode != 200 {
                var errorData = Data()
                for try await byte in asyncBytes {
                    errorData.append(byte)
                }
                
                // Try to extract error message from response
                let statusCode = httpResponse.statusCode
                var errorDetails = ""
                var errorType = ""
                
                if let responseString = String(data: errorData, encoding: .utf8) {
                    print("💡 API ERROR RESPONSE: \(responseString)")
                    
                    if let errorJson = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
                       let error = errorJson["error"] as? [String: Any] {
                        if let message = error["message"] as? String {
                            errorDetails = message
                            print("💡 ERROR MESSAGE: \(message)")
                        }
                        if let type = error["type"] as? String {
                            errorType = type
                            print("💡 ERROR TYPE: \(type)")
                        }
                    }
                }
                
                // Create user-friendly error message based on status code
                let userFriendlyMessage = APIErrorMessageCreator.createUserFriendlyErrorMessage(
                    statusCode: statusCode,
                    errorType: errorType,
                    errorDetails: errorDetails
                )
                
                finalizeStreamingMessage()
                _ = updateStreamingMessage(userFriendlyMessage)
                isProcessingCallback(false)
                return
            }
            
            // Process the streaming response
            for try await line in asyncBytes.lines {
                // Skip empty lines
                guard !line.isEmpty else { continue }
                
                // SSE format has "data: " prefix
                guard line.hasPrefix("data: ") else { continue }
                
                // Remove the "data: " prefix
                let jsonStr = line.dropFirst(6)
                
                // Handle the stream end event
                if jsonStr == "[DONE]" {
                    break
                }
                
                // Log raw response data for debugging
                print("💡 RAW RESPONSE: \(jsonStr)")
                
                // Parse the JSON
                if let data = jsonStr.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    
                    // Check for error events in the stream
                    if json["type"] as? String == "error",
                       let error = json["error"] as? [String: Any] {
                        var errorType = ""
                        var errorMessage = ""
                        
                        if let type = error["type"] as? String {
                            errorType = type
                            print("💡 STREAM ERROR TYPE: \(type)")
                        }
                        
                        if let message = error["message"] as? String {
                            errorMessage = message
                            print("💡 STREAM ERROR MESSAGE: \(message)")
                        }
                        
                        let userFriendlyMessage = APIErrorMessageCreator.createUserFriendlyErrorMessage(
                            statusCode: 0, // Use 0 to indicate it's a stream error, not an HTTP error
                            errorType: errorType,
                            errorDetails: "" // Don't append the original error, it's often redundant
                        )
                        
                        _ = updateStreamingMessage(userFriendlyMessage)
                        finalizeStreamingMessage()
                        isProcessingCallback(false)
                        return
                    }
                    
                    // Track cache performance metrics
                    if json["type"] as? String == "message_start",
                       let message = json["message"] as? [String: Any],
                       let usage = message["usage"] as? [String: Any] {
                        
                        if let creationTokens = usage["cache_creation_input_tokens"] as? Int {
                            cacheMetrics.cacheCreationTokens = creationTokens
                            print("🧠 Cache creation tokens: \(cacheMetrics.cacheCreationTokens)")
                        }
                        
                        if let readTokens = usage["cache_read_input_tokens"] as? Int {
                            cacheMetrics.cacheReadTokens = readTokens
                            print("🧠 Cache read tokens: \(cacheMetrics.cacheReadTokens)")
                        }
                        
                        if let tokens = usage["input_tokens"] as? Int {
                            cacheMetrics.inputTokens = tokens
                            print("🧠 Input tokens: \(cacheMetrics.inputTokens)")
                        }
                        
                        // Log cache performance summary
                        print("🧠 CACHE PERFORMANCE SUMMARY:")
                        print("🧠 - Cache creation tokens: \(cacheMetrics.cacheCreationTokens)")
                        print("🧠 - Cache read tokens: \(cacheMetrics.cacheReadTokens)")
                        print("🧠 - Regular input tokens: \(cacheMetrics.inputTokens)")
                        print("🧠 - Total tokens processed: \(cacheMetrics.totalTokens)")
                        
                        if cacheMetrics.hasCacheHit {
                            print("🧠 - Cache hit detected! Approximately \(String(format: "%.1f", cacheMetrics.cacheSavingsPercent))% of tokens were read from cache")
                        }
                        
                        // Record metrics in the performance tracker
                        CachePerformanceTracker.shared.recordRequest(
                            cacheCreationTokens: cacheMetrics.cacheCreationTokens,
                            cacheReadTokens: cacheMetrics.cacheReadTokens,
                            inputTokens: cacheMetrics.inputTokens
                        )
                    }
                    
                    // Check if this is a start of content block (could be text or tool)
                    if json["type"] as? String == "content_block_start" {
                        print("💡 Content block start detected")
                        if let contentBlock = json["content_block"] as? [String: Any],
                           let blockType = contentBlock["type"] as? String {
                            
                            print("💡 Content block type: \(blockType)")
                            
                            // Handle tool_use block start
                            if blockType == "tool_use" {
                                if let toolName = contentBlock["name"] as? String,
                                   let toolId = contentBlock["id"] as? String {
                                    print("💡 DETECTED TOOL USE START: \(toolName) with ID: \(toolId)")
                                    
                                    // Save the tool name and id for later
                                    self.currentToolName = toolName
                                    self.currentToolId = toolId
                                    self.currentToolInputJson = ""
                                    
                                    // We'll store the tool use information after we have the input JSON
                                    // This is done below when we process the tool use
                                }
                            }
                        }
                    }
                    // Handle tool input JSON deltas (streamed piece by piece)
                    else if json["type"] as? String == "content_block_delta",
                            let delta = json["delta"] as? [String: Any],
                            let inputJsonDelta = delta["type"] as? String, inputJsonDelta == "input_json_delta",
                            let partialJson = delta["partial_json"] as? String {
                        
                        print("💡 Tool input JSON delta: \(partialJson)")
                        
                        // Accumulate the input json
                        self.currentToolInputJson += partialJson
                    }
                    // Check for message_delta with stop_reason = "tool_use"
                    else if json["type"] as? String == "message_delta",
                            let delta = json["delta"] as? [String: Any],
                            let stopReason = delta["stop_reason"] as? String, stopReason == "tool_use" {
                        
                        print("💡 Message stopped for tool use")
                        
                        // Create usable tool input from collected JSON chunks
                        var toolInput: [String: Any] = [:]
                        
                        if !self.currentToolInputJson.isEmpty {
                            // Try to parse the accumulated input JSON
                            print("💡 Accumulated JSON: \(self.currentToolInputJson)")
                            
                            // Sometimes the JSON is incomplete/malformed because of streaming chunks
                            // In that case, we'll fall back to a default tool call
                            if let jsonData = self.currentToolInputJson.data(using: .utf8),
                               let parsedInput = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                                toolInput = parsedInput
                                print("💡 Successfully parsed JSON input from Claude")
                            } else {
                                print("💡 Failed to parse JSON, using fallback for \(self.currentToolName ?? "unknown tool")")
                                toolInput = ToolInputFallback.createInput(for: self.currentToolName)
                            }
                        } else {
                            print("💡 No input JSON accumulated, using fallback for \(self.currentToolName ?? "unknown tool")")
                            toolInput = ToolInputFallback.createInput(for: self.currentToolName)
                        }
                        
                        // Store this tool use in the lastAssistantMessageWithToolUse
                        // This will be used in follow-up requests
                        if lastAssistantMessageWithToolUse == nil {
                            lastAssistantMessageWithToolUse = [
                                "role": "assistant",
                                "content": [
                                    [
                                        "type": "tool_use",
                                        "id": self.currentToolId ?? "",
                                        "name": self.currentToolName ?? "",
                                        "input": toolInput // Include the input field
                                    ]
                                ]
                            ]
                        } else if var content = lastAssistantMessageWithToolUse?["content"] as? [[String: Any]] {
                            content.append([
                                "type": "tool_use",
                                "id": self.currentToolId ?? "",
                                "name": self.currentToolName ?? "",
                                "input": toolInput // Include the input field
                            ])
                            lastAssistantMessageWithToolUse?["content"] = content
                        }
                        
                        // If we have a tool name and ID, process the tool use
                        if let toolName = self.currentToolName, let toolId = self.currentToolId,
                           let processToolUse = self.processToolUseCallback {
                            print("💡 EXECUTING COLLECTED TOOL CALL: \(toolName)")
                            print("💡 With input: \(toolInput)")
                            
                            // Store this tool use in lastAssistantMessageWithToolUse for proper validation
                            if lastAssistantMessageWithToolUse == nil {
                                lastAssistantMessageWithToolUse = [
                                    "role": "assistant",
                                    "content": [[
                                        "type": "tool_use",
                                        "id": toolId,
                                        "name": toolName,
                                        "input": toolInput
                                    ]]
                                ]
                                print("💡 Created new lastAssistantMessageWithToolUse")
                            }
                            
                            // Process the tool use based on the tool name
                            let result = await processToolUse(toolName, toolId, toolInput)
                            
                            // Log the tool use and its result
                            print("💡 TOOL USE PROCESSED: \(toolName) with result: \(result)")
                            
                            // Store the tool result for the next API call
                            pendingToolResults.append(ToolUseResult(toolId: toolId, content: result))
                            
                            // Process all collected tool uses first, then send a follow-up request
                            // This prevents multiple duplicate operations from occurring
                            
                            // We now collect all tool results first (in pendingToolResults)
                            // and will send them all at once in a single follow-up request
                            // at the end of streaming process.
                            
                            // NOTE: We intentionally DO NOT immediately trigger
                            // a follow-up request here. Instead, the streaming loop
                            // will naturally end, and then we'll process all pending
                            // tool results at once to avoid duplicates.
                        }
                    }
                    // Handle regular text delta
                    else if let contentDelta = json["delta"] as? [String: Any],
                         let textContent = contentDelta["text"] as? String {
                        // Accumulate text content for context in follow-up requests
                        lastTextContentBeforeToolUse += textContent
                        
                        // Send the new content to the MainActor for UI updates
                        // and get back the full accumulated content
                        let updatedContent = updateStreamingMessage(textContent)
                        
                        // We still need to use the result of the updateStreamingMessage callback
                        // even though we're not tracking the full response anymore
                        let _ = updatedContent
                    }
                }
            }
            
            // If we have accumulated text content, add it to the conversation history
            if !lastTextContentBeforeToolUse.isEmpty {
                // Create an assistant message with the text content
                let textMessage: [String: Any] = [
                    "role": "assistant",
                    "content": [
                        ["type": "text", "text": lastTextContentBeforeToolUse]
                    ]
                ]
                
                // Add the text message to the conversation history
                completeConversationHistory.append(textMessage)
                print("💡 Added final text content to conversation history: \(lastTextContentBeforeToolUse)")
                
                // Reset the text content after adding it
                lastTextContentBeforeToolUse = ""
            }
            
            // Check if we have pending tool results that need to be processed
            if !pendingToolResults.isEmpty {
                print("💡 Sending follow-up request with \(pendingToolResults.count) pending tool results after stream completion")
                
                // Make sure we have a tool_use message before adding tool_result
                // Otherwise API returns error: "tool_result block(s) provided when previous message does not contain any tool_use blocks"
                if let assistantMessage = completeConversationHistory.last(where: {
                    ($0["role"] as? String) == "assistant"
                }), let content = assistantMessage["content"] as? [[String: Any]] {
                    
                    let hasToolUse = content.contains(where: {
                        ($0["type"] as? String) == "tool_use"
                    })
                    
                    if hasToolUse {
                        // Send a follow-up request with all collected tool results
                        await sendFollowUpRequestWithToolResults(
                            toolDefinitions: toolDefinitions,
                            updateStreamingMessage: updateStreamingMessage,
                            finalizeStreamingMessage: finalizeStreamingMessage,
                            isProcessingCallback: isProcessingCallback
                        )
                    } else {
                        print("💡 Converting tool results into a new user message for better handling")
                        
                        // Instead of failing, let's add a user message containing the tool result information
                        let userMessage = "I've just performed the following actions: " + 
                            pendingToolResults.map { "• \($0.content)" }.joined(separator: "\n")
                        
                        // Add the user message to the conversation history
                        let userMessageObj = APIRequestBuilder.createUserMessage(text: userMessage)
                        completeConversationHistory.append(userMessageObj)
                        
                        // Continue the conversation with this new message
                        await sendMessageWithCurrentState(
                            toolDefinitions: toolDefinitions,
                            updateStreamingMessage: updateStreamingMessage,
                            finalizeStreamingMessage: finalizeStreamingMessage,
                            isProcessingCallback: isProcessingCallback
                        )
                    }
                } else {
                    print("💡 Cannot add tool_results because there's no assistant message with tool_use blocks")
                    finalizeStreamingMessage()
                    isProcessingCallback(false)
                }
            } else {
                // No tool results to process, finalize the message
                finalizeStreamingMessage()
                isProcessingCallback(false)
            }
            
        } catch {
            finalizeStreamingMessage()
            let errorMessage = "Sorry, there was an error connecting to the service: \(error.localizedDescription)"
            _ = updateStreamingMessage(errorMessage)
            isProcessingCallback(false)
        }
    }
    
    
    /**
     * Tests if the current API key is valid by making a simple request to Claude.
     *
     * @return A string indicating whether the API key is valid or an error message
     */
    func testApiKey() async -> String {
        // Get the API key from UserDefaults
        guard !apiKey.isEmpty else {
            return "❌ Error: API key is not set"
        }
        
        // Create a simple request to test the API key
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        // Set up request headers directly instead of using APIRequestBuilder
        // to avoid including any optional headers that might cause issues
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        
        // Simple request body with correct format, stream: false for simple testing
        // Also include a basic tool definition to test if tools are supported
        let requestBody: [String: Any] = [
            "model": APIRequestBuilder.model,
            "max_tokens": 10,
            "stream": false,
            "tools": [
                [
                    "name": "test_tool",
                    "description": "A test tool",
                    "input_schema": [
                        "type": "object",
                        "properties": [
                            "test": ["type": "string"]
                        ]
                    ]
                ]
            ],
            "messages": [
                ["role": "user", "content": [
                    ["type": "text", "text": "Hello"]
                ]]
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            print("💡 Sending test API request with tools")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("💡 API Test Status Code: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    // Try to decode the response to confirm it worked
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("💡 API Test Response: \(responseString)")
                    }
                    return "✅ API key is valid with tools support!"
                } else {
                    // Try to extract error type and message
                    var errorDetails = ""
                    var errorType = ""
                    
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("💡 API Test Error Response: \(responseString)")
                        
                        if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let error = errorJson["error"] as? [String: Any] {
                            if let message = error["message"] as? String {
                                errorDetails = message
                                print("💡 TEST ERROR MESSAGE: \(message)")
                            }
                            if let type = error["type"] as? String {
                                errorType = type
                                print("💡 TEST ERROR TYPE: \(type)")
                            }
                        }
                    }
                    
                    // Create user-friendly error message based on status code
                    let userFriendlyMessage = APIErrorMessageCreator.createUserFriendlyErrorMessage(
                        statusCode: httpResponse.statusCode,
                        errorType: errorType,
                        errorDetails: errorDetails
                    )
                    
                    return "❌ \(userFriendlyMessage)"
                }
            } else {
                return "❌ Error: Invalid HTTP response"
            }
        } catch {
            print("💡 API Test Exception: \(error.localizedDescription)")
            return "❌ Error: \(error.localizedDescription)"
        }
    }
    
    /**
     * Sends a follow-up request to Claude with tool results to continue the conversation.
     *
     * This method is called automatically after a tool use is processed to allow Claude
     * to continue its response with the tool results.
     *
     * @param toolDefinitions Array of tool definitions that Claude can use
     * @param updateStreamingMessage Callback to update the UI with streaming content
     * @param finalizeStreamingMessage Callback to finalize the message when streaming is complete
     * @param isProcessingCallback Callback to update the processing state
     */
    
    
    private func sendFollowUpRequestWithToolResults(
        toolDefinitions: [[String: Any]],
        updateStreamingMessage: @escaping (String) -> String,
        finalizeStreamingMessage: @escaping () -> Void,
        isProcessingCallback: @escaping (Bool) -> Void
    ) async {
        print("💡 Sending follow-up request with tool results to continue Claude's response")
        
        // We need at least one tool result to continue
        guard !pendingToolResults.isEmpty else {
            print("💡 No pending tool results to send in follow-up request")
            return
        }
        
        // Create a new assistant message with the tool uses that have corresponding results
        var toolUseBlocks: [[String: Any]] = []
        
        // Track which tool uses we've already processed to avoid duplicates
        var processedToolIds = Set<String>()
        
        // First, try to get the original tool uses with their full inputs from lastAssistantMessageWithToolUse
        if let content = lastAssistantMessageWithToolUse?["content"] as? [[String: Any]] {
            for block in content {
                if let type = block["type"] as? String,
                   type == "tool_use",
                   let toolId = block["id"] as? String,
                   let toolName = block["name"] as? String,
                   let toolInput = block["input"] as? [String: Any],
                   pendingToolResults.contains(where: { $0.toolId == toolId }) {
                    
                    // Only include tool uses that have corresponding results
                    if !processedToolIds.contains(toolId) {
                        toolUseBlocks.append([
                            "type": "tool_use",
                            "id": toolId,
                            "name": toolName,
                            "input": toolInput // Include the original full input
                        ])
                        processedToolIds.insert(toolId)
                    }
                }
            }
        }
        
        // For any pending tool results that weren't matched above, use the current tool info
        for result in pendingToolResults {
            if !processedToolIds.contains(result.toolId) {
                // Try to find the original tool input from the accumulated JSON
                var toolInput: [String: Any] = [:]
                
                if !currentToolInputJson.isEmpty && result.toolId == currentToolId {
                    if let jsonData = currentToolInputJson.data(using: .utf8),
                       let parsedInput = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        toolInput = parsedInput
                    }
                }
                
                toolUseBlocks.append([
                    "type": "tool_use",
                    "id": result.toolId,
                    "name": currentToolName ?? "unknown_tool",
                    "input": toolInput // Use the parsed input or empty dict as last resort
                ])
                processedToolIds.insert(result.toolId)
            }
        }
        
        // Create an assistant message with the tool uses
        let assistantMessage: [String: Any] = [
            "role": "assistant",
            "content": toolUseBlocks
        ]
        
        print("💡 Created assistant message with \(toolUseBlocks.count) tool use blocks")
        
        // Add the assistant's text content if available
        if !lastTextContentBeforeToolUse.isEmpty {
            // Create an assistant message with the text content
            let textMessage: [String: Any] = [
                "role": "assistant",
                "content": [
                    ["type": "text", "text": lastTextContentBeforeToolUse]
                ]
            ]
            
            // Add the text message to the conversation history
            completeConversationHistory.append(textMessage)
            print("💡 Added previous text content to conversation history: \(lastTextContentBeforeToolUse)")
            
            // Reset the text content after adding it
            lastTextContentBeforeToolUse = ""
        }
        
        // Add the assistant message with tool uses to the conversation history
        completeConversationHistory.append(assistantMessage)
        
        // Create a user message with tool_result content blocks for each pending result
        var toolResultBlocks: [[String: Any]] = []
        
        for result in pendingToolResults {
            toolResultBlocks.append([
                "type": "tool_result",
                "tool_use_id": result.toolId,
                "content": result.content
            ])
        }
        
        // Create a user message with the tool results
        let userMessage: [String: Any] = ["role": "user", "content": toolResultBlocks]
        
        // Add the user message to the conversation history
        completeConversationHistory.append(userMessage)
        print("💡 Added \(pendingToolResults.count) tool results to conversation history")
        
        // Store the assistant message for future reference
        lastAssistantMessageWithToolUse = assistantMessage
        
        // Clear the pending results
        pendingToolResults = []
        
        // Update the context message with the latest memory data
        if !completeConversationHistory.isEmpty {
            // Get the updated context message
            let updatedContextMessage = APIRequestBuilder.createContextMessage(
                memoryContent: lastMemoryContent,
                calendarContext: lastCalendarContext,
                remindersContext: lastRemindersContext,
                locationContext: lastLocationContext,
                conversationHistory: lastConversationHistory
            )
            
            // Replace the first message (context) with updated content
            if completeConversationHistory[0]["role"] as? String == "user" {
                completeConversationHistory[0] = updatedContextMessage
                print("💡 Updated context message with latest memory data for tool follow-up")
            }
        }
        
        // Use the complete conversation history for the messages array
        let messages = completeConversationHistory
        
        // Create the request body with system as a top-level parameter and tools
        let requestBody = APIRequestBuilder.buildRequestBodyWithCaching(
            systemPrompt: systemPrompt,
            toolDefinitions: toolDefinitions,
            messages: messages
        )
        
        // Create the request
        var request = URLRequest(url: streamingURL)
        APIRequestBuilder.configureRequestHeaders(for: &request, apiKey: apiKey)
        
        do {
            let requestData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = requestData
            
            // Print the actual request JSON for debugging
            if let requestStr = String(data: requestData, encoding: .utf8) {
                print("💡 FOLLOW-UP API REQUEST: \(String(requestStr.prefix(1000))) [...]") // Only print first 1000 chars
            }
            
            // Create a URLSession data task with delegate
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                isProcessingCallback(false)
                return
            }
            
            print("💡 FOLLOW-UP API RESPONSE STATUS CODE: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode != 200 {
                var errorData = Data()
                for try await byte in asyncBytes {
                    errorData.append(byte)
                }
                
                // Try to extract error message from response
                let statusCode = httpResponse.statusCode
                var errorDetails = ""
                var errorType = ""
                
                if let responseString = String(data: errorData, encoding: .utf8) {
                    print("💡 FOLLOW-UP API ERROR RESPONSE: \(responseString)")
                    
                    if let errorJson = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
                       let error = errorJson["error"] as? [String: Any] {
                        if let message = error["message"] as? String {
                            errorDetails = message
                            print("💡 FOLLOW-UP ERROR MESSAGE: \(message)")
                        }
                        if let type = error["type"] as? String {
                            errorType = type
                            print("💡 FOLLOW-UP ERROR TYPE: \(type)")
                        }
                    }
                }
                
                // Create user-friendly error message based on status code
                let userFriendlyMessage = APIErrorMessageCreator.createUserFriendlyErrorMessage(
                    statusCode: statusCode,
                    errorType: errorType,
                    errorDetails: errorDetails,
                    isFollowUp: true
                )
                
                _ = updateStreamingMessage(userFriendlyMessage)
                finalizeStreamingMessage()
                isProcessingCallback(false)
                return
            }
            
            // Process the streaming response
            for try await line in asyncBytes.lines {
                // Skip empty lines
                guard !line.isEmpty else { continue }
                
                // SSE format has "data: " prefix
                guard line.hasPrefix("data: ") else { continue }
                
                // Remove the "data: " prefix
                let jsonStr = line.dropFirst(6)
                
                // Handle the stream end event
                if jsonStr == "[DONE]" {
                    break
                }
                
                // Log raw response data for debugging
                print("💡 FOLLOW-UP RAW RESPONSE: \(jsonStr)")
                
                // Parse the JSON
                if let data = jsonStr.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    
                    // Check for error events in the stream
                    if json["type"] as? String == "error",
                       let error = json["error"] as? [String: Any] {
                        var errorType = ""
                        var errorMessage = ""
                        
                        if let type = error["type"] as? String {
                            errorType = type
                            print("💡 FOLLOW-UP STREAM ERROR TYPE: \(type)")
                        }
                        
                        if let message = error["message"] as? String {
                            errorMessage = message
                            print("💡 FOLLOW-UP STREAM ERROR MESSAGE: \(message)")
                        }
                        
                        let userFriendlyMessage = APIErrorMessageCreator.createUserFriendlyErrorMessage(
                            statusCode: 0, // Use 0 to indicate it's a stream error, not an HTTP error
                            errorType: errorType,
                            errorDetails: "", // Don't append the original error, it's often redundant
                            isFollowUp: true
                        )
                        
                        _ = updateStreamingMessage(userFriendlyMessage)
                        finalizeStreamingMessage()
                        isProcessingCallback(false)
                        return
                    }
                    
                    // Track cache performance metrics
                    if json["type"] as? String == "message_start",
                       let message = json["message"] as? [String: Any],
                       let usage = message["usage"] as? [String: Any] {
                        
                        if let creationTokens = usage["cache_creation_input_tokens"] as? Int {
                            cacheMetrics.cacheCreationTokens = creationTokens
                            print("🧠 FOLLOW-UP Cache creation tokens: \(cacheMetrics.cacheCreationTokens)")
                        }
                        
                        if let readTokens = usage["cache_read_input_tokens"] as? Int {
                            cacheMetrics.cacheReadTokens = readTokens
                            print("🧠 FOLLOW-UP Cache read tokens: \(cacheMetrics.cacheReadTokens)")
                        }
                        
                        if let tokens = usage["input_tokens"] as? Int {
                            cacheMetrics.inputTokens = tokens
                            print("🧠 FOLLOW-UP Input tokens: \(cacheMetrics.inputTokens)")
                        }
                        
                        // Log cache performance summary
                        print("🧠 FOLLOW-UP CACHE PERFORMANCE SUMMARY:")
                        print("🧠 - Cache creation tokens: \(cacheMetrics.cacheCreationTokens)")
                        print("🧠 - Cache read tokens: \(cacheMetrics.cacheReadTokens)")
                        print("🧠 - Regular input tokens: \(cacheMetrics.inputTokens)")
                        print("🧠 - Total tokens processed: \(cacheMetrics.totalTokens)")
                        
                        if cacheMetrics.hasCacheHit {
                            print("🧠 - Cache hit detected! Approximately \(String(format: "%.1f", cacheMetrics.cacheSavingsPercent))% of tokens were read from cache")
                        }
                        
                        // Record metrics in the performance tracker
                        CachePerformanceTracker.shared.recordRequest(
                            cacheCreationTokens: cacheMetrics.cacheCreationTokens,
                            cacheReadTokens: cacheMetrics.cacheReadTokens,
                            inputTokens: cacheMetrics.inputTokens
                        )
                    }
                    
                    // Check if this is a start of content block (could be text or tool)
                    if json["type"] as? String == "content_block_start" {
                        print("💡 Follow-up content block start detected")
                        if let contentBlock = json["content_block"] as? [String: Any],
                           let blockType = contentBlock["type"] as? String {
                            
                            print("💡 Follow-up content block type: \(blockType)")
                            
                            // Handle tool_use block start
                            if blockType == "tool_use" {
                                if let toolName = contentBlock["name"] as? String,
                                   let toolId = contentBlock["id"] as? String {
                                    print("💡 FOLLOW-UP DETECTED TOOL USE START: \(toolName) with ID: \(toolId)")
                                    
                                    // Save the tool name and id for later
                                    self.currentToolName = toolName
                                    self.currentToolId = toolId
                                    self.currentToolInputJson = ""
                                    
                                    // Store this tool use in the lastAssistantMessageWithToolUse
                                    // This will be used in follow-up requests
                                    if var content = lastAssistantMessageWithToolUse?["content"] as? [[String: Any]] {
                                        // Try to parse the accumulated input JSON if available
                                        var toolInput: [String: Any] = [:]
                                        
                                        if !self.currentToolInputJson.isEmpty {
                                            if let jsonData = self.currentToolInputJson.data(using: .utf8),
                                               let parsedInput = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                                                toolInput = parsedInput
                                            }
                                        }
                                        
                                        content.append([
                                            "type": "tool_use",
                                            "id": toolId,
                                            "name": toolName,
                                            "input": toolInput // Store the full input, not an empty object
                                        ])
                                        lastAssistantMessageWithToolUse?["content"] = content
                                    }
                                }
                            }
                        }
                    }
                    // Handle tool input JSON deltas (streamed piece by piece)
                    else if json["type"] as? String == "content_block_delta",
                            let delta = json["delta"] as? [String: Any],
                            let inputJsonDelta = delta["type"] as? String, inputJsonDelta == "input_json_delta",
                            let partialJson = delta["partial_json"] as? String {
                        
                        print("💡 Follow-up tool input JSON delta: \(partialJson)")
                        
                        // Accumulate the input json
                        self.currentToolInputJson += partialJson
                    }
                    // Check for message_delta with stop_reason = "tool_use"
                    else if json["type"] as? String == "message_delta",
                            let delta = json["delta"] as? [String: Any],
                            let stopReason = delta["stop_reason"] as? String, stopReason == "tool_use" {
                        
                        print("💡 Follow-up message stopped for tool use")
                        
                        // Create usable tool input from collected JSON chunks
                        var toolInput: [String: Any] = [:]
                        
                        if !self.currentToolInputJson.isEmpty {
                            // Try to parse the accumulated input JSON
                            print("💡 Follow-up accumulated JSON: \(self.currentToolInputJson)")
                            
                            // Sometimes the JSON is incomplete/malformed because of streaming chunks
                            // In that case, we'll fall back to a default tool call
                            if let jsonData = self.currentToolInputJson.data(using: .utf8),
                               let parsedInput = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                                toolInput = parsedInput
                                print("💡 Successfully parsed JSON input from Claude in follow-up")
                            } else {
                                print("💡 Failed to parse JSON in follow-up, using fallback for \(self.currentToolName ?? "unknown tool")")
                                toolInput = ToolInputFallback.createInput(for: self.currentToolName)
                            }
                        } else {
                            print("💡 No input JSON accumulated in follow-up, using fallback for \(self.currentToolName ?? "unknown tool")")
                            toolInput = ToolInputFallback.createInput(for: self.currentToolName)
                        }
                        
                        // If we have a tool name and ID, process the tool use
                        if let toolName = self.currentToolName, let toolId = self.currentToolId,
                           let processToolUse = self.processToolUseCallback {
                            print("💡 EXECUTING COLLECTED TOOL CALL FROM FOLLOW-UP: \(toolName)")
                            print("💡 With input: \(toolInput)")
                            
                            // Process the tool use based on the tool name
                            let result = await processToolUse(toolName, toolId, toolInput)
                            
                            // Log the tool use and its result
                            print("💡 FOLLOW-UP TOOL USE PROCESSED: \(toolName) with result: \(result)")
                            
                            // Store the tool result for the next API call
                            pendingToolResults.append(ToolUseResult(toolId: toolId, content: result))
                            
                            // Don't make recursive calls to sendFollowUpRequestWithToolResults
                            // Instead, collect all tool results and process them at the end
                            print("💡 Collected tool result for later processing")
                        }
                    }
                    // Handle regular text delta
                    else if let contentDelta = json["delta"] as? [String: Any],
                            let textContent = contentDelta["text"] as? String {
                        // Accumulate text content for context in follow-up requests
                        lastTextContentBeforeToolUse += textContent
                        
                        // Send the new content to the MainActor for UI updates
                        // and get back the full accumulated content
                        let updatedContent = updateStreamingMessage(textContent)
                        
                        // We still need to use the result of the updateStreamingMessage callback
                        // even though we're not tracking the full response anymore
                        let _ = updatedContent
                    }
                }
            }
            
            // If we have accumulated text content, add it to the conversation history
            if !lastTextContentBeforeToolUse.isEmpty {
                // Create an assistant message with the text content
                let textMessage: [String: Any] = [
                    "role": "assistant",
                    "content": [
                        ["type": "text", "text": lastTextContentBeforeToolUse]
                    ]
                ]
                
                // Add the text message to the conversation history
                completeConversationHistory.append(textMessage)
                print("💡 Added final text content to conversation history: \(lastTextContentBeforeToolUse)")
                
                // Reset the text content after adding it
                lastTextContentBeforeToolUse = ""
            }
            
            // Check if we have pending tool results that need to be processed
            if !pendingToolResults.isEmpty {
                print("💡 Sending follow-up request with \(pendingToolResults.count) pending tool results after follow-up completion")
                
                // Make sure we have a tool_use message before adding tool_result
                // Otherwise API returns error: "tool_result block(s) provided when previous message does not contain any tool_use blocks"
                if let lastAssistantMessage = completeConversationHistory.last(where: {
                    ($0["role"] as? String) == "assistant"
                }), let content = lastAssistantMessage["content"] as? [[String: Any]] {
                    
                    let hasToolUse = content.contains(where: {
                        ($0["type"] as? String) == "tool_use"
                    })
                    
                    if hasToolUse {
                        // We have tool_use blocks, so we can add tool_result blocks
                        // Clear current pending results so we don't get into an infinite loop
                        let currentPendingResults = pendingToolResults
                        pendingToolResults = []
                        
                        // Create a new batch of tool results for the next request
                        var newToolResultBlocks: [[String: Any]] = []
                        for result in currentPendingResults {
                            newToolResultBlocks.append([
                                "type": "tool_result",
                                "tool_use_id": result.toolId,
                                "content": result.content
                            ])
                        }
                        
                        // Create and add a new user message with these tool results
                        let additionalUserMessage: [String: Any] = ["role": "user", "content": newToolResultBlocks]
                        completeConversationHistory.append(additionalUserMessage)
                        
                        // Continue the conversation with all tool results included
                        await sendMessageWithCurrentState(
                            toolDefinitions: toolDefinitions,
                            updateStreamingMessage: updateStreamingMessage,
                            finalizeStreamingMessage: finalizeStreamingMessage,
                            isProcessingCallback: isProcessingCallback
                        )
                    } else {
                        print("💡 Converting tool results into a new user message for better handling")
                        
                        // Instead of failing, let's add a user message containing the tool result information
                        let userMessage = "I've just performed the following actions: " + 
                            pendingToolResults.map { "• \($0.content)" }.joined(separator: "\n")
                        
                        // Add the user message to the conversation history
                        let userMessageObj = APIRequestBuilder.createUserMessage(text: userMessage)
                        completeConversationHistory.append(userMessageObj)
                        
                        // Continue the conversation with this new message
                        await sendMessageWithCurrentState(
                            toolDefinitions: toolDefinitions,
                            updateStreamingMessage: updateStreamingMessage,
                            finalizeStreamingMessage: finalizeStreamingMessage,
                            isProcessingCallback: isProcessingCallback
                        )
                    }
                } else {
                    print("💡 Converting tool results into a new user message for better handling")
                    
                    // Create a meaningful user message from the tool results
                    let userMessage = "I've just performed the following actions: " + 
                        pendingToolResults.map { "• \($0.content)" }.joined(separator: "\n")
                    
                    // Add the user message to the conversation history
                    let userMessageObj = APIRequestBuilder.createUserMessage(text: userMessage)
                    completeConversationHistory.append(userMessageObj)
                    
                    // Continue the conversation with this new message
                    await sendMessageWithCurrentState(
                        toolDefinitions: toolDefinitions,
                        updateStreamingMessage: updateStreamingMessage,
                        finalizeStreamingMessage: finalizeStreamingMessage,
                        isProcessingCallback: isProcessingCallback
                    )
                }
            } else {
                // No tool results to process, finalize the message
                finalizeStreamingMessage()
                isProcessingCallback(false)
            }
            
        } catch {
            let errorMessage = "\n\nUnable to continue: There was an error connecting to the service. \(error.localizedDescription)"
            _ = updateStreamingMessage(errorMessage)
            finalizeStreamingMessage()
            isProcessingCallback(false)
        }
    }
    
    /**
     * Sends a message to Claude using the current conversation state.
     *
     * This is a helper method used to continue a conversation after tool use
     * without creating duplicate tool calls.
     *
     * @param toolDefinitions Array of tool definitions that Claude can use
     * @param updateStreamingMessage Callback to update the UI with streaming content
     * @param finalizeStreamingMessage Callback to finalize the message when streaming is complete
     * @param isProcessingCallback Callback to update the processing state
     */
    private func sendMessageWithCurrentState(
        toolDefinitions: [[String: Any]],
        updateStreamingMessage: @escaping (String) -> String,
        finalizeStreamingMessage: @escaping () -> Void,
        isProcessingCallback: @escaping (Bool) -> Void
    ) async {
        // Recreate the context message with the latest data
        if !completeConversationHistory.isEmpty {
            // Get the updated context message
            let updatedContextMessage = APIRequestBuilder.createContextMessage(
                memoryContent: lastMemoryContent,
                calendarContext: lastCalendarContext,
                remindersContext: lastRemindersContext,
                locationContext: lastLocationContext,
                conversationHistory: lastConversationHistory
            )
            
            // Replace the first message (context) with updated content
            if completeConversationHistory[0]["role"] as? String == "user" {
                completeConversationHistory[0] = updatedContextMessage
                print("💡 Updated context message with latest memory data mid-conversation")
            }
        }
        
        // Create the request body with system as a top-level parameter and tools
        let requestBody = APIRequestBuilder.buildRequestBodyWithCaching(
            systemPrompt: systemPrompt,
            toolDefinitions: toolDefinitions,
            messages: completeConversationHistory
        )
        
        // Create the request
        var request = URLRequest(url: streamingURL)
        APIRequestBuilder.configureRequestHeaders(for: &request, apiKey: apiKey)
        
        do {
            let requestData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = requestData
            
            // Print the actual request JSON for debugging
            if let requestStr = String(data: requestData, encoding: .utf8) {
                print("💡 CONTINUATION API REQUEST: \(String(requestStr.prefix(1000))) [...]") // Only print first 1000 chars
            }
            
            // Create a URLSession data task with delegate
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                isProcessingCallback(false)
                return
            }
            
            print("💡 CONTINUATION API RESPONSE STATUS CODE: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode != 200 {
                var errorData = Data()
                for try await byte in asyncBytes {
                    errorData.append(byte)
                }
                
                // Try to extract error message from response
                let statusCode = httpResponse.statusCode
                var errorDetails = ""
                var errorType = ""
                
                if let responseString = String(data: errorData, encoding: .utf8) {
                    print("💡 CONTINUATION API ERROR RESPONSE: \(responseString)")
                    
                    if let errorJson = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
                       let error = errorJson["error"] as? [String: Any] {
                        if let message = error["message"] as? String {
                            errorDetails = message
                        }
                        if let type = error["type"] as? String {
                            errorType = type
                        }
                    }
                }
                
                // Create user-friendly error message based on status code
                let userFriendlyMessage = APIErrorMessageCreator.createUserFriendlyErrorMessage(
                    statusCode: statusCode,
                    errorType: errorType,
                    errorDetails: errorDetails,
                    isFollowUp: true
                )
                
                _ = updateStreamingMessage(userFriendlyMessage)
                finalizeStreamingMessage()
                isProcessingCallback(false)
                return
            }
            
            // Process the streaming response
            for try await line in asyncBytes.lines {
                // Skip empty lines
                guard !line.isEmpty else { continue }
                
                // SSE format has "data: " prefix
                guard line.hasPrefix("data: ") else { continue }
                
                // Remove the "data: " prefix
                let jsonStr = line.dropFirst(6)
                
                // Handle the stream end event
                if jsonStr == "[DONE]" {
                    break
                }
                
                // Log raw response data for debugging
                print("💡 CONTINUATION RAW RESPONSE: \(jsonStr)")
                
                // Parse the JSON
                if let data = jsonStr.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    
                    // Handle regular text delta
                    if let contentDelta = json["delta"] as? [String: Any],
                       let textContent = contentDelta["text"] as? String {
                        // Send the new content to the MainActor for UI updates
                        let _ = updateStreamingMessage(textContent)
                    }
                }
            }
            
            // Finalize the assistant message
            finalizeStreamingMessage()
            isProcessingCallback(false)
            
        } catch {
            let errorMessage = "\n\nUnable to continue: There was an error connecting to the service. \(error.localizedDescription)"
            _ = updateStreamingMessage(errorMessage)
            finalizeStreamingMessage()
            isProcessingCallback(false)
        }
    }

    
    /**
     * Tests if a provided API key is valid by making a simple request to Claude.
     *
     * @param key The API key to test
     * @return A boolean indicating whether the API key is valid
     */
    func testAPIKey(_ key: String) async -> Bool {
        // Create a simple request to test the API key
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        // We need to set headers manually here instead of using configureRequestHeaders
        // because we're using a different API key
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue(key, forHTTPHeaderField: "x-api-key")
        
        // Simple request body with correct format, stream: false for simple testing
        let requestBody: [String: Any] = [
            "model": "claude-3-7-sonnet-20250219",
            "max_tokens": 10,
            "stream": false,
            "messages": [
                ["role": "user", "content": "Hello"]
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            print("API key test error: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Context Update Methods
    
    /**
     * Updates the memory content stored in the context.
     * This ensures Claude has access to the latest memory data during a conversation.
     *
     * @param memoryContent The updated memory content string
     */
    func updateMemoryContext(_ memoryContent: String) async {
        self.lastMemoryContent = memoryContent
        print("💡 Memory context updated in API service (length: \(memoryContent.count) chars)")
    }
    
    /**
     * Updates the calendar events stored in the context.
     * This ensures Claude has access to the latest calendar data during a conversation.
     *
     * @param calendarContext The updated calendar events formatted as a string
     */
    func updateCalendarContext(_ calendarContext: String) async {
        self.lastCalendarContext = calendarContext
        print("💡 Calendar context updated in API service (length: \(calendarContext.count) chars)")
    }
    
    /**
     * Updates the reminders stored in the context.
     * This ensures Claude has access to the latest reminders data during a conversation.
     *
     * @param remindersContext The updated reminders formatted as a string
     */
    func updateRemindersContext(_ remindersContext: String) async {
        self.lastRemindersContext = remindersContext
        print("💡 Reminders context updated in API service (length: \(remindersContext.count) chars)")
    }
    
    /**
     * Updates the location information stored in the context.
     * This ensures Claude has access to the latest location data during a conversation.
     *
     * @param locationContext The updated location information as a string
     */
    func updateLocationContext(_ locationContext: String) async {
        self.lastLocationContext = locationContext
        print("💡 Location context updated in API service (length: \(locationContext.count) chars)")
    }
}
