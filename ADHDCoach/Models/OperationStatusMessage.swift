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

enum OperationAction: String, Codable {
    case add = "Adding"
    case update = "Updating"
    case delete = "Deleting"
    case batch = "Batch"
    
    var pastTense: String {
        switch self {
        case .add: return "Added"
        case .update: return "Updated"
        case .delete: return "Deleted"
        case .batch: return "" // Just use the operation type's action from the tool context
        }
    }
}

enum OperationItemType: String, Codable {
    case calendarEvent = "Calendar Event"
    case reminder = "Reminder"
    case memory = "Memory"
    
    var plural: String {
        switch self {
        case .calendarEvent: return "Calendar Events"
        case .reminder: return "Reminders"
        case .memory: return "Memories"
        }
    }
}

enum OperationType: String, Codable, Equatable {
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
    
    var action: OperationAction {
        switch self {
        case .addCalendarEvent, .addReminder, .addMemory: 
            return .add
        case .updateCalendarEvent, .updateReminder, .updateMemory: 
            return .update
        case .deleteCalendarEvent, .deleteReminder, .deleteMemory: 
            return .delete
        case .batchCalendarOperation, .batchReminderOperation, .batchMemoryOperation: 
            return .batch
        }
    }
    
    var itemType: OperationItemType {
        switch self {
        case .addCalendarEvent, .updateCalendarEvent, .deleteCalendarEvent, .batchCalendarOperation: 
            return .calendarEvent
        case .addReminder, .updateReminder, .deleteReminder, .batchReminderOperation: 
            return .reminder
        case .addMemory, .updateMemory, .deleteMemory, .batchMemoryOperation: 
            return .memory
        }
    }
    
    // Returns the operation type for a given action and item type combination
    static func operationType(for action: OperationAction, itemType: OperationItemType) -> OperationType {
        switch action {
        case .add:
            switch itemType {
            case .calendarEvent: return .addCalendarEvent
            case .reminder: return .addReminder
            case .memory: return .addMemory
            }
        case .update:
            switch itemType {
            case .calendarEvent: return .updateCalendarEvent
            case .reminder: return .updateReminder
            case .memory: return .updateMemory
            }
        case .delete:
            switch itemType {
            case .calendarEvent: return .deleteCalendarEvent
            case .reminder: return .deleteReminder
            case .memory: return .deleteMemory
            }
        case .batch:
            switch itemType {
            case .calendarEvent: return .batchCalendarOperation
            case .reminder: return .batchReminderOperation
            case .memory: return .batchMemoryOperation
            }
        }
    }
    
    var displayTextSuccess: String {
        switch self {
        case .addCalendarEvent, .updateCalendarEvent, .deleteCalendarEvent,
             .addReminder, .updateReminder, .deleteReminder,
             .addMemory, .updateMemory, .deleteMemory:
            // This will be handled by the count-aware displayText in OperationStatusMessage
            return ""
        case .batchCalendarOperation: return "Calendar Batch Operation"
        case .batchReminderOperation: return "Reminder Batch Operation" 
        case .batchMemoryOperation: return "Memory Batch Operation"
        }
    }
}

struct OperationStatusMessage: Identifiable, Codable, Equatable {
    // Conformance to Equatable
    static func == (lhs: OperationStatusMessage, rhs: OperationStatusMessage) -> Bool {
        return lhs.id == rhs.id &&
               lhs.operationType == rhs.operationType &&
               lhs.status == rhs.status &&
               lhs.timestamp == rhs.timestamp &&
               lhs.details == rhs.details &&
               lhs.count == rhs.count
    }
    let id: UUID
    let operationType: OperationType
    var status: OperationStatus
    let timestamp: Date
    var details: String?
    var count: Int = 1
    
    init(id: UUID = UUID(), operationType: OperationType, status: OperationStatus = .inProgress, timestamp: Date = Date(), details: String? = nil, count: Int = 1) {
        self.id = id
        self.operationType = operationType
        self.status = status
        self.timestamp = timestamp
        self.details = details
        self.count = max(1, count)
    }
    
    var displayText: String {
        switch status {
        case .inProgress:
            return "\(operationType.rawValue)..."
        case .success:
            let action = operationType.action.pastTense
            let itemType = count > 1 ? operationType.itemType.plural : operationType.itemType.rawValue
            
            // Handle batch operations - the actual action is in the context
            if operationType.action == .batch {
                // Here we would typically use the operation context, but instead
                // we'll rely on the correct operationType being set for batch operations
                return "\(action) \(count) \(itemType)"
            } else {
                return "\(action) \(count) \(itemType)"
            }
        case .failure:
            return "\(operationType.rawValue) Failed\(details != nil ? ": \(details!)" : "")"
        }
    }
    
    // Create a combined status message from multiple messages with the same action and item type
    static func combinedStatusMessage(from messages: [OperationStatusMessage]) -> OperationStatusMessage? {
        guard !messages.isEmpty else { return nil }
        
        // Create dictionary keys to group by
        struct GroupKey: Hashable {
            let action: OperationAction
            let itemType: OperationItemType
        }
        
        // Group by action and item type using a struct key
        let groupedMessages = Dictionary(grouping: messages) { message in
            GroupKey(action: message.operationType.action, itemType: message.operationType.itemType)
        }
        
        // Create combined messages for each group
        let combinedMessages = groupedMessages.map { key, messages in
            // Use the most recent message as a base
            let sortedMessages = messages.sorted { $0.timestamp > $1.timestamp }
            let baseMessage = sortedMessages.first!
            
            // Get the total count
            let totalCount = messages.reduce(0) { $0 + $1.count }
            
            // Get the representative operation type from our utility method
            let representativeOperationType = OperationType.operationType(
                for: key.action, 
                itemType: key.itemType
            )
            
            return OperationStatusMessage(
                id: baseMessage.id,
                operationType: representativeOperationType,
                status: baseMessage.status,
                timestamp: baseMessage.timestamp,
                details: baseMessage.details,
                count: totalCount
            )
        }
        
        return combinedMessages.first
    }
    
    // Combine multiple messages into grouped messages by action and item type
    static func combineMessages(_ messages: [OperationStatusMessage]) -> [OperationStatusMessage] {
        guard !messages.isEmpty else { return [] }
        
        // Create dictionary keys to group by
        struct GroupKey: Hashable {
            let action: OperationAction
            let itemType: OperationItemType
        }
        
        // Group by action and item type using a struct key
        let groupedMessages = Dictionary(grouping: messages) { message in
            GroupKey(action: message.operationType.action, itemType: message.operationType.itemType)
        }
        
        // Create combined messages for each group
        return groupedMessages.map { key, messages in
            // Use the most recent message as a base
            let sortedMessages = messages.sorted { $0.timestamp > $1.timestamp }
            let baseMessage = sortedMessages.first!
            
            // Get the total count
            let totalCount = messages.reduce(0) { $0 + $1.count }
            
            // Get the representative operation type from our utility method
            let representativeOperationType = OperationType.operationType(
                for: key.action, 
                itemType: key.itemType
            )
            
            return OperationStatusMessage(
                id: baseMessage.id,
                operationType: representativeOperationType,
                status: baseMessage.status,
                timestamp: baseMessage.timestamp,
                details: baseMessage.details,
                count: totalCount
            )
        }
    }
    
    // For serialization/deserialization
    enum CodingKeys: String, CodingKey {
        case id, operationType, status, timestamp, details, count
    }
    
    // Custom encoding for operationType (enum to string)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(operationType.rawValue, forKey: .operationType)
        try container.encode(status, forKey: .status)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(details, forKey: .details)
        try container.encode(count, forKey: .count)
    }
    
    // Custom decoding for operationType (string to enum)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let operationTypeString = try container.decode(String.self, forKey: .operationType)
        guard let opType = OperationType(rawValue: operationTypeString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .operationType,
                in: container,
                debugDescription: "Invalid operation type: \(operationTypeString)"
            )
        }
        operationType = opType
        status = try container.decode(OperationStatus.self, forKey: .status)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        details = try container.decodeIfPresent(String.self, forKey: .details)
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 1
    }
}
