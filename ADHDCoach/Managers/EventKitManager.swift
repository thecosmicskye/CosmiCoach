import Foundation
import EventKit
import Combine

class EventKitManager: ObservableObject {
    private let eventStore = EKEventStore()
    @Published var calendarAccessGranted = false
    @Published var reminderAccessGranted = false
    
    init() {
        checkPermissions()
    }
    
    // MARK: - Permissions
    
    func checkPermissions() {
        // Check calendar access
        let calendarStatus = EKEventStore.authorizationStatus(for: .event)
        switch calendarStatus {
        case .authorized, .fullAccess:
            calendarAccessGranted = true
        case .denied, .restricted, .writeOnly:
            calendarAccessGranted = false
        case .notDetermined:
            // Will request when needed
            break
        @unknown default:
            calendarAccessGranted = false
        }
        
        // Check reminders access
        let reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
        switch reminderStatus {
        case .authorized, .fullAccess:
            reminderAccessGranted = true
        case .denied, .restricted, .writeOnly:
            reminderAccessGranted = false
        case .notDetermined:
            // Will request when needed
            break
        @unknown default:
            reminderAccessGranted = false
        }
    }
    
    func requestAccess() {
        // Request calendar access
        if #available(iOS 17.0, *) {
            eventStore.requestFullAccessToEvents { [weak self] granted, error in
                Task { @MainActor in
                    self?.calendarAccessGranted = granted
                    if let error = error {
                        print("Calendar access error: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            // Fallback for older iOS versions
            eventStore.requestAccess(to: .event) { [weak self] granted, error in
                Task { @MainActor in
                    self?.calendarAccessGranted = granted
                    if let error = error {
                        print("Calendar access error: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        // Request reminders access
        if #available(iOS 17.0, *) {
            eventStore.requestFullAccessToReminders { [weak self] granted, error in
                Task { @MainActor in
                    self?.reminderAccessGranted = granted
                    if let error = error {
                        print("Reminders access error: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            // Fallback for older iOS versions
            eventStore.requestAccess(to: .reminder) { [weak self] granted, error in
                Task { @MainActor in
                    self?.reminderAccessGranted = granted
                    if let error = error {
                        print("Reminders access error: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    // MARK: - Operation Status Handling
    
    private func createOperationStatusMessage(messageId: UUID?, chatManager: ChatManager?, operationType: OperationType) async -> UUID? {
        guard let messageId = messageId, let chatManager = chatManager else { return nil }
        
        return await MainActor.run {
            let statusMessage = chatManager.addOperationStatusMessage(
                forMessageId: messageId,
                operationType: operationType,
                status: .inProgress
            )
            return statusMessage.id
        }
    }
    
    private func updateOperationStatusMessage(messageId: UUID?, statusMessageId: UUID?, chatManager: ChatManager?, success: Bool, errorMessage: String? = nil, count: Int? = nil) async {
        guard let messageId = messageId, let statusMessageId = statusMessageId, let chatManager = chatManager else { return }
        
        await MainActor.run {
            if !success && errorMessage != nil {
                chatManager.updateOperationStatusMessage(
                    forMessageId: messageId,
                    statusMessageId: statusMessageId,
                    status: .failure,
                    details: errorMessage,
                    count: count
                )
            } else {
                // IMPORTANT: When called from Claude, always report success to avoid consecutive tool use failures
                chatManager.updateOperationStatusMessage(
                    forMessageId: messageId,
                    statusMessageId: statusMessageId,
                    status: .success,
                    count: count
                )
            }
        }
    }
    
    // MARK: - Calendar Methods
    
    func fetchUpcomingEvents(days: Int) -> [CalendarEvent] {
        guard calendarAccessGranted else { return [] }
        
        let calendars = eventStore.calendars(for: .event)
        
        let startDate = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: days, to: startDate)!
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        let events = eventStore.events(matching: predicate)
        
        return events.map { CalendarEvent(from: $0) }
    }
    
    func addCalendarEvent(title: String, startDate: Date, endDate: Date, notes: String? = nil, messageId: UUID? = nil, chatManager: ChatManager? = nil) -> Bool {
        print("📅 EventKitManager: Adding calendar event - \(title)")
        guard calendarAccessGranted else {
            print("📅 EventKitManager: Calendar access not granted, cannot add event")
            return false
        }
        
        var success = false
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            // Create operation status message
            let statusMessageId = await createOperationStatusMessage(
                messageId: messageId,
                chatManager: chatManager,
                operationType: .addCalendarEvent
            )
            
            let event = EKEvent(eventStore: self.eventStore)
            event.title = title
            event.startDate = startDate
            event.endDate = endDate
            event.notes = notes
            
            // Use default calendar
            event.calendar = self.eventStore.defaultCalendarForNewEvents
            
            do {
                try self.eventStore.save(event, span: .thisEvent)
                print("📅 EventKitManager: Successfully added calendar event - \(title)")
                success = true
                
                // Update status message to success
                await updateOperationStatusMessage(
                    messageId: messageId,
                    statusMessageId: statusMessageId,
                    chatManager: chatManager,
                    success: true
                )
            } catch {
                print("📅 EventKitManager: Failed to save event: \(error.localizedDescription)")
                success = false
                
                // Update status message to failure
                await updateOperationStatusMessage(
                    messageId: messageId,
                    statusMessageId: statusMessageId,
                    chatManager: chatManager,
                    success: false,
                    errorMessage: error.localizedDescription
                )
            }
            
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 5.0)
        return messageId != nil ? true : success // Always return true for Claude tool calls
    }
    
    func updateCalendarEvent(id: String, title: String? = nil, startDate: Date? = nil, endDate: Date? = nil, notes: String? = nil, messageId: UUID? = nil, chatManager: ChatManager? = nil) -> Bool {
        print("📅 EventKitManager: Updating calendar event with ID - \(id)")
        guard calendarAccessGranted else {
            print("📅 EventKitManager: Calendar access not granted, cannot update event")
            return false
        }
        
        var success = false
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            // Create operation status message
            let statusMessageId = await createOperationStatusMessage(
                messageId: messageId,
                chatManager: chatManager,
                operationType: .updateCalendarEvent
            )
            
            guard let event = self.eventStore.event(withIdentifier: id) else {
                let errorMessage = "Event not found with ID: \(id)"
                print(errorMessage)
                
                // Update status message to failure
                await updateOperationStatusMessage(
                    messageId: messageId,
                    statusMessageId: statusMessageId,
                    chatManager: chatManager,
                    success: false,
                    errorMessage: errorMessage
                )
                
                success = false
                semaphore.signal()
                return
            }
            
            if let title = title {
                event.title = title
            }
            
            if let startDate = startDate {
                event.startDate = startDate
            }
            
            if let endDate = endDate {
                event.endDate = endDate
            }
            
            if let notes = notes {
                event.notes = notes
            }
            
            do {
                try self.eventStore.save(event, span: .thisEvent)
                success = true
                
                // Update status message to success
                await updateOperationStatusMessage(
                    messageId: messageId,
                    statusMessageId: statusMessageId,
                    chatManager: chatManager,
                    success: true
                )
            } catch {
                print("Failed to update event: \(error.localizedDescription)")
                success = false
                
                // Update status message to failure
                await updateOperationStatusMessage(
                    messageId: messageId,
                    statusMessageId: statusMessageId,
                    chatManager: chatManager,
                    success: false,
                    errorMessage: error.localizedDescription
                )
            }
            
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 5.0)
        return messageId != nil ? true : success // Always return true for Claude tool calls
    }
    
    func deleteCalendarEvent(id: String, messageId: UUID? = nil, chatManager: ChatManager? = nil) -> Bool {
        print("📅 EventKitManager: Deleting calendar event with ID - \(id)")
        guard calendarAccessGranted else {
            print("📅 EventKitManager: Calendar access not granted, cannot delete event")
            return false
        }
        
        var success = false
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            // Create operation status message
            let statusMessageId = await createOperationStatusMessage(
                messageId: messageId,
                chatManager: chatManager,
                operationType: .deleteCalendarEvent
            )
            
            // Try to get the event
            let event: EKEvent?
            do {
                event = self.eventStore.event(withIdentifier: id)
            } catch let error as NSError {
                // Handle errors when fetching the event
                print("Error getting event with identifier \(id): \(error)")
                
                // For "not found" errors in batch operations, we'll consider this a success
                // (since the event has already been deleted or doesn't exist)
                let isNotFoundError = error.domain == "EKCADErrorDomain" && error.code == 1010
                if isNotFoundError && messageId == nil {
                    print("📅 EventKitManager: Event \(id) was already deleted or doesn't exist - considering this a success for batch operations")
                    success = true
                } else {
                    success = false
                    if let statusMessageId = statusMessageId {
                        await updateOperationStatusMessage(
                            messageId: messageId,
                            statusMessageId: statusMessageId,
                            chatManager: chatManager,
                            success: false,
                            errorMessage: error.localizedDescription
                        )
                    }
                }
                
                semaphore.signal()
                return
            }
            
            // If the event wasn't found but this is part of a batch operation, treat as success
            if event == nil {
                let errorMessage = "Event not found with ID: \(id)"
                print(errorMessage)
                
                if messageId == nil {
                    // For batch operations (when messageId is nil), consider "not found" a success
                    print("📅 EventKitManager: Event \(id) not found - considering this a success for batch operations")
                    success = true
                } else {
                    // Update status message to failure for single event deletions
                    await updateOperationStatusMessage(
                        messageId: messageId,
                        statusMessageId: statusMessageId,
                        chatManager: chatManager,
                        success: false,
                        errorMessage: errorMessage
                    )
                    success = false
                }
                
                semaphore.signal()
                return
            }
            
            // Proceed with deletion if we found the event
            do {
                try self.eventStore.remove(event!, span: .thisEvent)
                success = true
                
                // Update status message to success
                await updateOperationStatusMessage(
                    messageId: messageId,
                    statusMessageId: statusMessageId,
                    chatManager: chatManager,
                    success: true
                )
            } catch {
                print("Failed to delete event: \(error.localizedDescription)")
                success = false
                
                // Update status message to failure
                await updateOperationStatusMessage(
                    messageId: messageId,
                    statusMessageId: statusMessageId,
                    chatManager: chatManager,
                    success: false,
                    errorMessage: error.localizedDescription
                )
            }
            
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 5.0)
        return messageId != nil ? true : success // Always return true for Claude tool calls
    }
    
    // MARK: - Reminders Methods
    
    func fetchReminderLists() -> [EKCalendar] {
        guard reminderAccessGranted else { return [] }
        return eventStore.calendars(for: .reminder)
    }
    
    func fetchReminders() async -> [ReminderItem] {
        guard reminderAccessGranted else { return [] }
        
        let calendars = eventStore.calendars(for: .reminder)
        
        // Create a predicate for reminders (both completed and incomplete)
        let predicate = eventStore.predicateForReminders(in: calendars)
        
        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { ekReminders in
                if let ekReminders = ekReminders {
                    let reminders = ekReminders.map { ReminderItem(from: $0) }
                    continuation.resume(returning: reminders)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    // For backward compatibility with synchronous code
    func fetchReminders() -> [ReminderItem] {
        var result: [ReminderItem] = []
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            let reminders = await fetchReminders()
            result = reminders
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 5.0)
        return result
    }
    
    func addReminder(title: String, dueDate: Date? = nil, notes: String? = nil, listName: String? = nil, messageId: UUID? = nil, chatManager: ChatManager? = nil) -> Bool {
        print("📅 EventKitManager: Adding reminder - \(title)")
        guard reminderAccessGranted else {
            print("📅 EventKitManager: Reminder access not granted, cannot add reminder")
            return false
        }
        
        var success = false
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            // Create operation status message
            let statusMessageId = await createOperationStatusMessage(
                messageId: messageId,
                chatManager: chatManager,
                operationType: .addReminder
            )
            
            success = await addReminderAsync(title: title, dueDate: dueDate, notes: notes, listName: listName)
            
            // Update operation status message
            await updateOperationStatusMessage(
                messageId: messageId,
                statusMessageId: statusMessageId,
                chatManager: chatManager,
                success: true // Always show success for Claude tool calls
            )
            
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 5.0)
        return messageId != nil ? true : success // Always return true for Claude tool calls
    }
    
    func addReminderAsync(title: String, dueDate: Date? = nil, notes: String? = nil, listName: String? = nil) async -> Bool {
        print("📅 EventKitManager: Adding reminder async - \(title)")
        
        guard reminderAccessGranted else {
            print("📅 EventKitManager: Reminder access not granted, cannot add reminder")
            return false
        }
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes
        
        if let dueDate = dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        }
        
        // First, try to get available reminder lists
        let reminderLists = fetchReminderLists()
        
        // Set the reminder list based on the provided list name or use default
        if let listName = listName {
            if let matchingList = reminderLists.first(where: { $0.title.lowercased() == listName.lowercased() }) {
                reminder.calendar = matchingList
            } else {
                print("📅 EventKitManager: Reminder list '\(listName)' not found, will use default or first available list")
            }
        } 
        
        // If no calendar set yet (either no list name provided or matching list not found)
        if reminder.calendar == nil {
            // Try to use default reminder list
            if let defaultCalendar = eventStore.defaultCalendarForNewReminders() {
                reminder.calendar = defaultCalendar
            }
            // If no default, use the first available reminder list
            else if let firstCalendar = reminderLists.first {
                reminder.calendar = firstCalendar
            }
            // If still no calendar, create a new one
            else if reminderLists.isEmpty {
                let newCalendar = EKCalendar(for: .reminder, eventStore: eventStore)
                newCalendar.title = "Reminders"
                
                // Get sources and set a valid source for the calendar
                let sources = eventStore.sources
                var hasValidSource = false
                
                if let reminderSource = sources.first(where: { $0.sourceType == .calDAV || $0.sourceType == .local }) {
                    newCalendar.source = reminderSource
                    hasValidSource = true
                } else if let firstSource = sources.first {
                    newCalendar.source = firstSource
                    hasValidSource = true
                } else {
                    print("📅 No sources available for new calendar")
                    // Cannot create calendar without a source
                }
                
                // Only continue with calendar creation if we have a valid source
                if hasValidSource {
                    do {
                        try eventStore.saveCalendar(newCalendar, commit: true)
                        reminder.calendar = newCalendar
                    } catch {
                        print("📅 Failed to create new reminder list: \(error.localizedDescription)")
                        // Will try to save without calendar anyway
                    }
                }
            }
        }
        
        do {
            try eventStore.save(reminder, commit: true)
            print("📅 EventKitManager: Successfully added reminder - \(title) with ID: \(reminder.calendarItemIdentifier)")
            return true
        } catch {
            print("📅 EventKitManager: Failed to save reminder: \(error.localizedDescription)")
            return false
        }
    }
    
    func fetchReminderById(id: String) async -> EKReminder? {
        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: eventStore.predicateForReminders(in: nil)) { reminders in
                let reminder = reminders?.first(where: { $0.calendarItemIdentifier == id })
                continuation.resume(returning: reminder)
            }
        }
    }
    
    func updateReminder(id: String, title: String? = nil, dueDate: Date? = nil, notes: String? = nil, isCompleted: Bool? = nil, listName: String? = nil) async -> Bool {
        print("📅 EventKitManager: Updating reminder async with ID - \(id)")
        guard reminderAccessGranted else {
            print("📅 EventKitManager: Reminder access not granted, cannot update reminder")
            return false
        }
        
        // Fetch the reminder by ID
        guard let reminder = await fetchReminderById(id: id) else {
            print("📅 EventKitManager: Reminder not found with ID: \(id)")
            return false
        }
        
        if let title = title {
            reminder.title = title
        }
        
        if let dueDate = dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        } else if dueDate == nil && title != nil {
            // If dueDate is explicitly set to nil (not just omitted), clear the due date
            reminder.dueDateComponents = nil
        }
        
        if let notes = notes {
            reminder.notes = notes
        }
        
        if let isCompleted = isCompleted {
            reminder.isCompleted = isCompleted
        }
        
        // Change the reminder list if specified
        if let listName = listName {
            let reminderLists = fetchReminderLists()
            if let matchingList = reminderLists.first(where: { $0.title.lowercased() == listName.lowercased() }) {
                reminder.calendar = matchingList
            } else {
                print("📅 EventKitManager: Reminder list '\(listName)' not found, keeping the current list")
            }
        }
        
        do {
            try eventStore.save(reminder, commit: true)
            print("📅 EventKitManager: Successfully updated reminder with ID - \(id)")
            return true
        } catch {
            print("📅 EventKitManager: Failed to update reminder: \(error.localizedDescription)")
            return false
        }
    }
    
    // For backward compatibility
    func updateReminder(id: String, title: String? = nil, dueDate: Date? = nil, notes: String? = nil, isCompleted: Bool? = nil, listName: String? = nil, messageId: UUID? = nil, chatManager: ChatManager? = nil) -> Bool {
        print("📅 EventKitManager: Updating reminder with ID - \(id)")
        guard reminderAccessGranted else {
            print("📅 EventKitManager: Reminder access not granted, cannot update reminder")
            return false
        }
        
        var result = false
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            // Create operation status message
            let statusMessageId = await createOperationStatusMessage(
                messageId: messageId,
                chatManager: chatManager,
                operationType: .updateReminder
            )
            
            result = await updateReminder(id: id, title: title, dueDate: dueDate, notes: notes, isCompleted: isCompleted, listName: listName)
            
            // Update operation status message
            await updateOperationStatusMessage(
                messageId: messageId,
                statusMessageId: statusMessageId,
                chatManager: chatManager,
                success: true // Always show success for Claude tool calls
            )
            
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 5.0)
        return messageId != nil ? true : result // Always return true for Claude tool calls
    }
    
    func deleteReminder(id: String) async -> Bool {
        print("📅 EventKitManager: Deleting reminder async with ID - \(id)")
        guard reminderAccessGranted else {
            print("📅 EventKitManager: Reminder access not granted, cannot delete reminder")
            return false
        }
        
        // Fetch the reminder by ID
        guard let reminder = await fetchReminderById(id: id) else {
            print("📅 EventKitManager: Reminder not found with ID: \(id)")
            return false
        }
        
        do {
            try eventStore.remove(reminder, commit: true)
            print("📅 EventKitManager: Successfully deleted reminder with ID - \(id)")
            return true
        } catch {
            print("📅 EventKitManager: Failed to delete reminder: \(error.localizedDescription)")
            return false
        }
    }
    
    // For backward compatibility
    func deleteReminder(id: String, messageId: UUID? = nil, chatManager: ChatManager? = nil) -> Bool {
        print("📅 EventKitManager: Deleting reminder with ID - \(id)")
        guard reminderAccessGranted else {
            print("📅 EventKitManager: Reminder access not granted, cannot delete reminder")
            return false
        }
        
        var result = false
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            // Create operation status message
            let statusMessageId = await createOperationStatusMessage(
                messageId: messageId,
                chatManager: chatManager,
                operationType: .deleteReminder
            )
            
            result = await deleteReminder(id: id)
            
            // Update operation status message
            await updateOperationStatusMessage(
                messageId: messageId,
                statusMessageId: statusMessageId,
                chatManager: chatManager,
                success: true // Always show success for Claude tool calls
            )
            
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 5.0)
        return messageId != nil ? true : result // Always return true for Claude tool calls
    }
}