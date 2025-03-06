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
    
    // MARK: - Request Building
    
    /**
     * Builds a request body with prompt caching enabled.
     *
     * This method creates a request body with cache_control parameters
     * to enable prompt caching for system prompt and tool definitions.
     * It follows Anthropic's documentation for proper cache_control placement.
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
        // Add cache control to tool definitions
        var cachedToolDefinitions = toolDefinitions
        if !cachedToolDefinitions.isEmpty {
            // Add cache_control to the last tool definition
            var lastTool = cachedToolDefinitions[cachedToolDefinitions.count - 1]
            lastTool["cache_control"] = ["type": "ephemeral"]
            cachedToolDefinitions[cachedToolDefinitions.count - 1] = lastTool
        }
        
        // Add cache control to context message if it exists and is the first message
        var cachedMessages = messages
        if !cachedMessages.isEmpty {
            // Check if the first message is a context message from the user
            if var firstMessage = cachedMessages.first,
               let role = firstMessage["role"] as? String, role == "user",
               var content = firstMessage["content"] as? [[String: Any]],
               !content.isEmpty {
                
                // Add cache_control to the last content block of the first message
                if var lastContentBlock = content.last {
                    lastContentBlock["cache_control"] = ["type": "ephemeral"]
                    content[content.count - 1] = lastContentBlock
                    firstMessage["content"] = content
                    cachedMessages[0] = firstMessage
                    
                    print("🧠 Added cache_control to context message")
                }
            }
        }
        
        // Create the request body with caching enabled
        // Note: system should be a string, not an array of objects
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
     *
     * @param memoryContent The user's memory content
     * @param calendarContext The user's calendar events formatted as a string
     * @param remindersContext The user's reminders formatted as a string
     * @param locationContext The user's location information (if available)
     * @param conversationHistory Recent conversation history formatted as a string
     * @return A dictionary representing the context message
     */
    static func createContextMessage(
        memoryContent: String,
        calendarContext: String,
        remindersContext: String,
        locationContext: String,
        conversationHistory: String
    ) -> [String: Any] {
        return ["role": "user", "content": [
            ["type": "text", "text": """
            Current time: \(formatCurrentDateTime())
            
            USER MEMORY:
            \(memoryContent)
            
            CALENDAR EVENTS:
            \(calendarContext)
            
            REMINDERS:
            \(remindersContext)
            
            \(locationContext)
            
            CONVERSATION HISTORY:
            \(conversationHistory)
            """]
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
