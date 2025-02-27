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

struct OperationStatusMessage: Identifiable, Codable {
    let id: UUID
    let operationType: String
    var status: OperationStatus
    let timestamp: Date
    var details: String?
    
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
            return "\(operationType) Succeeded"
        case .failure:
            return "\(operationType) Failed\(details != nil ? ": \(details!)" : "")"
        }
    }
    
    // For serialization/deserialization
    enum CodingKeys: String, CodingKey {
        case id, operationType, status, timestamp, details
    }
}
