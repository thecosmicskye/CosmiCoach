import Foundation

/**
 * ChatPersistenceManager handles the persistence of chat messages and related state.
 *
 * This class is responsible for:
 * - Loading and saving chat messages to/from UserDefaults
 * - Managing streaming message state persistence
 * - Handling incomplete messages from previous sessions
 * - Formatting conversation history for Claude
 */
class ChatPersistenceManager {
    
    /**
     * Loads chat messages and related state from UserDefaults.
     *
     * @return A tuple containing:
     *   - messages: Array of chat messages
     *   - currentStreamingMessageId: ID of the message currently being streamed (if any)
     *   - isProcessing: Whether a message is currently being processed
     */
    func loadMessages() -> (messages: [ChatMessage], currentStreamingMessageId: UUID?, isProcessing: Bool) {
        var messages: [ChatMessage] = []
        var currentStreamingMessageId: UUID? = nil
        var isProcessing = false
        
        // Load messages from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "chat_messages"),
           let decoded = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            messages = decoded
            
            // Load saved streaming state (if any)
            if let savedStreamingIdString = UserDefaults.standard.string(forKey: "streaming_message_id"),
               let savedStreamingId = UUID(uuidString: savedStreamingIdString) {
                // Only set if the message actually exists
                if messages.contains(where: { $0.id == savedStreamingId }) {
                    currentStreamingMessageId = savedStreamingId
                }
            }
            
            // Load processing state
            isProcessing = UserDefaults.standard.bool(forKey: "chat_processing_state")
        }
        
        return (messages, currentStreamingMessageId, isProcessing)
    }
    
    /**
     * Loads chat messages and related state from UserDefaults asynchronously.
     * This async version prevents blocking the main thread during app launch.
     *
     * @return A tuple containing messages, streaming ID, and processing state
     */
    func loadMessagesAsync() async -> (messages: [ChatMessage], isProcessing: Bool, currentStreamingMessageId: UUID?) {
        return await withCheckedContinuation { continuation in
            // Run on a background thread
            DispatchQueue.global(qos: .userInitiated).async {
                var messages: [ChatMessage] = []
                var currentStreamingMessageId: UUID? = nil
                var isProcessing = false
                
                // Load messages from UserDefaults
                if let data = UserDefaults.standard.data(forKey: "chat_messages"),
                   let decoded = try? JSONDecoder().decode([ChatMessage].self, from: data) {
                    messages = decoded
                    
                    // Load saved streaming state (if any)
                    if let savedStreamingIdString = UserDefaults.standard.string(forKey: "streaming_message_id"),
                       let savedStreamingId = UUID(uuidString: savedStreamingIdString) {
                        // Only set if the message actually exists
                        if messages.contains(where: { $0.id == savedStreamingId }) {
                            currentStreamingMessageId = savedStreamingId
                        }
                    }
                    
                    // Load processing state
                    isProcessing = UserDefaults.standard.bool(forKey: "chat_processing_state")
                }
                
                continuation.resume(returning: (messages, isProcessing, currentStreamingMessageId))
            }
        }
    }
    
    /**
     * Saves chat messages and related state to UserDefaults.
     *
     * @param messages Array of chat messages to save
     * @param isProcessing Whether a message is currently being processed
     * @param currentStreamingMessageId ID of the message currently being streamed (if any)
     */
    func saveMessages(messages: [ChatMessage], isProcessing: Bool, currentStreamingMessageId: UUID?) {
        // Save messages to UserDefaults for persistence
        if let encoded = try? JSONEncoder().encode(messages) {
            UserDefaults.standard.set(encoded, forKey: "chat_messages")
            
            // Save processing state for recovery after app restart
            UserDefaults.standard.set(isProcessing, forKey: "chat_processing_state")
            if let id = currentStreamingMessageId {
                UserDefaults.standard.set(id.uuidString, forKey: "streaming_message_id")
            } else {
                UserDefaults.standard.removeObject(forKey: "streaming_message_id")
            }
        }
    }
    
    /**
     * Resets any incomplete messages from previous sessions.
     *
     * This handles cases where the app was closed during message streaming,
     * marking incomplete messages as complete and adding an interruption tag.
     *
     * @param messages Reference to the messages array to modify
     * @return True if any messages were reset, false otherwise
     */
    func resetIncompleteMessages(messages: inout [ChatMessage]) -> Bool {
        var anyMessagesReset = false
        
        // Find any incomplete messages and mark them as complete
        // This handles cases where the app was closed during message streaming
        for (index, message) in messages.enumerated() {
            if !message.isComplete {
                // Mark as complete
                messages[index].isComplete = true
                anyMessagesReset = true
                
                // Only add the interruption tag if it's not already there
                if !message.content.hasSuffix("[Message was interrupted]") {
                    // Add the tag only if there's actual content
                    if !message.content.isEmpty {
                        messages[index].content += " [Message was interrupted]"
                    } else {
                        messages[index].content = "[Message was interrupted]"
                    }
                }
            }
        }
        
        if anyMessagesReset {
            // Clear any saved state in UserDefaults
            UserDefaults.standard.removeObject(forKey: "streaming_message_id")
            UserDefaults.standard.removeObject(forKey: "last_streaming_content")
            UserDefaults.standard.set(false, forKey: "chat_processing_state")
            
            // Save changes
            if let encoded = try? JSONEncoder().encode(messages) {
                UserDefaults.standard.set(encoded, forKey: "chat_messages")
            }
        }
        
        return anyMessagesReset
    }
    
    /**
     * Formats recent conversation history for Claude.
     *
     * This creates a formatted string of recent messages to provide
     * conversation context to Claude.
     *
     * @param messages Array of chat messages
     * @return Formatted string of recent conversation history
     */
    func formatRecentConversationHistory(messages: [ChatMessage]) -> String {
        // Get the most recent messages that fit within token limit
        // This is a simplified implementation - in a real app, you'd want to count tokens properly
        let recentMessages = messages.suffix(20) // Just use last 20 messages as a simple approach
        
        return recentMessages.map { message in
            let role = message.isUser ? "User" : "Assistant"
            let time = DateFormatter.shared.string(from: message.timestamp)
            return "[\(time)] \(role): \(message.content)"
        }.joined(separator: "\n\n")
    }
    
    /**
     * Clears all chat messages and related state from UserDefaults.
     */
    func clearAllMessages() {
        UserDefaults.standard.removeObject(forKey: "chat_messages")
        UserDefaults.standard.removeObject(forKey: "streaming_message_id")
        UserDefaults.standard.removeObject(forKey: "last_streaming_content")
        UserDefaults.standard.set(false, forKey: "chat_processing_state")
    }
}
