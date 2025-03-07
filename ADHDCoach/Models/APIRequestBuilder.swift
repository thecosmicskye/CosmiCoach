import Foundation

/**
 * APIRequestBuilder handles building and formatting API requests to Claude.
 * 
 * This class is responsible for constructing the JSON structure required
 * for Claude API requests, including handling prompt caching.
 */
class APIRequestBuilder {
    // MARK: - Constants
    
    static let model = "claude-3-7-sonnet-20250219"
    static let maxTokens = 4000
    
    // MARK: - Cache Tracking
    
    // Track content hashes to determine when content has changed
    private static var lastMemoryHash: Int = 0
    private static var lastCalRemHash: Int = 0
    private static var lastHistoryHash: Int = 0
    
    // MARK: - Request Building
    
    /**
     * Builds a request body with smart prompt caching enabled.
     *
     * This method creates a request body with cache_control parameters using
     * a hybrid approach that:
     * 1. Caches static content (system prompt, tool definitions)
     * 2. Uses a multi-part message approach for context to allow caching of stable data
     * 3. Uses content-aware hashing to determine when to invalidate cache
     *
     * @param systemPrompt The system prompt to include in the request
     * @param toolDefinitions Array of tool definitions that Claude can use
     * @param messages Array of messages to include in the request
     * @return A dictionary containing the request body with caching enabled
     */
    static func buildRequestBodyWithCaching(
        systemPrompt: String,
        toolDefinitions: [[String: Any]],
        messages: [[String: Any]]
    ) -> [String: Any] {
        // Add cache control to tool definitions - these rarely change
        var cachedToolDefinitions = toolDefinitions
        if !cachedToolDefinitions.isEmpty {
            // Add cache_control to the last tool definition
            var lastTool = cachedToolDefinitions[cachedToolDefinitions.count - 1]
            lastTool["cache_control"] = ["type": "ephemeral"]
            cachedToolDefinitions[cachedToolDefinitions.count - 1] = lastTool
            print("🧠 Added ephemeral cache to tool definitions")
        }
        
        // Smart caching for context message
        var cachedMessages = messages
        if !cachedMessages.isEmpty {
            // Check if the first message is a context message from the user
            if var firstMessage = cachedMessages.first,
               let role = firstMessage["role"] as? String, role == "user",
               var content = firstMessage["content"] as? [[String: Any]],
               !content.isEmpty,
               let text = content[0]["text"] as? String {
                
                // Split the message into multiple parts to enable partial caching
                let lines = text.components(separatedBy: "\n\n")
                var newContent: [[String: Any]] = []
                
                // Extract the different context sections
                var currentTimeSection = ""
                var userMemorySection = ""
                var calendarSection = ""
                var remindersSection = ""
                var locationSection = ""
                var historySection = ""
                
                var currentSection = ""
                for line in lines {
                    if line.starts(with: "Current time:") {
                        currentTimeSection = line
                    } else if line.starts(with: "USER MEMORY:") {
                        currentSection = "memory"
                        userMemorySection = line
                    } else if line.starts(with: "CALENDAR EVENTS:") {
                        currentSection = "calendar"
                        calendarSection = line
                    } else if line.starts(with: "REMINDERS:") {
                        currentSection = "reminders"
                        remindersSection = line
                    } else if line.contains("LOCATION:") || line.contains("Current location:") {
                        currentSection = "location"
                        locationSection = line
                    } else if line.starts(with: "CONVERSATION HISTORY:") {
                        currentSection = "history"
                        historySection = line
                    } else if !line.isEmpty {
                        // Append to the current section
                        switch currentSection {
                        case "memory":
                            userMemorySection += "\n" + line
                        case "calendar":
                            calendarSection += "\n" + line
                        case "reminders":
                            remindersSection += "\n" + line
                        case "location":
                            locationSection += "\n" + line
                        case "history":
                            historySection += "\n" + line
                        default:
                            break
                        }
                    }
                }
                
                // 1. Add the time (never cached, always fresh)
                newContent.append(["type": "text", "text": currentTimeSection])
                
                // We can use up to 4 cache_control blocks total (including tool definitions)
                // Since we already use 1 for tools, we have 3 left for context
                // Priority: Memory, Calendar+Reminders combined, History
                
                // We need to compare with the current hashes
                
                // 2. Add user memory (rarely changes, can be cached)
                if !userMemorySection.isEmpty {
                    // Generate a hash from the content to detect changes
                    let currentMemoryHash = userMemorySection.hashValue
                    
                    var memoryBlock: [String: Any] = ["type": "text", "text": userMemorySection]
                    
                    // Check if memory content is the same as last time
                    if currentMemoryHash == APIRequestBuilder.lastMemoryHash {
                        memoryBlock["cache_control"] = ["type": "ephemeral"]
                        print("🧠 Added cache_control to memory section (unchanged)")
                    } else {
                        // Update the hash for next time
                        APIRequestBuilder.lastMemoryHash = currentMemoryHash
                        print("🧠 Memory content changed, not using cache this time")
                    }
                    
                    newContent.append(memoryBlock)
                }
                
                // 3. Add calendar events and reminders (combine to save cache blocks)
                let combinedDataSection = """
                \(calendarSection)
                
                \(remindersSection)
                """
                
                if !combinedDataSection.isEmpty {
                    // Generate a hash from the content to detect changes
                    let currentDataHash = combinedDataSection.hashValue
                    
                    var dataBlock: [String: Any] = ["type": "text", "text": combinedDataSection]
                    
                    // Check if calendar+reminders content is the same as last time
                    if currentDataHash == APIRequestBuilder.lastCalRemHash {
                        dataBlock["cache_control"] = ["type": "ephemeral"]
                        print("🧠 Added cache_control to calendar/reminders section (unchanged)")
                    } else {
                        // Update the hash for next time
                        APIRequestBuilder.lastCalRemHash = currentDataHash
                        print("🧠 Calendar/reminders content changed, not using cache this time")
                    }
                    
                    newContent.append(dataBlock)
                }
                
                // 4. Add location (changes frequently, don't cache)
                if !locationSection.isEmpty {
                    newContent.append(["type": "text", "text": locationSection])
                }
                
                // 5. Add conversation history (grows with each message, consider partial caching)
                if !historySection.isEmpty {
                    // For conversation history, don't try to cache the whole thing since
                    // it will almost always change. Instead, we'll just add it as-is.
                    newContent.append(["type": "text", "text": historySection])
                    print("🧠 Skipping cache for conversation history (changes frequently)")
                }
                
                // Replace the original content with the multi-part content
                if !newContent.isEmpty {
                    firstMessage["content"] = newContent
                    cachedMessages[0] = firstMessage
                    print("🧠 Split context message into \(newContent.count) parts with smart caching")
                }
            }
        }
        
        // Create the request body with enhanced caching
        // Note: In Claude's API, the system field is a string, not an array of objects
        // We can't apply cache_control directly to the system prompt with this format
        return [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "tools": cachedToolDefinitions,
            "stream": true,
            "messages": cachedMessages
        ]
    }
    
    /**
     * Formats the current date and time with timezone information.
     *
     * @return A formatted string representing the current date and time
     */
    static func formatCurrentDateTime() -> String {
        return DateFormatter.formatCurrentDateTimeWithTimezone()
    }
    
    /**
     * Configures the HTTP request headers for Claude API communication.
     *
     * @param request The URLRequest to configure
     * @param apiKey The API key to use for authentication
     */
    static func configureRequestHeaders(for request: inout URLRequest, apiKey: String) {
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // For tool use, we should use the most recent version with tools support
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
    }
    
    /**
     * Creates a context message with all user information.
     * Always includes the current date and time, regardless of when the context was created.
     * Maintains backward compatibility with the original single-block approach,
     * as the caching optimization handles the splitting internally.
     *
     * @param memoryContent The user's memory content
     * @param calendarContext The user's calendar events formatted as a string
     * @param remindersContext The user's reminders formatted as a string
     * @param locationContext The user's location information (if available)
     * @param conversationHistory Recent conversation history formatted as a string
     * @return A dictionary representing the context message with all information
     */
    static func createContextMessage(
        memoryContent: String,
        calendarContext: String,
        remindersContext: String,
        locationContext: String,
        conversationHistory: String
    ) -> [String: Any] {
        // Log context details
        print("🧠 Creating context message:")
        print("🧠 - Memory content length: \(memoryContent.count) chars")
        print("🧠 - Calendar context length: \(calendarContext.count) chars")
        print("🧠 - Reminders context length: \(remindersContext.count) chars")
        print("🧠 - Location context length: \(locationContext.count) chars")
        print("🧠 - Conversation history length: \(conversationHistory.count) chars")
        print("🧠 - Using current time: \(formatCurrentDateTime())")
        
        // Always use fresh timestamp
        let currentTimeString = formatCurrentDateTime()
        
        // Format the context as a single block of text with clear section separators
        // This keeps the same format while allowing the buildRequestBodyWithCaching method
        // to split it into multiple content blocks for efficient caching
        let contextText = """
        Current time: \(currentTimeString)
        
        USER MEMORY:
        \(memoryContent)
        
        CALENDAR EVENTS:
        \(calendarContext)
        
        REMINDERS:
        \(remindersContext)
        
        \(locationContext)
        
        CONVERSATION HISTORY:
        \(conversationHistory)
        """
        
        // Print a snippet of the memory content to verify it's being included
        if memoryContent.count > 0 {
            let memoryPreview = String(memoryContent.prefix(200)) + (memoryContent.count > 200 ? "..." : "")
            print("🧠 Memory content preview: \(memoryPreview)")
        } else {
            print("🧠 Warning: Memory content is empty!")
        }
        
        print("🧠 Total context text length: \(contextText.count) chars")
        
        // Return as a single content block; the buildRequestBodyWithCaching method
        // will split it into multiple blocks with appropriate cache_control settings
        return ["role": "user", "content": [
            ["type": "text", "text": contextText]
        ]]
    }
    
    /**
     * Creates a user message with the user's input.
     *
     * @param text The user's message text
     * @return A dictionary representing the user message
     */
    static func createUserMessage(text: String) -> [String: Any] {
        return ["role": "user", "content": [
            ["type": "text", "text": text]
        ]]
    }
    
    /**
     * Creates a standard greeting message from the assistant.
     *
     * @return A dictionary representing the assistant greeting
     */
    static func createAssistantGreeting() -> [String: Any] {
        return ["role": "assistant", "content": [
            ["type": "text", "text": "I understand. How can I help you today?"]
        ]]
    }
    
    /**
     * Creates a tool results message containing the results of tool use.
     *
     * @param toolResults Array of tool use results
     * @return A dictionary representing the tool results message
     */
    static func createToolResultsMessage(toolResults: [ToolUseResult]) -> [String: Any] {
        var toolResultBlocks: [[String: Any]] = []
        
        for result in toolResults {
            toolResultBlocks.append([
                "type": "tool_result",
                "tool_use_id": result.toolId,
                "content": result.content
            ])
        }
        
        return ["role": "user", "content": toolResultBlocks]
    }
}
