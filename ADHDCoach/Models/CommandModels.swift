import Foundation

// Tool schemas for Claude's function calling API

// Calendar Tool Schemas
struct CalendarAddCommand: Codable {
    let title: String
    let start: String
    let end: String
    let notes: String?
    
    static var schema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "title": ["type": "string", "description": "The title of the calendar event"],
                "start": ["type": "string", "description": "The start date and time in format 'MMM d, yyyy at h:mm a'"],
                "end": ["type": "string", "description": "The end date and time in format 'MMM d, yyyy at h:mm a'"],
                "notes": ["type": "string", "description": "Optional notes for the calendar event"]
            ],
            "required": ["title", "start", "end"]
        ]
    }
}

struct CalendarModifyCommand: Codable {
    let id: String
    let title: String?
    let start: String?
    let end: String?
    let notes: String?
    
    static var schema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "The ID of the calendar event to modify"],
                "title": ["type": "string", "description": "Optional new title for the calendar event"],
                "start": ["type": "string", "description": "Optional new start date and time in format 'MMM d, yyyy at h:mm a'"],
                "end": ["type": "string", "description": "Optional new end date and time in format 'MMM d, yyyy at h:mm a'"],
                "notes": ["type": "string", "description": "Optional new notes for the calendar event"]
            ],
            "required": ["id"]
        ]
    }
}

struct CalendarDeleteCommand: Codable {
    let id: String
    
    static var schema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "The ID of the calendar event to delete"]
            ],
            "required": ["id"]
        ]
    }
}

// Reminder Tool Schemas
struct ReminderAddCommand: Codable {
    let title: String
    let due: String?
    let notes: String?
    let list: String?
    
    static var schema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "title": ["type": "string", "description": "The title of the reminder"],
                "due": ["type": "string", "description": "Optional due date and time in format 'MMM d, yyyy at h:mm a'"],
                "notes": ["type": "string", "description": "Optional notes for the reminder"],
                "list": ["type": "string", "description": "Optional reminder list name"]
            ],
            "required": ["title"]
        ]
    }
}

struct ReminderModifyCommand: Codable {
    let id: String
    let title: String?
    let due: String?
    let notes: String?
    let list: String?
    
    static var schema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "The ID of the reminder to modify"],
                "title": ["type": "string", "description": "Optional new title for the reminder"],
                "due": ["type": "string", "description": "Optional new due date and time in format 'MMM d, yyyy at h:mm a'"],
                "notes": ["type": "string", "description": "Optional new notes for the reminder"],
                "list": ["type": "string", "description": "Optional new reminder list name"]
            ],
            "required": ["id"]
        ]
    }
}

struct ReminderDeleteCommand: Codable {
    let id: String
    
    static var schema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "The ID of the reminder to delete"]
            ],
            "required": ["id"]
        ]
    }
}

// Memory Tool Schemas
struct MemoryAddCommand: Codable {
    let content: String
    let category: String
    let importance: Int?
    
    static var schema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "content": ["type": "string", "description": "The content of the memory to add"],
                "category": ["type": "string", "description": "The category for the memory (Personal Information, Preferences, Behavior Patterns, Daily Basics, Medications, Goals, Miscellaneous Notes)"],
                "importance": ["type": "integer", "description": "Optional importance level (1-5, with 5 being most important)"]
            ],
            "required": ["content", "category"]
        ]
    }
}

struct MemoryRemoveCommand: Codable {
    let content: String
    
    static var schema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "content": ["type": "string", "description": "The exact content of the memory to remove"]
            ],
            "required": ["content"]
        ]
    }
}
