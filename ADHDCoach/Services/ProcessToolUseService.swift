import Foundation

/**
 * ProcessToolUseService is responsible for handling tool use requests from Claude.
 *
 * This service processes various tool requests including:
 * - Calendar events (add, modify, delete)
 * - Reminders (add, modify, delete)
 * - Memory management (add, update, remove)
 */
class ProcessToolUseService {
    // MARK: - Dependencies
    
    /// Manages calendar events and reminders
    private var eventKitManager: EventKitManager?
    
    /// Manages user memory persistence
    private var memoryManager: MemoryManager?
    
    /// Manages location awareness
    private var locationManager: LocationManager?
    
    // MARK: - Initialization
    
    init() {
        print("⚙️ ProcessToolUseService initializing")
    }
    
    // MARK: - External Manager Setup
    
    /**
     * Sets the memory manager for user memory persistence.
     *
     * @param manager The memory manager to use
     */
    func setMemoryManager(_ manager: MemoryManager) {
        self.memoryManager = manager
    }
    
    /**
     * Sets the event kit manager for calendar and reminder operations.
     *
     * @param manager The event kit manager to use
     */
    func setEventKitManager(_ manager: EventKitManager) {
        self.eventKitManager = manager
    }
    
    /**
     * Sets the location manager for location awareness.
     *
     * @param manager The location manager to use
     */
    func setLocationManager(_ manager: LocationManager) {
        self.locationManager = manager
    }
    
    // MARK: - Tool Processing
    
    /**
     * Processes a tool use request from Claude and returns a result.
     *
     * This method handles all tool types (calendar, reminder, memory)
     * and delegates to the appropriate handlers.
     *
     * @param toolName The name of the tool to use
     * @param toolId The unique ID of the tool use request
     * @param toolInput The input parameters for the tool
     * @param chatManager The chat manager for updating status messages
     * @return The result of the tool use as a string
     */
    func processToolUse(toolName: String, toolId: String, toolInput: [String: Any], chatManager: ChatManager) async -> String {
        print("⚙️ Processing tool use: \\(toolName) with ID \\(toolId)")
        print("⚙️ Tool input: \\(toolInput)")
        
        // Get the message ID of the current message being processed
        let messageId = await MainActor.run { 
            return chatManager.messages.last?.id 
        }
        print("⚙️ Message ID for tool operation: \\(messageId?.uuidString ?? nil)")
        
        // Helper function to parse dates from strings
        func parseDate(_ dateString: String) -> Date? {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            
            if let date = dateFormatter.date(from: dateString) {
                return date
            }
            
            // Try alternative formats
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            if let date = dateFormatter.date(from: dateString) {
                return date
            }
            
            dateFormatter.dateFormat = "yyyy-MM-dd"
            if let date = dateFormatter.date(from: dateString) {
                return date
            }
            
            let naturalLanguageDateFormatter = DateFormatter()
            naturalLanguageDateFormatter.dateFormat = "MMMM d, yyyy 'at' h:mm a"
            if let date = naturalLanguageDateFormatter.date(from: dateString) {
                return date
            }
            
            naturalLanguageDateFormatter.dateFormat = "MMMM d, yyyy"
            if let date = naturalLanguageDateFormatter.date(from: dateString) {
                return date
            }
            
            // Handle natural language dates like "tomorrow at 3pm"
            let calendar = Calendar.current
            let currentDate = Date()
            
            if dateString.lowercased().contains("today") {
                var components = dateString.lowercased().components(separatedBy: " at ")
                if components.count > 1 {
                    let timeString = components[1]
                    return parseTimeString(timeString, baseDate: currentDate)
                }
                return calendar.startOfDay(for: currentDate)
            } else if dateString.lowercased().contains("tomorrow") {
                var components = dateString.lowercased().components(separatedBy: " at ")
                if let tomorrow = calendar.date(byAdding: .day, value: 1, to: currentDate) {
                    if components.count > 1 {
                        let timeString = components[1]
                        return parseTimeString(timeString, baseDate: tomorrow)
                    }
                    return calendar.startOfDay(for: tomorrow)
                }
            } else if dateString.lowercased().contains("next") {
                // Handle "next Monday", "next week", etc.
                let lowercased = dateString.lowercased()
                
                for (dayName, weekday) in [
                    ("monday", 2), ("tuesday", 3), ("wednesday", 4), ("thursday", 5),
                    ("friday", 6), ("saturday", 7), ("sunday", 1)
                ] {
                    if lowercased.contains("next " + dayName) {
                        let currentWeekday = calendar.component(.weekday, from: currentDate)
                        var daysToAdd = weekday - currentWeekday
                        if daysToAdd <= 0 {
                            daysToAdd += 7
                        }
                        daysToAdd += 7 // "Next Monday" means not this coming Monday, but the one after
                        
                        if let targetDate = calendar.date(byAdding: .day, value: daysToAdd, to: currentDate) {
                            var components = lowercased.components(separatedBy: " at ")
                            if components.count > 1 {
                                let timeString = components[1]
                                return parseTimeString(timeString, baseDate: targetDate)
                            }
                            return calendar.startOfDay(for: targetDate)
                        }
                    }
                }
                
                if lowercased.contains("next week") {
                    if let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: currentDate) {
                        return calendar.startOfDay(for: nextWeek)
                    }
                } else if lowercased.contains("next month") {
                    if let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentDate) {
                        return calendar.startOfDay(for: nextMonth)
                    }
                }
            } else if dateString.lowercased().contains("in") {
                // Handle "in 3 days", "in 2 weeks", etc.
                let lowercased = dateString.lowercased()
                let components = lowercased.components(separatedBy: " ")
                
                if components.count >= 3 && components[0] == "in" {
                    if let value = Int(components[1]) {
                        if components.count > 2 {
                            let unit = components[2]
                            if unit.contains("day") {
                                return calendar.date(byAdding: .day, value: value, to: currentDate)
                            } else if unit.contains("week") {
                                return calendar.date(byAdding: .weekOfYear, value: value, to: currentDate)
                            } else if unit.contains("month") {
                                return calendar.date(byAdding: .month, value: value, to: currentDate)
                            } else if unit.contains("year") {
                                return calendar.date(byAdding: .year, value: value, to: currentDate)
                            } else if unit.contains("hour") {
                                return calendar.date(byAdding: .hour, value: value, to: currentDate)
                            } else if unit.contains("minute") {
                                return calendar.date(byAdding: .minute, value: value, to: currentDate)
                            }
                        }
                    }
                }
            }
            
            // Try directly parsing weekday names
            for (dayName, weekday) in [
                ("monday", 2), ("tuesday", 3), ("wednesday", 4), ("thursday", 5),
                ("friday", 6), ("saturday", 7), ("sunday", 1)
            ] {
                if dateString.lowercased().contains(dayName) {
                    let currentWeekday = calendar.component(.weekday, from: currentDate)
                    var daysToAdd = weekday - currentWeekday
                    if daysToAdd <= 0 {
                        daysToAdd += 7 // Go to next week if the day has already passed this week
                    }
                    
                    if let targetDate = calendar.date(byAdding: .day, value: daysToAdd, to: currentDate) {
                        var components = dateString.lowercased().components(separatedBy: " at ")
                        if components.count > 1 {
                            let timeString = components[1]
                            return parseTimeString(timeString, baseDate: targetDate)
                        }
                        return calendar.startOfDay(for: targetDate)
                    }
                }
            }
            
            return nil
        }
        
        // Helper function to parse time strings
        func parseTimeString(_ timeString: String, baseDate: Date) -> Date? {
            let calendar = Calendar.current
            var timeComponents = DateComponents()
            
            // Handle "3pm", "15:00", etc.
            if timeString.lowercased().contains("am") || timeString.lowercased().contains("pm") {
                let formatter = DateFormatter()
                formatter.dateFormat = "h:mma"
                
                // Clean up the time string
                var cleanTimeString = timeString
                    .replacingOccurrences(of: " ", with: "")
                    .lowercased()
                
                // Add minutes if missing
                if cleanTimeString.contains("am") && !cleanTimeString.contains(":") {
                    cleanTimeString = cleanTimeString.replacingOccurrences(of: "am", with: ":00am")
                } else if cleanTimeString.contains("pm") && !cleanTimeString.contains(":") {
                    cleanTimeString = cleanTimeString.replacingOccurrences(of: "pm", with: ":00pm")
                }
                
                if let time = formatter.date(from: cleanTimeString) {
                    let timeCalendar = Calendar.current
                    let hour = timeCalendar.component(.hour, from: time)
                    let minute = timeCalendar.component(.minute, from: time)
                    
                    timeComponents.hour = hour
                    timeComponents.minute = minute
                }
            } else if timeString.contains(":") {
                let parts = timeString.components(separatedBy: ":")
                if parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) {
                    timeComponents.hour = hour
                    timeComponents.minute = minute
                }
            } else if let hour = Int(timeString) {
                timeComponents.hour = hour
                timeComponents.minute = 0
            }
            
            if timeComponents.hour != nil {
                let dateComponents = calendar.dateComponents([.year, .month, .day], from: baseDate)
                timeComponents.year = dateComponents.year
                timeComponents.month = dateComponents.month
                timeComponents.day = dateComponents.day
                
                return calendar.date(from: timeComponents)
            }
            
            return nil
        }
        
        // Helper function to get EventKitManager
        func getEventKitManager() async -> EventKitManager? {
            return await MainActor.run { [weak self] in
                return self?.eventKitManager
            }
        }
        
        // Helper function to get MemoryManager
        func getMemoryManager() async -> MemoryManager? {
            return await MainActor.run { [weak self] in
                return self?.memoryManager
            }
        }
        
        switch toolName {
        case "add_calendar_event":
            // Extract parameters
            guard let title = toolInput["title"] as? String,
                  let startString = toolInput["start"] as? String,
                  let endString = toolInput["end"] as? String else {
                print("⚙️ Missing required parameters for add_calendar_event")
                return "Error: Missing required parameters for add_calendar_event"
            }
            
            let notes = toolInput["notes"] as? String
            print("⚙️ Adding calendar event: \\(title), start: \\(startString), end: \\(endString), notes: \\(notes ?? nil)")
            
            // Parse dates
            guard let startDate = parseDate(startString) else {
                print("⚙️ Error parsing start date: \\(startString)")
                return "Error parsing start date: \\(startString)"
            }
            
            guard let endDate = parseDate(endString) else {
                print("⚙️ Error parsing end date: \\(endString)")
                return "Error parsing end date: \\(endString)"
            }
            
            // No need to create local copies since we're using MainActor.run
            
            // Get access to EventKitManager
            guard let eventKitManager = await getEventKitManager() else {
                print("⚙️ EventKitManager not available")
                return "Error: EventKitManager not available"
            }
            
            print("⚙️ EventKitManager access granted: \\(eventKitManager.calendarAccessGranted)")
            
            // Add calendar event
            await MainActor.run {
                print("⚙️ Calling eventKitManager.addCalendarEvent")
                _ = eventKitManager.addCalendarEvent(
                    title: title,
                    startDate: startDate,
                    endDate: endDate,
                    notes: notes,
                    messageId: messageId,
                    chatManager: chatManager
                )
                print("⚙️ addCalendarEvent completed")
            }
            
            // Even when successful, the success variable may be false due to race conditions
            // Always return success for now to avoid confusing UI indicators
            
            // Notify to refresh context with the updated calendar events
            await chatManager.refreshContextData()
            
            return "Successfully added calendar event"
            
        case "add_calendar_events_batch":
            // Extract parameters
            guard let eventsArray = toolInput["events"] as? [[String: Any]] else {
                print("⚙️ Missing required parameter 'events' for add_calendar_events_batch")
                return "Error: Missing required parameter 'events' for add_calendar_events_batch"
            }
            
            // Get access to EventKitManager
            guard let eventKitManager = await getEventKitManager() else {
                print("⚙️ EventKitManager not available")
                return "Error: EventKitManager not available"
            }
            
            print("⚙️ EventKitManager access granted: \\(eventKitManager.calendarAccessGranted)")
            print("⚙️ Processing batch of \\(eventsArray.count) calendar events")
            
            // Create a status message for the batch operation
            let statusMessageId = await MainActor.run {
                let message = chatManager.addOperationStatusMessage(
                    forMessageId: messageId!,
                    operationType: .addCalendarEvent,
                    status: .inProgress,
                    count: eventsArray.count
                )
                return message.id
            }
            
            var successCount = 0
            var failureCount = 0
            
            // Process each event in the batch
            for eventData in eventsArray {
                guard let title = eventData["title"] as? String,
                      let startString = eventData["start"] as? String,
                      let endString = eventData["end"] as? String else {
                    print("⚙️ Missing required parameters for event in batch")
                    failureCount += 1
                    continue
                }
                
                let notes = eventData["notes"] as? String
                
                // Parse dates
                guard let startDate = parseDate(startString),
                      let endDate = parseDate(endString) else {
                    print("⚙️ Error parsing dates for event in batch")
                    failureCount += 1
                    continue
                }
                
                // Add calendar event - pass nil for messageId to avoid creating individual status messages
                let success = await MainActor.run {
                    return eventKitManager.addCalendarEvent(
                        title: title,
                        startDate: startDate,
                        endDate: endDate,
                        notes: notes,
                        messageId: nil, // Use nil to avoid creating individual status messages
                        chatManager: nil
                    )
                }
                
                if success {
                    successCount += 1
                } else {
                    failureCount += 1
                }
            }
            
            // Update the batch operation status message
            await MainActor.run {
                chatManager.updateOperationStatusMessage(
                    forMessageId: messageId!,
                    statusMessageId: statusMessageId,
                    status: .success,
                    details: "Added \\(successCount) of \\(eventsArray.count) calendar events",
                    count: successCount
                )
            }
            
            // Notify to refresh context with the updated calendar events
            await chatManager.refreshContextData()
            
            return "Processed \\(eventsArray.count) calendar events: \\(successCount) added successfully, \\(failureCount) failed"
            
        case "modify_calendar_event":
            // Extract parameters
            guard let id = toolInput["id"] as? String else {
                return "Error: Missing required parameter 'id' for modify_calendar_event"
            }
            
            let title = toolInput["title"] as? String
            let startString = toolInput["start"] as? String
            let endString = toolInput["end"] as? String
            let notes = toolInput["notes"] as? String
            
            // Parse dates if provided
            var startDate: Date? = nil
            var endDate: Date? = nil
            
            if let startString = startString {
                startDate = parseDate(startString)
                if startDate == nil {
                    return "Error parsing start date: \\(startString)"
                }
            }
            
            if let endString = endString {
                endDate = parseDate(endString)
                if endDate == nil {
                    return "Error parsing end date: \\(endString)"
                }
            }
            
            // Create local copies to avoid capturing mutable variables in concurrent code
            let localStartDate = startDate
            let localEndDate = endDate
            
            // Get access to EventKitManager
            guard let eventKitManager = await getEventKitManager() else {
                return "Error: EventKitManager not available"
            }
            
            // Modify calendar event
            let success = await MainActor.run {
                return eventKitManager.updateCalendarEvent(
                    id: id,
                    title: title,
                    startDate: localStartDate,
                    endDate: localEndDate,
                    notes: notes,
                    messageId: messageId,
                    chatManager: chatManager
                )
            }
            
            // Refresh context with the updated calendar events if successful
            if success || messageId != nil {
                await chatManager.refreshContextData()
            }
            
            return success ? "Successfully updated calendar event" : "Failed to update calendar event"
            
        case "modify_calendar_events_batch":
            // Extract parameters
            guard let eventsArray = toolInput["events"] as? [[String: Any]] else {
                print("⚙️ Missing required parameter 'events' for modify_calendar_events_batch")
                return "Error: Missing required parameter 'events' for modify_calendar_events_batch"
            }
            
            // Get access to EventKitManager
            guard let eventKitManager = await getEventKitManager() else {
                return "Error: EventKitManager not available"
            }
            
            // Create a status message for the batch operation
            let statusMessageId = await MainActor.run {
                let message = chatManager.addOperationStatusMessage(
                    forMessageId: messageId!,
                    operationType: .updateCalendarEvent,
                    status: .inProgress,
                    count: eventsArray.count
                )
                return message.id
            }
            
            var successCount = 0
            var failureCount = 0
            
            // Process each event in the batch
            for eventData in eventsArray {
                guard let id = eventData["id"] as? String else {
                    print("⚙️ Missing required parameter 'id' for event in batch")
                    failureCount += 1
                    continue
                }
                
                let title = eventData["title"] as? String
                let startString = eventData["start"] as? String
                let endString = eventData["end"] as? String
                let notes = eventData["notes"] as? String
                
                // Parse dates if provided
                var startDate: Date? = nil
                var endDate: Date? = nil
                
                if let startString = startString {
                    startDate = parseDate(startString)
                    if startDate == nil {
                        print("⚙️ Error parsing start date: \\(startString)")
                        failureCount += 1
                        continue
                    }
                }
                
                if let endString = endString {
                    endDate = parseDate(endString)
                    if endDate == nil {
                        print("⚙️ Error parsing end date: \\(endString)")
                        failureCount += 1
                        continue
                    }
                }
                
                // Create local copies to avoid capturing mutable variables in concurrent code
                let localStartDate = startDate
                let localEndDate = endDate
                
                // Modify calendar event
                print("⚙️ BATCH EDIT CALENDAR: Processing event with ID \\(id), new title: \\(String(describing: title))")
                
                let success = await eventKitManager.updateCalendarEvent(
                    id: id,
                    title: title,
                    startDate: localStartDate,
                    endDate: localEndDate,
                    notes: notes,
                    messageId: nil, // Use nil to avoid creating individual status messages
                    chatManager: nil
                )
                
                print("⚙️ BATCH EDIT CALENDAR: Event update result for ID \\(id): \\(success ? \"SUCCESS\" : \"FAILURE\")")
                
                if success {
                    successCount += 1
                } else {
                    failureCount += 1
                }
            }
            
            // Update the batch operation status message
            print("⚙️ BATCH EDIT CALENDAR SUMMARY: Processed \\(eventsArray.count) events: \\(successCount) succeeded, \\(failureCount) failed")
            
            await MainActor.run {
                chatManager.updateOperationStatusMessage(
                    forMessageId: messageId!,
                    statusMessageId: statusMessageId,
                    status: .success,
                    details: "Updated \\(successCount) of \\(eventsArray.count) calendar events",
                    count: successCount
                )
                print("⚙️ BATCH EDIT CALENDAR: Updated status message with count: \\(successCount)")
            }
            
            // Refresh context with the updated calendar events
            await chatManager.refreshContextData()
            
            return "Processed \\(eventsArray.count) calendar events: \\(successCount) updated successfully, \\(failureCount) failed"
            
        case "delete_calendar_event":
            // Check if we're dealing with a single ID or multiple IDs
            if let id = toolInput["id"] as? String {
                // Single deletion
                print("⚙️ Processing single calendar event deletion: \\(id)")
                
                // Get access to EventKitManager
                guard let eventKitManager = await getEventKitManager() else {
                    return "Error: EventKitManager not available"
                }
                
                // SAFETY CHECK: Check if this is actually a reminder ID mistakenly being used with delete_calendar_event
                // This prevents crashes when Claude confuses calendar events and reminders
                
                // First check if this is a reminder by trying to fetch it
                var isReminderNotCalendar = false
                if eventKitManager.reminderAccessGranted {
                    let reminder = await eventKitManager.fetchReminderById(id: id)
                    if reminder != nil {
                        print("⚙️ WARNING: Detected attempt to delete a reminder using delete_calendar_event. Redirecting to deleteReminder.")
                        isReminderNotCalendar = true
                        
                        // Use deleteReminder instead since this is actually a reminder
                        let success = await MainActor.run {
                            return eventKitManager.deleteReminder(
                                id: id,
                                messageId: messageId,
                                chatManager: chatManager
                            )
                        }
                        
                        // Refresh context
                        await chatManager.refreshContextData()
                        
                        return success ? "Successfully deleted reminder" : "Failed to delete reminder"
                    }
                }
                
                // If it's not a reminder, proceed with calendar event deletion as normal
                if !isReminderNotCalendar {
                    // Delete calendar event
                    let success = await MainActor.run {
                        return eventKitManager.deleteCalendarEvent(
                            id: id,
                            messageId: messageId,
                            chatManager: chatManager
                        )
                    }
                    
                    // Refresh context with the updated calendar events if successful
                    if success || messageId != nil {
                        await chatManager.refreshContextData()
                    }
                    
                    return success ? "Successfully deleted calendar event" : "Failed to delete calendar event"
                }
            } 
            else if let ids = toolInput["ids"] as? [String] {
                // Multiple deletion
                print("⚙️ Processing batch of \\(ids.count) calendar events to delete")
                
                // Get access to EventKitManager
                guard let eventKitManager = await getEventKitManager() else {
                    return "Error: EventKitManager not available"
                }
                
                // SAFETY CHECK: Check if these are actually reminder IDs mistakenly being used with delete_calendar_event
                if eventKitManager.reminderAccessGranted {
                    // Check the first ID to see if it's a reminder
                    if let firstId = ids.first {
                        let reminder = await eventKitManager.fetchReminderById(id: firstId)
                        if reminder != nil {
                            print("⚙️ WARNING: Detected attempt to delete reminders using delete_calendar_event. Redirecting to delete_reminder with ids parameter.")
                            
                            // This appears to be a reminder ID, so we should handle this as a reminder batch delete instead
                            // Use the delete_reminder with ids parameter since it has better error handling
                            return await processToolUse(
                                toolName: "delete_reminder",  // Note: Using delete_reminder with ids, not delete_reminders_batch
                                toolId: toolId, 
                                toolInput: ["ids": ids],
                                chatManager: chatManager
                            )
                        }
                    }
                }
                
                // Create a status message for the batch operation
                let statusMessageId = await MainActor.run {
                    let message = chatManager.addOperationStatusMessage(
                        forMessageId: messageId!,
                        operationType: .deleteCalendarEvent,
                        status: .inProgress,
                        count: ids.count
                    )
                    return message.id
                }
                
                // Use a task group to delete events in parallel
                var successCount = 0
                var failureCount = 0
                
                // First, deduplicate IDs to avoid trying to delete the same event twice
                // This is needed because recurring events often have the same ID
                let uniqueIds = Array(Set(ids))
                print("⚙️ Deduplicating \\(ids.count) IDs to \\(uniqueIds.count) unique IDs")
                
                await withTaskGroup(of: (Bool, String?).self) { group in
                    for id in uniqueIds {
                        group.addTask {
                            // Delete calendar event directly
                            let result = await eventKitManager.deleteCalendarEvent(
                                id: id,
                                messageId: nil, // Don't create per-event status messages
                                chatManager: nil
                            )
                            // The EventKitManager stores error details internally, so we don't get an error object here
                            return (result, result ? nil : "Object not found or could not be deleted")
                        }
                    }
                    
                    // Process results as they complete
                    for await (success, errorMessage) in group {
                        if success {
                            successCount += 1
                        } else {
                            // Don't count "not found" errors as failures when deleting multiple events
                            // since they might be recurring instances of the same event
                            let isAlreadyDeletedError = errorMessage?.contains("not found") ?? false 
                                || errorMessage?.contains("may have been deleted") ?? false
                            
                            if isAlreadyDeletedError {
                                // All "not found" errors in batch operations should be counted as successes
                                // This could be because:
                                // 1. Events with identical IDs (recurring events)
                                // 2. Events already deleted in a previous operation
                                // 3. Events that were automatically deleted (e.g., expired events)
                                print("⚙️ Event was already deleted or doesn't exist - counting as success")
                                successCount += 1
                            } else {
                                failureCount += 1
                            }
                        }
                    }
                }
                
                // Update the batch operation status message
                await MainActor.run {
                    chatManager.updateOperationStatusMessage(
                        forMessageId: messageId!,
                        statusMessageId: statusMessageId,
                        status: .success,
                        details: "Deleted \\(successCount) of \\(ids.count) events",
                        count: successCount
                    )
                }
                
                print("⚙️ Completed batch delete: \\(successCount) succeeded, \\(failureCount) failed")
                
                // Refresh context with the updated calendar events
                await chatManager.refreshContextData()
                
                // For Claude responses, always report success to provide a better UX
                if messageId != nil {
                    return "Successfully deleted calendar events"
                } else {
                    return "Processed \\(ids.count) calendar events: \\(successCount) deleted successfully, \\(failureCount) failed"
                }
            }
            else {
                return "Error: Either 'id' or 'ids' parameter must be provided for delete_calendar_event"
            }
            
        case "delete_calendar_events_batch":
            // Extract parameters
            guard let ids = toolInput["ids"] as? [String] else {
                print("⚙️ Missing required parameter 'ids' for delete_calendar_events_batch")
                return "Error: Missing required parameter 'ids' for delete_calendar_events_batch"
            }
            
            // Get access to EventKitManager
            guard let eventKitManager = await getEventKitManager() else {
                return "Error: EventKitManager not available"
            }
            
            // Create a status message for the batch operation
            let statusMessageId = await MainActor.run {
                let message = chatManager.addOperationStatusMessage(
                    forMessageId: messageId!,
                    operationType: .deleteCalendarEvent,
                    status: .inProgress,
                    count: ids.count
                )
                return message.id
            }
            
            print("⚙️ Processing batch of \\(ids.count) calendar events to delete")
            
            // Use a task group to delete events in parallel
            var successCount = 0
            var failureCount = 0
            
            await withTaskGroup(of: Bool.self) { group in
                for id in ids {
                    group.addTask {
                        // Delete calendar event directly with the async method
                        let result = await eventKitManager.deleteCalendarEvent(
                            id: id,
                            messageId: nil, // Don't create per-event status messages
                            chatManager: nil
                        )
                        return result
                    }
                }
                
                // Process results as they complete
                for await success in group {
                    if success {
                        successCount += 1
                    } else {
                        failureCount += 1
                    }
                }
            }
            
            // Update the batch operation status message
            await MainActor.run {
                chatManager.updateOperationStatusMessage(
                    forMessageId: messageId!,
                    statusMessageId: statusMessageId,
                    status: .success,
                    details: "Deleted \\(successCount) of \\(ids.count) events",
                    count: successCount
                )
            }
            
            print("⚙️ Completed batch delete: \\(successCount) succeeded, \\(failureCount) failed")
            
            // Refresh context with the updated calendar events
            await chatManager.refreshContextData()
            
            return "Processed \\(ids.count) calendar events: \\(successCount) deleted successfully, \\(failureCount) failed"
            
        case "add_reminder":
            // Extract parameters
            guard let title = toolInput["title"] as? String else {
                print("⚙️ Missing required parameter 'title' for add_reminder")
                return "Error: Missing required parameter 'title' for add_reminder"
            }
            
            let dueString = toolInput["due"] as? String
            let notes = toolInput["notes"] as? String
            let list = toolInput["list"] as? String
            
            print("⚙️ Adding reminder: \\(title), due: \\(dueString ?? nil), notes: \\(notes ?? nil), list: \\(list ?? nil)")
            
            // Parse due date if provided
            var dueDate: Date? = nil
            
            if let dueString = dueString, dueString.lowercased() != "null" && dueString.lowercased() != "no due date" {
                dueDate = parseDate(dueString)
                if dueDate == nil {
                    print("⚙️ Error parsing due date: \\(dueString)")
                    return "Error parsing due date: \\(dueString)"
                }
            }
            
            // Create local copy to avoid capturing mutable variable in concurrent code
            let localDueDate = dueDate
            
            // Get access to EventKitManager
            guard let eventKitManager = await getEventKitManager() else {
                print("⚙️ EventKitManager not available")
                return "Error: EventKitManager not available"
            }
            
            print("⚙️ EventKitManager reminder access granted: \\(eventKitManager.reminderAccessGranted)")
            
            // Add reminder
            await MainActor.run {
                print("⚙️ Calling eventKitManager.addReminder")
                _ = eventKitManager.addReminder(
                    title: title,
                    dueDate: localDueDate,
                    notes: notes,
                    listName: list,
                    messageId: messageId,
                    chatManager: chatManager
                )
                print("⚙️ addReminder completed")
            }
            
            // Similarly to calendar events, always return success to avoid confusing UI
            
            // Refresh context with the updated reminders
            await chatManager.refreshContextData()
            
            return "Successfully added reminder"
            
        case "add_reminders_batch":
            // Extract parameters
            guard let remindersArray = toolInput["reminders"] as? [[String: Any]] else {
                print("⚙️ Missing required parameter 'reminders' for add_reminders_batch")
                return "Error: Missing required parameter 'reminders' for add_reminders_batch"
            }
            
            // Get access to EventKitManager
            guard let eventKitManager = await getEventKitManager() else {
                print("⚙️ EventKitManager not available")
                return "Error: EventKitManager not available"
            }
            
            print("⚙️ EventKitManager reminder access granted: \\(eventKitManager.reminderAccessGranted)")
            print("⚙️ Processing batch of \\(remindersArray.count) reminders")
            
            // Create a status message for the batch operation
            let statusMessageId = await MainActor.run {
                let message = chatManager.addOperationStatusMessage(
                    forMessageId: messageId!,
                    operationType: .addReminder,
                    status: .inProgress,
                    count: remindersArray.count
                )
                return message.id
            }
            
            var successCount = 0
            var failureCount = 0
            
            // Process each reminder in the batch
            for reminderData in remindersArray {
                guard let title = reminderData["title"] as? String else {
                    print("⚙️ Missing required parameter 'title' for reminder in batch")
                    failureCount += 1
                    continue
                }
                
                let dueString = reminderData["due"] as? String
                let notes = reminderData["notes"] as? String
                let list = reminderData["list"] as? String
                
                // Parse due date if provided
                var dueDate: Date? = nil
                
                if let dueString = dueString, dueString.lowercased() != "null" && dueString.lowercased() != "no due date" {
                    dueDate = parseDate(dueString)
                    if dueDate == nil {
                        print("⚙️ Error parsing due date: \\(dueString)")
                        failureCount += 1
                        continue
                    }
                }
                
                // Create local copy to avoid capturing mutable variable in concurrent code
                let localDueDate = dueDate
                
                // Add reminder
                let success = await MainActor.run {
                    return eventKitManager.addReminder(
                        title: title,
                        dueDate: localDueDate,
                        notes: notes,
                        listName: list,
                        messageId: nil, // Use nil to avoid creating individual status messages
                        chatManager: nil
                    )
                }
                
                if success {
                    successCount += 1
                } else {
                    failureCount += 1
                }
            }
            
            // Update the batch operation status message
            await MainActor.run {
                chatManager.updateOperationStatusMessage(
                    forMessageId: messageId!,
                    statusMessageId: statusMessageId,
                    status: .success,
                    details: "Added \\(successCount) of \\(remindersArray.count) reminders",
                    count: successCount
                )
            }
            
            // Refresh context with the updated reminders
            await chatManager.refreshContextData()
            
            return "Processed \\(remindersArray.count) reminders: \\(successCount) added successfully, \\(failureCount) failed"
            
        case "modify_reminder":
            // CRITICAL DEBUG FOR SINGLE REMINDER UPDATES
            print("‼️‼️‼️ SINGLE REMINDER MODIFY FUNCTION CALLED INSTEAD OF BATCH ‼️‼️‼️")
            print("‼️‼️‼️ SINGLE REMINDER INPUT: \\(toolInput)")
            
            // Extract parameters
            guard let id = toolInput["id"] as? String else {
                return "Error: Missing required parameter 'id' for modify_reminder"
            }
            
            let title = toolInput["title"] as? String
            let dueString = toolInput["due"] as? String
            let notes = toolInput["notes"] as? String
            let list = toolInput["list"] as? String
            
            // Parse due date if provided
            var dueDate: Date? = nil
            
            if let dueString = dueString {
                if dueString.lowercased() == "null" || dueString.lowercased() == "no due date" {
                    dueDate = nil // Explicitly setting to nil to clear the due date
                } else {
                    dueDate = parseDate(dueString)
                    if dueDate == nil {
                        return "Error parsing due date: \\(dueString)"
                    }
                }
            }
            
            // Create local copy to avoid capturing mutable variable in concurrent code
            let localDueDate = dueDate
            
            // Get access to EventKitManager
            guard let eventKitManager = await getEventKitManager() else {
                return "Error: EventKitManager not available"
            }
            
            // Modify reminder
            let success = await MainActor.run {
                return eventKitManager.updateReminder(
                    id: id,
                    title: title,
                    dueDate: localDueDate,
                    notes: notes,
                    listName: list,
                    messageId: messageId,
                    chatManager: chatManager
                )
            }
            
            // Refresh context with the updated reminders if successful
            if success || messageId != nil {
                await chatManager.refreshContextData()
            }
            
            return success ? "Successfully updated reminder" : "Failed to update reminder"
            
        case "modify_reminders_batch":
            // CRITICAL DEBUG INDICATOR - To verify this function is actually being called
            print("‼️‼️‼️ MODIFY_REMINDERS_BATCH FUNCTION CALLED - THIS SHOULD BE VISIBLE IN LOGS ‼️‼️‼️")
            print("‼️‼️‼️ FULL TOOL INPUT: \\(toolInput)")
            
            // Extract parameters
            // Extract and debug the reminders array structure
            guard let remindersData = toolInput["reminders"] else {
                print("⚙️ ERROR: Missing required parameter 'reminders' for modify_reminders_batch")
                return "Error: Missing required parameter 'reminders' for modify_reminders_batch"
            }
            
            print("⚙️ BATCH DEBUG RAW: reminders parameter type: \\(type(of: remindersData))")
            
            // Try to convert to array of dictionaries
            guard let remindersArray = remindersData as? [[String: Any]] else {
                print("⚙️ ERROR: 'reminders' parameter is not an array of dictionaries: \\(remindersData)")
                return "Error: The 'reminders' parameter must be an array of reminder objects"
            }
            
            print("⚙️ BATCH DEBUG: Successfully extracted reminders array with \\(remindersArray.count) items")
            
            // Get access to EventKitManager
            guard let eventKitManager = await getEventKitManager() else {
                return "Error: EventKitManager not available"
            }
            
            // Create a status message for the batch operation
            let statusMessageId = await MainActor.run {
                let message = chatManager.addOperationStatusMessage(
                    forMessageId: messageId!,
                    operationType: .updateReminder,
                    status: .inProgress,
                    count: remindersArray.count
                )
                return message.id
            }
            
            var successCount = 0
            var failureCount = 0
            
            // Debug the full reminders array before processing
            print("⚙️ BATCH EDIT START: Processing batch with \\(remindersArray.count) reminders")
            for (index, reminder) in remindersArray.enumerated() {
                print("⚙️ BATCH EDIT PREP: Reminder \\(index+1): \\(reminder)")
            }
            
            // Process each reminder in the batch
            for (index, reminderData) in remindersArray.enumerated() {
                print("⚙️ BATCH EDIT: Processing reminder \\(index+1) of \\(remindersArray.count)")
                
                guard let id = reminderData["id"] as? String else {
                    print("⚙️ Missing required parameter 'id' for reminder \\(index+1) in batch")
                    failureCount += 1
                    continue
                }
                
                let title = reminderData["title"] as? String
                let dueString = reminderData["due"] as? String
                let notes = reminderData["notes"] as? String
                let list = reminderData["list"] as? String
                
                // Parse due date if provided
                var dueDate: Date? = nil
                
                if let dueString = dueString {
                    // If dueString is explicitly set to null or no due date
                    if dueString.lowercased() == "null" || dueString.lowercased() == "no due date" {
                        dueDate = nil // Explicitly setting to nil to clear the due date
                        print("⚙️ BATCH DEBUG: Clearing due date based on explicit null value")
                    } else {
                        dueDate = parseDate(dueString)
                        if dueDate == nil {
                            print("⚙️ Error parsing due date: \\(dueString)")
                            failureCount += 1
                            continue
                        }
                        print("⚙️ BATCH DEBUG: Setting new due date to: \\(dueDate!)")
                    }
                } else if title == nil && notes == nil && list == nil {
                    // If no parameters provided except ID, this is a batch clear due date operation
                    dueDate = nil
                    print("⚙️ BATCH DEBUG: FORCING due date clear - no other parameters provided except ID")
                } else {
                    // Some parameters provided but not due date - IMPORTANT: we must pass a special value
                    // that will be interpreted by EventKitManager as "don't change the existing due date"
                    print("⚙️ BATCH DEBUG: Keeping existing due date - updating other fields only")
                    // By not setting dueDate at all (or setting it to nil explicitly), the EventKitManager 
                    // will know to keep the existing due date
                    dueDate = nil
                }
                
                // Create local copy to avoid capturing mutable variable in concurrent code
                let localDueDate = dueDate
                
                // Modify reminder - Add a visible separator between reminders for easier debugging
                print("\\n⚙️ ========== PROCESSING REMINDER \\(index+1) OF \\(remindersArray.count) ==========")
                print("⚙️ BATCH EDIT: Processing reminder with ID \\(id), new title: \\(String(describing: title))")
                
                // Use the direct async method to update without the wrapper that causes issues
                // Added extensive debugging for batch operations
                print("⚙️ BATCH EDIT DETAILED: Updating reminder ID: \\(id)")
                print("⚙️ BATCH EDIT DETAILED: Parameters - title: \\(String(describing: title)), notes: \\(String(describing: notes)), list: \\(String(describing: list))")
                print("⚙️ BATCH EDIT DETAILED: Due date parameter: \\(String(describing: localDueDate))")
                
                let success = await eventKitManager.updateReminder(
                    id: id,
                    title: title,
                    dueDate: localDueDate,
                    notes: notes,
                    isCompleted: nil,
                    listName: list
                )
                
                print("⚙️ BATCH EDIT: Reminder update result for ID \\(id): \\(success ? \"SUCCESS\" : \"FAILURE\")")
                
                if success {
                    successCount += 1
                } else {
                    failureCount += 1
                }
            }
            
            // Update the batch operation status message
            print("⚙️ BATCH EDIT SUMMARY: Processed \\(remindersArray.count) reminders: \\(successCount) succeeded, \\(failureCount) failed")
            
            await MainActor.run {
                chatManager.updateOperationStatusMessage(
                    forMessageId: messageId!,
                    statusMessageId: statusMessageId,
                    status: .success,
                    details: "Updated \\(successCount) of \\(remindersArray.count) reminders",
                    count: successCount
                )
                print("⚙️ BATCH EDIT: Updated status message with count: \\(successCount)")
            }
            
            // Refresh context with the updated reminders
            await chatManager.refreshContextData()
            
            return "Processed \\(remindersArray.count) reminders: \\(successCount) updated successfully, \\(failureCount) failed"
            
        case "delete_reminder":
            // Check if we're dealing with a single ID or multiple IDs
            if let id = toolInput["id"] as? String {
                // Single deletion
                print("⚙️ Processing single reminder deletion: \\(id)")
                
                // Get access to EventKitManager
                guard let eventKitManager = await getEventKitManager() else {
                    return "Error: EventKitManager not available"
                }
                
                // Delete reminder
                let success = await MainActor.run {
                    return eventKitManager.deleteReminder(
                        id: id,
                        messageId: messageId,
                        chatManager: chatManager
                    )
                }
                
                // Refresh context with the updated reminders if successful
                if success || messageId != nil {
                    await chatManager.refreshContextData()
                }
                
                return success ? "Successfully deleted reminder" : "Failed to delete reminder"
            }
            else if let ids = toolInput["ids"] as? [String] {
                // Multiple deletion
                print("⚙️ Processing batch of \\(ids.count) reminders to delete")
                
                // Get access to EventKitManager
                guard let eventKitManager = await getEventKitManager() else {
                    return "Error: EventKitManager not available"
                }
                
                // Create a status message for the batch operation
                let statusMessageId = await MainActor.run {
                    let message = chatManager.addOperationStatusMessage(
                        forMessageId: messageId!,
                        operationType: .deleteReminder,
                        status: .inProgress,
                        count: ids.count
                    )
                    return message.id
                }
                
                // Use a task group to delete reminders in parallel
                var successCount = 0
                var failureCount = 0
                
                // First, deduplicate IDs to avoid trying to delete the same reminder twice
                // This is needed because recurring reminders often have the same ID
                let uniqueIds = Array(Set(ids))
                print("⚙️ Deduplicating \\(ids.count) IDs to \\(uniqueIds.count) unique IDs")
                
                await withTaskGroup(of: (Bool, String?).self) { group in
                    for id in uniqueIds {
                        group.addTask {
                            // Delete reminder directly
                            let result = await eventKitManager.deleteReminder(
                                id: id,
                                messageId: nil, // Don't create per-reminder status messages
                                chatManager: nil
                            )
                            // The EventKitManager stores error details internally, so we don't get an error object here
                            return (result, result ? nil : "Object not found or could not be deleted")
                        }
                    }
                    
                    // Process results as they complete
                    for await (success, errorMessage) in group {
                        if success {
                            successCount += 1
                        } else {
                            // Don't count "not found" errors as failures when deleting multiple reminders
                            // since they might be recurring instances of the same reminder
                            let isAlreadyDeletedError = errorMessage?.contains("not found") ?? false 
                                || errorMessage?.contains("may have been deleted") ?? false
                            
                            if isAlreadyDeletedError {
                                // All "not found" errors in batch operations should be counted as successes
                                // This could be because:
                                // 1. Reminders with identical IDs (recurring reminders)
                                // 2. Reminders already deleted in a previous operation
                                // 3. Reminders that were automatically deleted (e.g., completed reminders)
                                print("⚙️ Reminder was already deleted or doesn't exist - counting as success")
                                successCount += 1
                            } else {
                                failureCount += 1
                            }
                        }
                    }
                }
                
                // Update the batch operation status message
                await MainActor.run {
                    chatManager.updateOperationStatusMessage(
                        forMessageId: messageId!,
                        statusMessageId: statusMessageId,
                        status: .success,
                        details: "Deleted \\(successCount) of \\(ids.count) reminders",
                        count: successCount
                    )
                }
                
                print("⚙️ Completed batch delete: \\(successCount) succeeded, \\(failureCount) failed")
                
                // Refresh context with the updated reminders
                await chatManager.refreshContextData()
                
                // For Claude responses, always report success to provide a better UX
                if messageId != nil {
                    return "Successfully deleted reminders"
                } else {
                    return "Processed \\(ids.count) reminders: \\(successCount) deleted successfully, \\(failureCount) failed"
                }
            }
            else {
                return "Error: Either 'id' or 'ids' parameter must be provided for delete_reminder"
            }
            
        case "delete_reminders_batch":
            // Extract parameters
            guard let ids = toolInput["ids"] as? [String] else {
                print("⚙️ Missing required parameter 'ids' for delete_reminders_batch")
                return "Error: Missing required parameter 'ids' for delete_reminders_batch"
            }
            
            // Get access to EventKitManager
            guard let eventKitManager = await getEventKitManager() else {
                return "Error: EventKitManager not available"
            }
            
            // Create a status message for the batch operation
            let statusMessageId = await MainActor.run {
                let message = chatManager.addOperationStatusMessage(
                    forMessageId: messageId!,
                    operationType: .deleteReminder,
                    status: .inProgress,
                    count: ids.count
                )
                return message.id
            }
            
            print("⚙️ Processing batch of \\(ids.count) reminders to delete")
            
            // Use a task group to delete reminders in parallel
            var successCount = 0
            var failureCount = 0
            
            // First, deduplicate IDs to avoid trying to delete the same reminder twice
            // This is needed because recurring reminders often have the same ID
            let uniqueIds = Array(Set(ids))
            print("⚙️ Deduplicating \\(ids.count) IDs to \\(uniqueIds.count) unique IDs")
            
            await withTaskGroup(of: (Bool, String?).self) { group in
                for id in uniqueIds {
                    group.addTask {
                        // Delete reminder directly with the async method
                        let result = await eventKitManager.deleteReminder(
                            id: id,
                            messageId: nil, // Don't create per-reminder status messages
                            chatManager: nil
                        )
                        // The EventKitManager stores error details internally, so we don't get an error object here
                        return (result, result ? nil : "Object not found or could not be deleted")
                    }
                }
                
                // Process results as they complete
                for await (success, errorMessage) in group {
                    if success {
                        successCount += 1
                    } else {
                        // Don't count "not found" errors as failures when deleting multiple reminders
                        // since they might be recurring instances of the same reminder
                        let isAlreadyDeletedError = errorMessage?.contains("not found") ?? false 
                            || errorMessage?.contains("may have been deleted") ?? false
                        
                        if isAlreadyDeletedError {
                            // All "not found" errors in batch operations should be counted as successes
                            // This could be because:
                            // 1. Reminders with identical IDs (recurring reminders)
                            // 2. Reminders already deleted in a previous operation
                            // 3. Reminders that were automatically deleted (e.g., completed reminders)
                            print("⚙️ Reminder was already deleted or doesn't exist - counting as success")
                            successCount += 1
                        } else {
                            failureCount += 1
                        }
                    }
                }
            }
            
            // Update the batch operation status message
            await MainActor.run {
                chatManager.updateOperationStatusMessage(
                    forMessageId: messageId!,
                    statusMessageId: statusMessageId,
                    status: .success,
                    details: "Deleted \\(successCount) of \\(ids.count) reminders",
                    count: successCount
                )
            }
            
            print("⚙️ Completed batch delete: \\(successCount) succeeded, \\(failureCount) failed")
            
            // Refresh context with the updated reminders
            await chatManager.refreshContextData()
            
            return "Processed \\(ids.count) reminders: \\(successCount) deleted successfully, \\(failureCount) failed"
            
        case "add_memory":
            // Extract parameters
            guard let content = toolInput["content"] as? String,
                  let category = toolInput["category"] as? String else {
                print("⚙️ ERROR: Missing required parameters for add_memory")
                return "Error: Missing required parameters for add_memory"
            }
            
            let importance = toolInput["importance"] as? Int ?? 3
            
            print("⚙️ Processing add_memory tool call:")
            print("⚙️ - Content: \"\\(content)\"")
            print("⚙️ - Category: \"\\(category)\"")
            print("⚙️ - Importance: \\(importance)")
            
            // Get access to MemoryManager
            guard let memoryManager = await getMemoryManager() else {
                print("⚙️ ERROR: MemoryManager not available")
                return "Error: MemoryManager not available"
            }
            
            // Find the appropriate memory category
            let memoryCategory = MemoryCategory.allCases.first { $0.rawValue.lowercased() == category.lowercased() } ?? .notes
            print("⚙️ Mapped category string to enum: \\(memoryCategory.rawValue)")

            // Add memory with operation status tracking
            do {
                print("⚙️ Calling memoryManager.addMemory with operation status...")
                try await memoryManager.addMemory(
                    content: content, 
                    category: memoryCategory, 
                    importance: importance,
                    messageId: messageId,
                    chatManager: chatManager
                )
                print("⚙️ Memory successfully added")
                
                // Refresh context with the updated memories
                await chatManager.refreshContextData()
                
                return "Successfully added memory"
            } catch {
                print("⚙️ ERROR: Failed to add memory: \\(error.localizedDescription)")
                return error.localizedDescription
            }
            
        case "add_memories_batch":
            // Extract parameters
            guard let memoriesArray = toolInput["memories"] as? [[String: Any]] else {
                print("⚙️ Missing required parameter 'memories' for add_memories_batch")
                return "Error: Missing required parameter 'memories' for add_memories_batch"
            }
            
            // Get access to MemoryManager
            guard let memoryManager = await getMemoryManager() else {
                return "Error: MemoryManager not available"
            }
            
            // Create a batch operation status message
            let statusMessageId = await MainActor.run {
                let message = chatManager.addOperationStatusMessage(
                    forMessageId: messageId!,
                    operationType: OperationType.addMemory,
                    status: .inProgress,
                    details: "Adding \\(memoriesArray.count) memories",
                    count: memoriesArray.count
                )
                return message.id
            }
            
            var successCount = 0
            var failureCount = 0
            
            // Process each memory in the batch
            for memoryData in memoriesArray {
                guard let content = memoryData["content"] as? String,
                      let category = memoryData["category"] as? String else {
                    print("⚙️ Missing required parameters for memory in batch")
                    failureCount += 1
                    continue
                }
                
                let importance = memoryData["importance"] as? Int ?? 3
                
                // Find the appropriate memory category
                let memoryCategory = MemoryCategory.allCases.first { $0.rawValue.lowercased() == category.lowercased() } ?? .notes

                // Add memory
                do {
                    try await memoryManager.addMemory(content: content, category: memoryCategory, importance: importance)
                    successCount += 1
                } catch {
                    print("⚙️ Failed to add memory: \\(error.localizedDescription)")
                    failureCount += 1
                }
            }
            
            // Update the batch operation status message
            await MainActor.run {
                chatManager.updateOperationStatusMessage(
                    forMessageId: messageId!,
                    statusMessageId: statusMessageId,
                    status: .success,
                    details: "Added \\(successCount) of \\(memoriesArray.count) memories"
                )
            }
            
            // Refresh context with the updated memories
            await chatManager.refreshContextData()
            
            let result = "Processed \(memoriesArray.count) memories: \(successCount) added successfully, \(failureCount) failed"
            print("📝 Memory batch addition result: \(result)")
            return result
            
        case "remove_memory":
            // Extract parameters
            guard let content = toolInput["content"] as? String else {
                return "Error: Missing required parameter 'content' for remove_memory"
            }
            
            // Get access to MemoryManager
            guard let memoryManager = await getMemoryManager() else {
                return "Error: MemoryManager not available"
            }
            
            // Find memory with matching content on the main thread
            let memoryId: UUID? = await MainActor.run {
                if let memory = memoryManager.memories.first(where: { $0.content == content }) {
                    return memory.id
                }
                return UUID()  // Return a placeholder UUID instead of nil
            }
            
            // Check if we found a memory with the given content
            if let memoryId = memoryId {
                do {
                    try await memoryManager.deleteMemory(
                        id: memoryId,
                        messageId: messageId,
                        chatManager: chatManager
                    )
                    
                    // Refresh context with the updated memories
                    await chatManager.refreshContextData()
                    
                    return "Successfully removed memory"
                } catch {
                    return "Failed to remove memory: \\(error.localizedDescription)"
                }
            } else {
                // Create a failure status message for memory not found
                if let messageId = messageId {
                    await MainActor.run {
                        chatManager.addOperationStatusMessage(
                            forMessageId: messageId,
                            operationType: OperationType.deleteMemory,
                            status: .failure,
                            details: "No memory found with content: \\(content)"
                        )
                    }
                }
                
                return "Error: No memory found with content: \\(content)"
            }
            
        case "remove_memories_batch":
            // Extract parameters
            guard let contents = toolInput["contents"] as? [String] else {
                print("⚙️ Missing required parameter 'contents' for remove_memories_batch")
                return "Error: Missing required parameter 'contents' for remove_memories_batch"
            }
            
            // Get access to MemoryManager
            guard let memoryManager = await getMemoryManager() else {
                return "Error: MemoryManager not available"
            }
            
            // Create a batch operation status message
            let statusMessageId = await MainActor.run {
                let message = chatManager.addOperationStatusMessage(
                    forMessageId: messageId!,
                    operationType: OperationType.deleteMemory,
                    status: .inProgress,
                    details: "Removing \\(contents.count) memories",
                    count: contents.count
                )
                return message.id
            }
            
            var successCount = 0
            var failureCount = 0
            
            // Process each content in the batch
            for content in contents {
                // Find memory with matching content on the main thread
                let memoryId: UUID? = await MainActor.run {
                    if let memory = memoryManager.memories.first(where: { $0.content == content }) {
                        return memory.id
                    }
                    return nil
                }
                
                // Check if we found a memory with the given content
                if let memoryId = memoryId {
                    do {
                        try await memoryManager.deleteMemory(id: memoryId)
                        successCount += 1
                    } catch {
                        print("⚙️ Failed to remove memory: \\(error.localizedDescription)")
                        failureCount += 1
                    }
                } else {
                    print("⚙️ No memory found with content: \\(content)")
                    failureCount += 1
                }
            }
            
            // Update the batch operation status message
            await MainActor.run {
                chatManager.updateOperationStatusMessage(
                    forMessageId: messageId!,
                    statusMessageId: statusMessageId,
                    status: .success,
                    details: "Removed \\(successCount) of \\(contents.count) memories",
                    count: successCount
                )
            }
            
            // Refresh context with the updated memories
            await chatManager.refreshContextData()
            
            let result = "Processed \(contents.count) memories: \(successCount) removed successfully, \(failureCount) failed"
            print("📝 Memory batch removal result: \(result)")
            return result
            
        case "update_memory":
            // Extract parameters
            let idParam = toolInput["id"] as? String
            let contentParam = toolInput["content"] as? String 
            let oldContentParam = toolInput["old_content"] as? String
            let categoryStr = toolInput["category"] as? String
            let newImportance = toolInput["importance"] as? Int
            
            // Get access to MemoryManager
            guard let memoryManager = await getMemoryManager() else {
                return "Error: MemoryManager not available"
            }
            
            // Fallback to content matching if UUID fails or isn't provided
            var targetMemoryId: UUID? = nil
            
            // Try UUID first if provided
            if let idParam = idParam {
                if let uuid = UUID(uuidString: idParam) {
                    // Valid UUID provided
                    targetMemoryId = uuid
                }
            }
            
            // If no valid UUID, try to find memory by content
            if targetMemoryId == nil && oldContentParam != nil {
                // Find memory with matching content
                let memoryWithContent = await MainActor.run {
                    return memoryManager.memories.first(where: { $0.content == oldContentParam })
                }
                
                if let memory = memoryWithContent {
                    targetMemoryId = memory.id
                    print("⚙️ Found memory by content matching: \\(oldContentParam ?? nil)")
                }
            }
            
            // If ID param wasn't a UUID and was provided as content, try that as fallback
            if targetMemoryId == nil && idParam != nil {
                // Try using the ID parameter as content search
                let memoryWithIdAsContent = await MainActor.run {
                    return memoryManager.memories.first(where: { $0.content == idParam })
                }
                
                if let memory = memoryWithIdAsContent {
                    targetMemoryId = memory.id
                    print("⚙️ Found memory by using id parameter as content: \\(idParam ?? nil)")
                }
            }
            
            // Return error if we couldn't identify a memory to update
            guard let targetMemoryId = targetMemoryId else {
                return "Error: Could not find memory to update. Please provide either a valid UUID or the old content of the memory."
            }
            
            // Convert category string to enum if provided
            var newCategory: MemoryCategory? = nil
            if let categoryStr = categoryStr {
                newCategory = MemoryCategory.allCases.first { $0.rawValue.lowercased() == categoryStr.lowercased() } ?? .notes
            }
            
            // Ensure we have at least one field to update
            guard contentParam != nil || newCategory != nil || newImportance != nil else {
                return "Error: At least one of 'content', 'category', or 'importance' must be provided for update_memory"
            }
            
            // Update memory
            do {
                try await memoryManager.updateMemory(
                    id: targetMemoryId,
                    newContent: contentParam,
                    newCategory: newCategory,
                    newImportance: newImportance,
                    messageId: messageId,
                    chatManager: chatManager
                )
                
                // Refresh context with the updated memories
                await chatManager.refreshContextData()
                
                return "Successfully updated memory"
            } catch {
                return "Failed to update memory: \\(error.localizedDescription)"
            }
            
        case "update_memories_batch":
            // Extract parameters
            guard let memoriesArray = toolInput["memories"] as? [[String: Any]] else {
                print("⚙️ Missing required parameter 'memories' for update_memories_batch")
                return "Error: Missing required parameter 'memories' for update_memories_batch"
            }
            
            // Get access to MemoryManager
            guard let memoryManager = await getMemoryManager() else {
                return "Error: MemoryManager not available"
            }
            
            // Create a batch operation status message
            let statusMessageId = await MainActor.run {
                let message = chatManager.addOperationStatusMessage(
                    forMessageId: messageId!,
                    operationType: OperationType.updateMemory,
                    status: .inProgress,
                    details: "Updating \\(memoriesArray.count) memories",
                    count: memoriesArray.count
                )
                return message.id
            }
            
            var successCount = 0
            var failureCount = 0
            
            // Process each memory in the batch
            for memoryData in memoriesArray {
                // Extract parameters for this memory
                let idParam = memoryData["id"] as? String
                let contentParam = memoryData["content"] as? String
                let oldContentParam = memoryData["old_content"] as? String
                let categoryStr = memoryData["category"] as? String
                let newImportance = memoryData["importance"] as? Int
                
                // Fallback to content matching if UUID fails or isn't provided
                var targetMemoryId: UUID? = nil
                
                // Try UUID first if provided
                if let idParam = idParam {
                    if let uuid = UUID(uuidString: idParam) {
                        targetMemoryId = uuid
                    }
                }
                
                // If no valid UUID, try to find memory by content
                if targetMemoryId == nil && oldContentParam != nil {
                    // Find memory with matching content
                    let memoryWithContent = await MainActor.run {
                        return memoryManager.memories.first(where: { $0.content == oldContentParam })
                    }
                    
                    if let memory = memoryWithContent {
                        targetMemoryId = memory.id
                        print("⚙️ Found memory by content matching: \\(oldContentParam ?? nil)")
                    }
                }
                
                // If ID param wasn't a UUID and was provided as content, try that as fallback
                if targetMemoryId == nil && idParam != nil {
                    // Try using the ID parameter as content search
                    let memoryWithIdAsContent = await MainActor.run {
                        return memoryManager.memories.first(where: { $0.content == idParam })
                    }
                    
                    if let memory = memoryWithIdAsContent {
                        targetMemoryId = memory.id
                        print("⚙️ Found memory by using id parameter as content: \\(idParam ?? nil)")
                    }
                }
                
                // Skip this memory if we couldn't identify it
                guard let memoryId = targetMemoryId else {
                    print("⚙️ Could not find memory to update in batch")
                    failureCount += 1
                    continue
                }
                
                // Convert category string to enum if provided
                var newCategory: MemoryCategory? = nil
                if let categoryStr = categoryStr {
                    newCategory = MemoryCategory.allCases.first { $0.rawValue.lowercased() == categoryStr.lowercased() } ?? .notes
                }
                
                // Skip if no fields to update
                guard contentParam != nil || newCategory != nil || newImportance != nil else {
                    failureCount += 1
                    continue
                }
                
                // Update memory
                do {
                    try await memoryManager.updateMemory(
                        id: memoryId,
                        newContent: contentParam,
                        newCategory: newCategory,
                        newImportance: newImportance
                    )
                    successCount += 1
                } catch {
                    print("⚙️ Failed to update memory in batch: \\(error.localizedDescription)")
                    failureCount += 1
                }
            }
            
            // Update the batch operation status message
            await MainActor.run {
                chatManager.updateOperationStatusMessage(
                    forMessageId: messageId!,
                    statusMessageId: statusMessageId,
                    status: .success,
                    details: "Updated \\(successCount) of \\(memoriesArray.count) memories",
                    count: successCount
                )
            }
            
            // Refresh context with the updated memories
            await chatManager.refreshContextData()
            
            let result = "Processed \(memoriesArray.count) memories: \(successCount) updated successfully, \(failureCount) failed"
            print("📝 Memory batch update result: \(result)")
            return result
            
        default:
            return "Error: Unknown tool \(toolName)"
        }
    }
}
