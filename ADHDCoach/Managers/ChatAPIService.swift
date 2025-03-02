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
    private var pendingToolResults: [(toolId: String, content: String)] = []
    
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
       - Use add_calendar_event tool when the user asks to create a single calendar event
       - Use add_calendar_events_batch tool when the user asks to create multiple calendar events
       - Use add_reminder tool when the user asks to create a single reminder
       - Use add_reminders_batch tool when the user asks to create multiple reminders
       - Use add_memory tool when you need to store a single piece of important information
       - Use add_memories_batch tool when you need to store multiple pieces of important information
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
    - DO NOT add calendar events or reminders as memories
    - Avoid duplicating memories

    IMPORTANT: When working with multiple items (multiple calendar events, reminders, or memories), always use the batch tools:
    - add_calendar_events_batch: Use this to add multiple calendar events in a single operation
    - modify_calendar_events_batch: Use this to modify multiple calendar events in a single operation
    - delete_calendar_events_batch: Use this to delete multiple calendar events in a single operation
    - add_reminders_batch: Use this to add multiple reminders in a single operation
    - modify_reminders_batch: Use this to modify multiple reminders in a single operation
    - delete_reminders_batch: Use this to delete multiple reminders in a single operation
    - add_memories_batch: Use this to add multiple memories in a single operation
    - remove_memories_batch: Use this to remove multiple memories in a single operation
    """
    
    /// Store the last assistant message with tool use for follow-up requests
    private var lastAssistantMessageWithToolUse: [String: Any]?
    
    /// Store the last text content before tool use to provide context for follow-up
    private var lastTextContentBeforeToolUse: String = ""
    
    /// Store the complete conversation history including all tool uses and results
    private var completeConversationHistory: [[String: Any]] = []
    
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
        
        // Create a messages array with context first, then user message
        var contextMessage: [String: Any] = ["role": "user", "content": [
            ["type": "text", "text": """
            Current time: \(formatCurrentDateTime())
            
            USER MEMORY:
            \(lastMemoryContent)
            
            CALENDAR EVENTS:
            \(lastCalendarContext)
            
            REMINDERS:
            \(lastRemindersContext)
            
            \(lastLocationContext)
            
            CONVERSATION HISTORY:
            \(lastConversationHistory)
            """]
        ]]
        
        var assistantGreeting: [String: Any] = ["role": "assistant", "content": [
            ["type": "text", "text": "I understand. How can I help you today?"]
        ]]
        
        var userMessage: [String: Any] = ["role": "user", "content": [
            ["type": "text", "text": userMessage]
        ]]
        
        // If this is a new conversation, initialize the complete conversation history
        if completeConversationHistory.isEmpty {
            completeConversationHistory.append(contextMessage)
            completeConversationHistory.append(assistantGreeting)
            completeConversationHistory.append(userMessage)
        } else {
            // If we're continuing a conversation, just add the new user message
            completeConversationHistory.append(userMessage)
        }
        
        // Use the complete conversation history for the messages array
        var messages = completeConversationHistory
        
        // Add any pending tool results as tool_result blocks
        // This handles the case when a previous message resulted in a tool use
        if !pendingToolResults.isEmpty {
            print("Including \(pendingToolResults.count) tool results in the request")
            
            // Create a user message with tool_result content blocks for each pending result
            var toolResultBlocks: [[String: Any]] = []
            
            for result in pendingToolResults {
                toolResultBlocks.append([
                    "type": "tool_result",
                    "tool_use_id": result.toolId,
                    "content": result.content
                ])
            }
            
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
            
            if !toolResultBlocks.isEmpty && hasToolUseInPreviousMessages {
                messages.append(["role": "user", "content": toolResultBlocks])
                print("Added tool results to messages array")
            } else if !toolResultBlocks.isEmpty {
                print("Skipping tool results because there are no previous messages with tool use")
            }
            
            // Clear the pending results after adding them
            pendingToolResults = []
        }
        
        // Create the request body with system as a top-level parameter and tools
        let requestBody: [String: Any] = [
            "model": "claude-3-7-sonnet-20250219",
            "max_tokens": 4000,
            "system": systemPrompt,
            "tools": toolDefinitions,
            "stream": true,
            "messages": messages
        ]
        
        print("💡 REQUEST CONTAINS \(toolDefinitions.count) TOOLS")
        for tool in toolDefinitions {
            if let name = tool["name"] as? String {
                print("💡 TOOL DEFINED: \(name)")
            }
        }
        
        // Create the request
        var request = URLRequest(url: streamingURL)
        configureRequestHeaders(&request)
        
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
                
                if let responseString = String(data: errorData, encoding: .utf8) {
                    print("💡 API ERROR RESPONSE: \(responseString)")
                    
                    if let errorJson = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
                       let error = errorJson["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        errorDetails = ". \(message)"
                        print("💡 ERROR MESSAGE: \(message)")
                    }
                }
                
                let finalErrorMessage = "Error communicating with Claude API. Status code: \(statusCode)\(errorDetails)"
                
                finalizeStreamingMessage()
                _ = updateStreamingMessage(finalErrorMessage)
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
                                createFallbackToolInput(toolName: self.currentToolName, toolInput: &toolInput)
                            }
                        } else {
                            print("💡 No input JSON accumulated, using fallback for \(self.currentToolName ?? "unknown tool")")
                            createFallbackToolInput(toolName: self.currentToolName, toolInput: &toolInput)
                        }
                        
                        // Helper function to create appropriate fallback input based on tool type
                        func createFallbackToolInput(toolName: String?, toolInput: inout [String: Any]) {
                            let now = Date()
                            
                            switch toolName {
                            case "add_calendar_event":
                                let oneHourLater = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now
                                toolInput = [
                                    "title": "Test Calendar Event",
                                    "start": DateFormatter.claudeDateParser.string(from: now),
                                    "end": DateFormatter.claudeDateParser.string(from: oneHourLater),
                                    "notes": "Created by Claude when JSON parsing failed"
                                ]
                            case "add_reminder":
                                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
                                toolInput = [
                                    "title": "Test Reminder",
                                    "due": DateFormatter.claudeDateParser.string(from: tomorrow),
                                    "notes": "Created by Claude when JSON parsing failed"
                                ]
                            case "add_memory":
                                toolInput = [
                                    "content": "User asked Claude to create a test memory",
                                    "category": "Miscellaneous Notes",
                                    "importance": 3
                                ]
                            default:
                                // For other tools, provide a basic fallback
                                toolInput = ["note": "Fallback tool input for \(toolName ?? "unknown tool")"]
                            }
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
                            
                            // Process the tool use based on the tool name
                            let result = await processToolUse(toolName, toolId, toolInput)
                            
                            // Log the tool use and its result
                            print("💡 TOOL USE PROCESSED: \(toolName) with result: \(result)")
                            
                            // Store the tool result for the next API call
                            pendingToolResults.append((toolId: toolId, content: result))
                            
                            // Automatically send a follow-up request with the tool results
                            // to continue the conversation after tool use
                            await sendFollowUpRequestWithToolResults(
                                toolDefinitions: toolDefinitions,
                                updateStreamingMessage: updateStreamingMessage,
                                finalizeStreamingMessage: finalizeStreamingMessage,
                                isProcessingCallback: isProcessingCallback
                            )
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
                var textMessage: [String: Any] = [
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
            
            // Finalize the assistant message
            finalizeStreamingMessage()
            isProcessingCallback(false)
            
        } catch {
            finalizeStreamingMessage()
            _ = updateStreamingMessage("Error: \(error.localizedDescription)")
            isProcessingCallback(false)
        }
    }
    
    /**
     * Formats the current date and time with timezone information.
     *
     * @return A formatted string representing the current date and time
     */
    private func formatCurrentDateTime() -> String {
        return DateFormatter.formatCurrentDateTimeWithTimezone()
    }
    
    /**
     * Configures the HTTP request headers for Claude API communication.
     *
     * @param request The URLRequest to configure
     */
    private func configureRequestHeaders(_ request: inout URLRequest) {
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // Add the beta header for token-efficient tool use
        request.addValue("token-efficient-tools-2025-02-19", forHTTPHeaderField: "anthropic-beta")
        // For tool use, we should use the most recent version with tools support
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
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
        // Set up request headers directly instead of using configureRequestHeaders
        // to avoid including any optional headers that might cause issues
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // Add the beta header for token-efficient tool use
        request.addValue("token-efficient-tools-2025-02-19", forHTTPHeaderField: "anthropic-beta")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        
        // Simple request body with correct format, stream: false for simple testing
        // Also include a basic tool definition to test if tools are supported
        let requestBody: [String: Any] = [
            "model": "claude-3-7-sonnet-20250219",
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
                    // Try to extract error message
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("💡 API Test Error Response: \(responseString)")
                        return "❌ Error: \(responseString)"
                    } else {
                        return "❌ Error: Status code \(httpResponse.statusCode)"
                    }
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
    // Store the context from the initial request to use in follow-up requests
    private var lastMemoryContent: String = ""
    private var lastCalendarContext: String = ""
    private var lastRemindersContext: String = ""
    private var lastLocationContext: String = ""
    private var lastConversationHistory: String = ""
    
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
        var assistantMessage: [String: Any] = [
            "role": "assistant",
            "content": toolUseBlocks
        ]
        
        // Add the assistant's text content if available
        if !lastTextContentBeforeToolUse.isEmpty {
            // Create an assistant message with the text content
            var textMessage: [String: Any] = [
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
        var userMessage: [String: Any] = ["role": "user", "content": toolResultBlocks]
        
        // Add the user message to the conversation history
        completeConversationHistory.append(userMessage)
        print("💡 Added \(pendingToolResults.count) tool results to conversation history")
        
        // Store the assistant message for future reference
        lastAssistantMessageWithToolUse = assistantMessage
        
        // Clear the pending results
        pendingToolResults = []
        
        // Use the complete conversation history for the messages array
        var messages = completeConversationHistory
        
        // Create the request body with system as a top-level parameter and tools
        let requestBody: [String: Any] = [
            "model": "claude-3-7-sonnet-20250219",
            "max_tokens": 4000,
            "system": systemPrompt,
            "tools": toolDefinitions,
            "stream": true,
            "messages": messages
        ]
        
        // Create the request
        var request = URLRequest(url: streamingURL)
        configureRequestHeaders(&request)
        
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
                
                if let responseString = String(data: errorData, encoding: .utf8) {
                    print("💡 FOLLOW-UP API ERROR RESPONSE: \(responseString)")
                    
                    if let errorJson = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
                       let error = errorJson["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        errorDetails = ". \(message)"
                        print("💡 FOLLOW-UP ERROR MESSAGE: \(message)")
                    }
                }
                
                let finalErrorMessage = "\n\nError continuing response after tool use. Status code: \(statusCode)\(errorDetails)"
                
                _ = updateStreamingMessage(finalErrorMessage)
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
                                createFallbackToolInput(toolName: self.currentToolName, toolInput: &toolInput)
                            }
                        } else {
                            print("💡 No input JSON accumulated in follow-up, using fallback for \(self.currentToolName ?? "unknown tool")")
                            createFallbackToolInput(toolName: self.currentToolName, toolInput: &toolInput)
                        }
                        
                        // Helper function to create appropriate fallback input based on tool type
                        func createFallbackToolInput(toolName: String?, toolInput: inout [String: Any]) {
                            let now = Date()
                            
                            switch toolName {
                            case "add_calendar_event":
                                let oneHourLater = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now
                                toolInput = [
                                    "title": "Test Calendar Event",
                                    "start": DateFormatter.claudeDateParser.string(from: now),
                                    "end": DateFormatter.claudeDateParser.string(from: oneHourLater),
                                    "notes": "Created by Claude when JSON parsing failed"
                                ]
                            case "add_reminder":
                                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
                                toolInput = [
                                    "title": "Test Reminder",
                                    "due": DateFormatter.claudeDateParser.string(from: tomorrow),
                                    "notes": "Created by Claude when JSON parsing failed"
                                ]
                            case "add_memory":
                                toolInput = [
                                    "content": "User asked Claude to create a test memory",
                                    "category": "Miscellaneous Notes",
                                    "importance": 3
                                ]
                            default:
                                // For other tools, provide a basic fallback
                                toolInput = ["note": "Fallback tool input for \(toolName ?? "unknown tool")"]
                            }
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
                            pendingToolResults.append((toolId: toolId, content: result))
                            
                            // Recursively send another follow-up request with the new tool results
                            await sendFollowUpRequestWithToolResults(
                                toolDefinitions: toolDefinitions,
                                updateStreamingMessage: updateStreamingMessage,
                                finalizeStreamingMessage: finalizeStreamingMessage,
                                isProcessingCallback: isProcessingCallback
                            )
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
                var textMessage: [String: Any] = [
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
            
            // Finalize the assistant message
            finalizeStreamingMessage()
            isProcessingCallback(false)
            
        } catch {
            _ = updateStreamingMessage("\n\nError continuing response after tool use: \(error.localizedDescription)")
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
        // Add the beta header for token-efficient tool use
        request.addValue("token-efficient-tools-2025-02-19", forHTTPHeaderField: "anthropic-beta")
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
}
