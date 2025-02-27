import Foundation

struct MemoryItem: Identifiable, Codable {
    let id: UUID
    let content: String
    let category: MemoryCategory
    let timestamp: Date
    var importance: Int // 1-5 scale, with 5 being most important
    
    init(id: UUID = UUID(), content: String, category: MemoryCategory, importance: Int = 3, timestamp: Date = Date()) {
        self.id = id
        self.content = content
        self.category = category
        self.importance = importance
        self.timestamp = timestamp
    }
}

enum MemoryCategory: String, Codable, CaseIterable {
    case personalInfo = "Personal Information"
    case preferences = "Preferences"
    case patterns = "Behavior Patterns"
    case dailyBasics = "Daily Basics"
    case medications = "Medications"
    case goals = "Goals"
    case notes = "Miscellaneous Notes"
    
    var description: String {
        switch self {
        case .personalInfo:
            return "Basic information about the user"
        case .preferences:
            return "User preferences and likes/dislikes"
        case .patterns:
            return "Patterns in user behavior and task completion"
        case .dailyBasics:
            return "Tracking of daily basics like eating and drinking water"
        case .medications:
            return "Medication information and tracking"
        case .goals:
            return "Short and long-term goals"
        case .notes:
            return "Miscellaneous information to remember"
        }
    }
}
