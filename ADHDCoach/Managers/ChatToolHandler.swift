import Foundation

/**
 * ChatToolHandler manages tool definitions and processing for Claude API integration.
 *
 * This class is responsible for:
 * - Providing tool definitions that Claude can use
 * - Processing memory updates from Claude's responses
 * - Providing helper methods for tool processing
 */
class ChatToolHandler {
    /// Callback for processing tool use requests from Claude
    /// Parameters:
    /// - toolName: The name of the tool to use
    /// - toolId: The unique ID of the tool use request
    /// - toolInput: The input parameters for the tool
    /// - messageId: The ID of the message associated with this tool use
    /// - chatManager: Reference to the ChatManager for status updates
    /// Returns: The result of the tool use as a string
    var processToolUseCallback: ((String, String, [String: Any], UUID?, ChatManager) async -> String)?
    
    /**
     * Returns the tool definitions that Claude can use.
     *
     * These definitions include calendar, reminder, and memory tools
     * with their input schemas and descriptions.
     *
     * @return An array of tool definitions in the format expected by Claude API
     */
    func getToolDefinitions() -> [[String: Any]] {
        return [
            // Calendar Tools - Single item operations
            [
                "name": "add_calendar_event",
                "description": "Add a new calendar event to the user's calendar. You MUST use this tool when the user wants to add a single event to their calendar.",
                "input_schema": CalendarAddCommand.schema
            ],
            [
                "name": "modify_calendar_event",
                "description": "Modify an existing calendar event in the user's calendar. Use this tool when the user wants to change a single existing event.",
                "input_schema": CalendarModifyCommand.schema
            ],
            [
                "name": "delete_calendar_event",
                "description": "Delete an existing calendar event from the user's calendar. Use this tool when the user wants to remove a single event.",
                "input_schema": CalendarDeleteCommand.schema
            ],
            
            // Calendar Tools - Batch operations
            [
                "name": "add_calendar_events_batch",
                "description": "Add multiple calendar events to the user's calendar at once. Use this tool when the user wants to add multiple events in a single operation.",
                "input_schema": CalendarAddBatchCommand.schema
            ],
            [
                "name": "modify_calendar_events_batch",
                "description": "Modify multiple existing calendar events in the user's calendar at once. Use this tool when the user wants to change multiple existing events in a single operation.",
                "input_schema": CalendarModifyBatchCommand.schema
            ],
            [
                "name": "delete_calendar_events_batch",
                "description": "Delete multiple existing calendar events from the user's calendar at once. Use this tool when the user wants to remove multiple events in a single operation.",
                "input_schema": CalendarDeleteBatchCommand.schema
            ],
            
            // Reminder Tools - Single item operations
            [
                "name": "add_reminder",
                "description": "Add a new reminder to the user's reminders list. You MUST use this tool when the user wants to add a single reminder.",
                "input_schema": ReminderAddCommand.schema
            ],
            [
                "name": "modify_reminder",
                "description": "Modify an existing reminder in the user's reminders. Use this tool when the user wants to change a single existing reminder.",
                "input_schema": ReminderModifyCommand.schema
            ],
            [
                "name": "delete_reminder",
                "description": "Delete an existing reminder from the user's reminders. Use this tool when the user wants to remove a single reminder.",
                "input_schema": ReminderDeleteCommand.schema
            ],
            
            // Reminder Tools - Batch operations
            [
                "name": "add_reminders_batch",
                "description": "Add multiple reminders to the user's reminders list at once. Use this tool when the user wants to add multiple reminders in a single operation.",
                "input_schema": ReminderAddBatchCommand.schema
            ],
            [
                "name": "modify_reminders_batch",
                "description": "Modify multiple existing reminders in the user's reminders at once. Use this tool when the user wants to change multiple existing reminders in a single operation.",
                "input_schema": ReminderModifyBatchCommand.schema
            ],
            [
                "name": "delete_reminders_batch",
                "description": "Delete multiple existing reminders from the user's reminders at once. Use this tool when the user wants to remove multiple reminders in a single operation.",
                "input_schema": ReminderDeleteBatchCommand.schema
            ],
            
            // Memory Tools - Single item operations
            [
                "name": "add_memory",
                "description": "Add a new memory to the user's memory database. You MUST use this tool to store important information about the user that should persist between conversations.",
                "input_schema": MemoryAddCommand.schema
            ],
            [
                "name": "remove_memory",
                "description": "Remove a memory from the user's memory database. Use this tool when information becomes outdated or is no longer relevant.",
                "input_schema": MemoryRemoveCommand.schema
            ],
            
            // Memory Tools - Batch operations
            [
                "name": "add_memories_batch",
                "description": "Add multiple memories to the user's memory database at once. Use this tool when you need to store multiple pieces of important information in a single operation.",
                "input_schema": MemoryAddBatchCommand.schema
            ],
            [
                "name": "remove_memories_batch",
                "description": "Remove multiple memories from the user's memory database at once. Use this tool when multiple pieces of information become outdated or are no longer relevant.",
                "input_schema": MemoryRemoveBatchCommand.schema
            ]
        ]
    }
    
    /**
     * Processes memory updates from Claude's response.
     *
     * This method supports both legacy bracket-based memory updates and
     * the newer structured memory instructions.
     *
     * @param response The text response from Claude
     * @param memoryManager The memory manager to use for updates
     */
    func processMemoryUpdates(response: String, memoryManager: MemoryManager) async {
        // Support both old and new memory update formats for backward compatibility
        
        // 1. Check for old format memory updates
        let memoryUpdatePattern = "\\[MEMORY_UPDATE\\]([\\s\\S]*?)\\[\\/MEMORY_UPDATE\\]"
        if let regex = try? NSRegularExpression(pattern: memoryUpdatePattern, options: []) {
            let matches = regex.matches(in: response, range: NSRange(response.startIndex..., in: response))
            
            for match in matches {
                if let updateRange = Range(match.range(at: 1), in: response) {
                    let diffContent = String(response[updateRange])
                    print("Found legacy memory update instruction: \(diffContent.count) characters")
                    
                    // Apply the diff to the memory file
                    let success = await memoryManager.applyDiff(diff: diffContent.trimmingCharacters(in: .whitespacesAndNewlines))
                    
                    if success {
                        print("Successfully applied legacy memory update")
                    } else {
                        print("Failed to apply legacy memory update")
                    }
                }
            }
        }
        
        // 2. Check for new structured memory instructions
        // Process the new structured memory format
        // This uses the new method in MemoryManager
        let success = await memoryManager.processMemoryInstructions(instructions: response)
        
        if success {
            print("Successfully processed structured memory instructions")
        }
    }
    
    /**
     * Parses a date string into a Date object.
     *
     * @param dateString The date string in the format "MMM d, yyyy 'at' h:mm a"
     * @return A Date object if parsing was successful, nil otherwise
     */
    func parseDate(_ dateString: String) -> Date? {
        return DateFormatter.claudeDateParser.date(from: dateString)
    }
    
    /**
     * Creates fallback tool input when JSON parsing fails.
     *
     * This provides sensible defaults for different tool types to ensure
     * tool processing can continue even when input parsing fails.
     *
     * @param toolName The name of the tool to create fallback input for
     * @return A dictionary containing fallback input parameters
     */
    func createFallbackToolInput(toolName: String?) -> [String: Any] {
        let now = Date()
        
        switch toolName {
        case "add_calendar_event":
            let oneHourLater = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now
            return [
                "title": "Test Calendar Event",
                "start": DateFormatter.claudeDateParser.string(from: now),
                "end": DateFormatter.claudeDateParser.string(from: oneHourLater),
                "notes": "Created by Claude when JSON parsing failed"
            ]
        case "add_reminder":
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
            return [
                "title": "Test Reminder",
                "due": DateFormatter.claudeDateParser.string(from: tomorrow),
                "notes": "Created by Claude when JSON parsing failed"
            ]
        case "add_memory":
            return [
                "content": "User asked Claude to create a test memory",
                "category": "Miscellaneous Notes",
                "importance": 3
            ]
        default:
            // For other tools, provide a basic fallback
            return ["note": "Fallback tool input for \(toolName ?? "unknown tool")"]
        }
    }
}
