import Foundation

/**
 * ChatOperationStatusManager handles the tracking and persistence of operation status messages.
 *
 * This class is responsible for:
 * - Managing status messages for operations triggered by chat messages
 * - Persisting status messages to UserDefaults
 * - Retrieving status messages for display in the UI
 * - Updating status messages as operations progress
 */
class ChatOperationStatusManager {
    /// Maps message IDs to their associated operation status messages
    private var operationStatusMessages: [UUID: [OperationStatusMessage]] = [:]
    
    /**
     * Initializes the manager and loads any saved operation status messages.
     */
    init() {
        loadOperationStatusMessages()
    }
    
    /**
     * Returns all operation status messages associated with a specific chat message.
     *
     * @param messageId The UUID of the chat message
     * @return An array of operation status messages
     */
    func statusMessagesForMessage(_ messageId: UUID) -> [OperationStatusMessage] {
        return operationStatusMessages[messageId] ?? []
    }
    
    /**
     * Returns combined operation status messages for a specific chat message.
     * Similar operations (same action and item type) will be combined with count.
     *
     * @param messageId The UUID of the chat message
     * @return An array of combined operation status messages
     */
    func combinedStatusMessagesForMessage(_ messageId: UUID) -> [OperationStatusMessage] {
        let messages = statusMessagesForMessage(messageId)
        return OperationStatusMessage.combineMessages(messages)
    }
    
    /**
     * Adds a new operation status message for a specific chat message.
     *
     * @param messageId The UUID of the chat message
     * @param operationType The type of operation (using the OperationType enum)
     * @param status The current status of the operation (default: .inProgress)
     * @param details Optional details about the operation
     * @param count The number of items affected (default: 1)
     * @return The newly created operation status message
     */
    func addOperationStatusMessage(
        forMessageId messageId: UUID,
        operationType: OperationType,
        status: OperationStatus = .inProgress,
        details: String? = nil,
        count: Int = 1
    ) -> OperationStatusMessage {
        let statusMessage = OperationStatusMessage(
            operationType: operationType,
            status: status,
            details: details,
            count: count
        )
        
        // Initialize the array if it doesn't exist
        if operationStatusMessages[messageId] == nil {
            operationStatusMessages[messageId] = []
        }
        
        // Add the status message
        operationStatusMessages[messageId]?.append(statusMessage)
        
        // Save to persistence
        saveOperationStatusMessages()
        
        return statusMessage
    }
    
    // Note: The string-based version has been removed as it's no longer needed
    
    /**
     * Updates an existing operation status message.
     *
     * @param messageId The UUID of the chat message
     * @param statusMessageId The UUID of the status message to update
     * @param status The new status of the operation
     * @param details Optional new details about the operation
     * @param count Optional count of items affected (maintains original count if not provided)
     */
    func updateOperationStatusMessage(
        forMessageId messageId: UUID,
        statusMessageId: UUID,
        status: OperationStatus,
        details: String? = nil,
        count: Int? = nil
    ) {
        // Find the status message
        if var statusMessages = operationStatusMessages[messageId],
           let index = statusMessages.firstIndex(where: { $0.id == statusMessageId }) {
            // Update the status
            statusMessages[index].status = status
            
            // Update details if provided
            if let details = details {
                statusMessages[index].details = details
            }
            
            // Update count if provided, otherwise maintain the existing count
            if let count = count {
                statusMessages[index].count = count
            }
            
            // Save the updated array
            operationStatusMessages[messageId] = statusMessages
            
            // Save to persistence
            saveOperationStatusMessages()
        }
    }
    
    /**
     * Removes an operation status message.
     *
     * @param messageId The UUID of the chat message
     * @param statusMessageId The UUID of the status message to remove
     */
    func removeOperationStatusMessage(forMessageId messageId: UUID, statusMessageId: UUID) {
        // Find and remove the status message
        if var statusMessages = operationStatusMessages[messageId] {
            statusMessages.removeAll(where: { $0.id == statusMessageId })
            
            // Update the array or remove it if empty
            if statusMessages.isEmpty {
                operationStatusMessages.removeValue(forKey: messageId)
            } else {
                operationStatusMessages[messageId] = statusMessages
            }
            
            // Save to persistence
            saveOperationStatusMessages()
        }
    }
    
    /**
     * Saves operation status messages to UserDefaults for persistence.
     */
    func saveOperationStatusMessages() {
        if let encoded = try? JSONEncoder().encode(operationStatusMessages) {
            UserDefaults.standard.set(encoded, forKey: "operation_status_messages")
        }
    }
    
    /**
     * Loads operation status messages from UserDefaults.
     *
     * @return A dictionary mapping message IDs to their status messages
     */
    @discardableResult
    func loadOperationStatusMessages() -> [UUID: [OperationStatusMessage]] {
        if let data = UserDefaults.standard.data(forKey: "operation_status_messages"),
           let decoded = try? JSONDecoder().decode([UUID: [OperationStatusMessage]].self, from: data) {
            operationStatusMessages = decoded
        }
        return operationStatusMessages
    }
}
