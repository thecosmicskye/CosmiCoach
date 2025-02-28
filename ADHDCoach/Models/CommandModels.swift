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

struct CalendarAddBatchCommand: Codable {
    let events: [CalendarEvent]
    
    struct CalendarEvent: Codable {
        let title: String
        let start: String
        let end: String
        let notes: String?
    }
    
    static var schema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "events": [
                    "type": "array",
                    "description": "Array of calendar events to add",
                    "items": [
                        "type": "object",
                        "properties": [
                            "title": ["type": "string", "description": "The title of the calendar event"],
                            "start": ["type": "string", "description": "The start date and time in format 'MMM d, yyyy at h:mm a'"],
                            "end": ["type": "string", "description": "The end date and time in format 'MMM d, yyyy at h:mm a'"],
                            "notes": ["type": "string", "description": "Optional notes for the calendar event"]
                        ],
                        "required": ["title", "start", "end"]
                    ]
                ]
            ],
            "required": ["events"]
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

struct CalendarModifyBatchCommand: Codable {
    let events: [CalendarEvent]
    
    struct CalendarEvent: Codable {
        let id: String
        let title: String?
        let start: String?
        let end: String?
        let notes: String?
    }
    
    static var schema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "events": [
                    "type": "array",
                    "description": "Array of calendar events to modify",
                    "items": [
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
                ]
            ],
            "required": ["events"]
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

struct CalendarDeleteBatchCommand: Codable {
    let ids: [String]
    
    static var schema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "ids": [
                    "type": "array",
                    "description": "Array of calendar event IDs to delete",
                    "items": ["type": "string"]
                ]
            ],
            "required": ["ids"]
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

struct ReminderAddBatchCommand: Codable {
    let reminders: [Reminder]
    
    struct Reminder: Codable {
        let title: String
        let due: String?
        let notes: String?
        let list: String?
    }
    
    static var schema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "reminders": [
                    "type": "array",
                    "description": "Array of reminders to add",
                    "items": [
                        "type": "object",
                        "properties": [
                            "title": ["type": "string", "description": "The title of the reminder"],
                            "due": ["type": "string", "description": "Optional due date and time in format 'MMM d, yyyy at h:mm a'"],
                            "notes": ["type": "string", "description": "Optional notes for the reminder"],
                            "list": ["type": "string", "description": "Optional reminder list name"]
                        ],
                        "required": ["title"]
                    ]
                ]
            ],
            "required": ["reminders"]
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

struct ReminderModifyBatchCommand: Codable {
    let reminders: [Reminder]
    
    struct Reminder: Codable {
        let id: String
        let title: String?
        let due: String?
        let notes: String?
        let list: String?
    }
    
    static var schema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "reminders": [
                    "type": "array",
                    "description": "Array of reminders to modify",
                    "items": [
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
                ]
            ],
            "required": ["reminders"]
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

struct ReminderDeleteBatchCommand: Codable {
    let ids: [String]
    
    static var schema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "ids": [
                    "type": "array",
                    "description": "Array of reminder IDs to delete",
                    "items": ["type": "string"]
                ]
            ],
            "required": ["ids"]
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

struct MemoryAddBatchCommand: Codable {
    let memories: [Memory]
    
    struct Memory: Codable {
        let content: String
        let category: String
        let importance: Int?
    }
    
    static var schema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "memories": [
                    "type": "array",
                    "description": "Array of memories to add",
                    "items": [
                        "type": "object",
                        "properties": [
                            "content": ["type": "string", "description": "The content of the memory to add"],
                            "category": ["type": "string", "description": "The category for the memory (Personal Information, Preferences, Behavior Patterns, Daily Basics, Medications, Goals, Miscellaneous Notes)"],
                            "importance": ["type": "integer", "description": "Optional importance level (1-5, with 5 being most important)"]
                        ],
                        "required": ["content", "category"]
                    ]
                ]
            ],
            "required": ["memories"]
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

struct MemoryRemoveBatchCommand: Codable {
    let contents: [String]
    
    static var schema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "contents": [
                    "type": "array",
                    "description": "Array of memory contents to remove",
                    "items": ["type": "string"]
                ]
            ],
            "required": ["contents"]
        ]
    }
}
