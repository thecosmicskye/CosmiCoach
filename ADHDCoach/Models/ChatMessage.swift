import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    let timestamp: Date
    let isUser: Bool
    var isComplete: Bool = true
    
    init(id: UUID = UUID(), content: String, timestamp: Date = Date(), isUser: Bool, isComplete: Bool = true) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
        self.isUser = isUser
        self.isComplete = isComplete
    }
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    // For serialization/deserialization
    enum CodingKeys: String, CodingKey {
        case id, content, timestamp, isUser, isComplete
    }
}
