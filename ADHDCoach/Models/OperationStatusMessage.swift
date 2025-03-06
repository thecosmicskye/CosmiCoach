import Foundation

enum OperationStatus: String, Codable {
    case inProgress = "In Progress"
    case success = "Success"
    case failure = "Failure"
    
    var icon: String {
        switch self {
        case .inProgress: return "hourglass"
        case .success: return "checkmark.circle"
        case .failure: return "xmark.circle"
        }
    }
}

enum OperationType: String, Codable {
    // Calendar operations
    case addCalendarEvent = "Adding Calendar Event"
    case updateCalendarEvent = "Updating Calendar Event" 
    case deleteCalendarEvent = "Deleting Calendar Event"
    
    // Reminder operations
    case addReminder = "Adding Reminder"
    case updateReminder = "Updating Reminder"
    case deleteReminder = "Deleting Reminder"
    
    // Memory operations
    case addMemory = "Adding Memory"
    case updateMemory = "Updating Memory"
    case deleteMemory = "Deleting Memory"
    
    // Batch operations
    case batchCalendarOperation = "Calendar Batch Operation"
    case batchReminderOperation = "Reminder Batch Operation"
    case batchMemoryOperation = "Memory Batch Operation"
    
    var displayTextSuccess: String {
        switch self {
        case .addCalendarEvent: return "Added Calendar Event"
        case .updateCalendarEvent: return "Updated Calendar Event"
        case .deleteCalendarEvent: return "Deleted Calendar Event"
        case .addReminder: return "Added Reminder"
        case .updateReminder: return "Updated Reminder"
        case .deleteReminder: return "Deleted Reminder"
        case .addMemory: return "Added Memory"
        case .updateMemory: return "Updated Memory"
        case .deleteMemory: return "Deleted Memory"
        case .batchCalendarOperation: return "Calendar Batch Operation"
        case .batchReminderOperation: return "Reminder Batch Operation" 
        case .batchMemoryOperation: return "Memory Batch Operation"
        }
    }
}

struct OperationStatusMessage: Identifiable, Codable {
    let id: UUID
    let operationType: String
    var status: OperationStatus
    let timestamp: Date
    var details: String?
    
    init(id: UUID = UUID(), operationType: OperationType, status: OperationStatus = .inProgress, timestamp: Date = Date(), details: String? = nil) {
        self.id = id
        self.operationType = operationType.rawValue
        self.status = status
        self.timestamp = timestamp
        self.details = details
    }
    
    // For backward compatibility
    init(id: UUID = UUID(), operationType: String, status: OperationStatus = .inProgress, timestamp: Date = Date(), details: String? = nil) {
        self.id = id
        self.operationType = operationType
        self.status = status
        self.timestamp = timestamp
        self.details = details
    }
    
    var displayText: String {
        switch status {
        case .inProgress:
            return "\(operationType)..."
        case .success:
            // Try to convert to enum for nicer display
            if let opType = OperationType(rawValue: operationType) {
                return opType.displayTextSuccess
            }
            return operationType
        case .failure:
            return "\(operationType) Failed\(details != nil ? ": \(details!)" : "")"
        }
    }
    
    // For serialization/deserialization
    enum CodingKeys: String, CodingKey {
        case id, operationType, status, timestamp, details
    }
}
