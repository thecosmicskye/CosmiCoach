import Foundation

// Models for JSON-based command parsing

// Calendar Commands
struct CalendarAddCommand: Decodable {
    let title: String
    let start: String
    let end: String
    let notes: String?
}

struct CalendarModifyCommand: Decodable {
    let id: String
    let title: String?
    let start: String?
    let end: String?
    let notes: String?
}

struct CalendarDeleteCommand: Decodable {
    let id: String
}

// Reminder Commands
struct ReminderAddCommand: Decodable {
    let title: String
    let due: String?
    let notes: String?
    let list: String?
}

struct ReminderModifyCommand: Decodable {
    let id: String
    let title: String?
    let due: String?
    let notes: String?
    let list: String?
}

struct ReminderDeleteCommand: Decodable {
    let id: String
}

// Memory Commands
struct MemoryAddCommand: Decodable {
    let content: String
    let category: String
    let importance: Int?
}

struct MemoryRemoveCommand: Decodable {
    let content: String
}
