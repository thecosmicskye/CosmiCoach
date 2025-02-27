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
        
        // Create operation status message if we have a message ID and chat manager
        var statusMessageId: UUID?
        var success = false
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            // Create operation status message on the main actor
            if let messageId = messageId, let chatManager = chatManager {
                statusMessageId = await MainActor.run {
                    let statusMessage = chatManager.addOperationStatusMessage(
                        forMessageId: messageId,
                        operationType: "Adding Calendar Event",
                        status: .inProgress
                    )
                    return statusMessage.id
                }
            }
            
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
                if let messageId = messageId, let statusMessageId = statusMessageId, let chatManager = chatManager {
                    await MainActor.run {
                        chatManager.updateOperationStatusMessage(
                            forMessageId: messageId,
                            statusMessageId: statusMessageId,
                            status: .success
                        )
                    }
                }
            } catch {
                print("📅 EventKitManager: Failed to save event: \(error.localizedDescription)")
                success = false
                
                // Update status message to failure
                if let messageId = messageId, let statusMessageId = statusMessageId, let chatManager = chatManager {
                    await MainActor.run {
                        chatManager.updateOperationStatusMessage(
                            forMessageId: messageId,
                            statusMessageId: statusMessageId,
                            status: .failure,
                            details: error.localizedDescription
                        )
                    }
                }
            }
            
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 5.0)
        return success
    }
    
    func updateCalendarEvent(id: String, title: String? = nil, startDate: Date? = nil, endDate: Date? = nil, notes: String? = nil, messageId: UUID? = nil, chatManager: ChatManager? = nil) -> Bool {
        print("📅 EventKitManager: Updating calendar event with ID - \(id)")
        guard calendarAccessGranted else {
            print("📅 EventKitManager: Calendar access not granted, cannot update event")
            return false
        }
        
        // Create operation status message if we have a message ID and chat manager
        var statusMessageId: UUID?
        var success = false
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            // Create operation status message on the main actor
            if let messageId = messageId, let chatManager = chatManager {
                statusMessageId = await MainActor.run {
                    let statusMessage = chatManager.addOperationStatusMessage(
                        forMessageId: messageId,
                        operationType: "Updating Calendar Event",
                        status: .inProgress
                    )
                    return statusMessage.id
                }
            }
            
            guard let event = self.eventStore.event(withIdentifier: id) else {
                print("Event not found with ID: \(id)")
                
                // Update status message to failure
                if let messageId = messageId, let statusMessageId = statusMessageId, let chatManager = chatManager {
                    await MainActor.run {
                        chatManager.updateOperationStatusMessage(
                            forMessageId: messageId,
                            statusMessageId: statusMessageId,
                            status: .failure,
                            details: "Event not found with ID: \(id)"
                        )
                    }
                }
                
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
                if let messageId = messageId, let statusMessageId = statusMessageId, let chatManager = chatManager {
                    await MainActor.run {
                        chatManager.updateOperationStatusMessage(
                            forMessageId: messageId,
                            statusMessageId: statusMessageId,
                            status: .success
                        )
                    }
                }
            } catch {
                print("Failed to update event: \(error.localizedDescription)")
                success = false
                
                // Update status message to failure
                if let messageId = messageId, let statusMessageId = statusMessageId, let chatManager = chatManager {
                    await MainActor.run {
                        chatManager.updateOperationStatusMessage(
                            forMessageId: messageId,
                            statusMessageId: statusMessageId,
                            status: .failure,
                            details: error.localizedDescription
                        )
                    }
                }
            }
            
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 5.0)
        return success
    }
    
    func deleteCalendarEvent(id: String, messageId: UUID? = nil, chatManager: ChatManager? = nil) -> Bool {
        print("📅 EventKitManager: Deleting calendar event with ID - \(id)")
        guard calendarAccessGranted else {
            print("📅 EventKitManager: Calendar access not granted, cannot delete event")
            return false
        }
        
        // Create operation status message if we have a message ID and chat manager
        var statusMessageId: UUID?
        var success = false
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            // Create operation status message on the main actor
            if let messageId = messageId, let chatManager = chatManager {
                statusMessageId = await MainActor.run {
                    let statusMessage = chatManager.addOperationStatusMessage(
                        forMessageId: messageId,
                        operationType: "Deleting Calendar Event",
                        status: .inProgress
                    )
                    return statusMessage.id
                }
            }
            
            guard let event = self.eventStore.event(withIdentifier: id) else {
                print("Event not found with ID: \(id)")
                
                // Update status message to failure
                if let messageId = messageId, let statusMessageId = statusMessageId, let chatManager = chatManager {
                    await MainActor.run {
                        chatManager.updateOperationStatusMessage(
                            forMessageId: messageId,
                            statusMessageId: statusMessageId,
                            status: .failure,
                            details: "Event not found with ID: \(id)"
                        )
                    }
                }
                
                success = false
                semaphore.signal()
                return
            }
            
            do {
                try self.eventStore.remove(event, span: .thisEvent)
                success = true
                
                // Update status message to success
                if let messageId = messageId, let statusMessageId = statusMessageId, let chatManager = chatManager {
                    await MainActor.run {
                        chatManager.updateOperationStatusMessage(
                            forMessageId: messageId,
                            statusMessageId: statusMessageId,
                            status: .success
                        )
                    }
                }
            } catch {
                print("Failed to delete event: \(error.localizedDescription)")
                success = false
                
                // Update status message to failure
                if let messageId = messageId, let statusMessageId = statusMessageId, let chatManager = chatManager {
                    await MainActor.run {
                        chatManager.updateOperationStatusMessage(
                            forMessageId: messageId,
                            statusMessageId: statusMessageId,
                            status: .failure,
                            details: error.localizedDescription
                        )
                    }
                }
            }
            
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 5.0)
        return success
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
        
        // Create operation status message if we have a message ID and chat manager
        var statusMessageId: UUID?
        var success = false
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            // Create operation status message on the main actor
            if let messageId = messageId, let chatManager = chatManager {
                statusMessageId = await MainActor.run {
                    let statusMessage = chatManager.addOperationStatusMessage(
                        forMessageId: messageId,
                        operationType: "Adding Reminder",
                        status: .inProgress
                    )
                    return statusMessage.id
                }
            }
            
            success = await addReminderAsync(title: title, dueDate: dueDate, notes: notes, listName: listName)
            
            // Update status message based on result
            if let messageId = messageId, let statusMessageId = statusMessageId, let chatManager = chatManager {
                if success {
                    await MainActor.run {
                        chatManager.updateOperationStatusMessage(
                            forMessageId: messageId,
                            statusMessageId: statusMessageId,
                            status: .success
                        )
                    }
                } else {
                    await MainActor.run {
                        chatManager.updateOperationStatusMessage(
                            forMessageId: messageId,
                            statusMessageId: statusMessageId,
                            status: .failure,
                            details: "Failed to add reminder"
                        )
                    }
                }
            }
            
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 5.0)
        return success
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
        
        // Set the reminder list based on the provided list name or use default
        if let listName = listName {
            let reminderLists = fetchReminderLists()
            if let matchingList = reminderLists.first(where: { $0.title.lowercased() == listName.lowercased() }) {
                reminder.calendar = matchingList
            } else {
                // If no matching list is found, use default
                if let calendar = eventStore.defaultCalendarForNewReminders() {
                    reminder.calendar = calendar
                }
                print("📅 EventKitManager: Reminder list '\(listName)' not found, using default list")
            }
        } else {
            // Use default reminder list if no list name provided
            if let calendar = eventStore.defaultCalendarForNewReminders() {
                reminder.calendar = calendar
            }
        }
        
        do {
            try eventStore.save(reminder, commit: true)
            print("📅 EventKitManager: Successfully added reminder - \(title)")
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
        
        // Create operation status message if we have a message ID and chat manager
        var statusMessageId: UUID?
        var result = false
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            // Create operation status message on the main actor
            if let messageId = messageId, let chatManager = chatManager {
                statusMessageId = await MainActor.run {
                    let statusMessage = chatManager.addOperationStatusMessage(
                        forMessageId: messageId,
                        operationType: "Updating Reminder",
                        status: .inProgress
                    )
                    return statusMessage.id
                }
            }
            
            result = await updateReminder(id: id, title: title, dueDate: dueDate, notes: notes, isCompleted: isCompleted, listName: listName)
            
            // Update status message based on result
            if let messageId = messageId, let statusMessageId = statusMessageId, let chatManager = chatManager {
                if result {
                    await MainActor.run {
                        chatManager.updateOperationStatusMessage(
                            forMessageId: messageId,
                            statusMessageId: statusMessageId,
                            status: .success
                        )
                    }
                } else {
                    await MainActor.run {
                        chatManager.updateOperationStatusMessage(
                            forMessageId: messageId,
                            statusMessageId: statusMessageId,
                            status: .failure,
                            details: "Failed to update reminder"
                        )
                    }
                }
            }
            
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 5.0)
        return result
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
        
        // Create operation status message if we have a message ID and chat manager
        var statusMessageId: UUID?
        var result = false
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            // Create operation status message on the main actor
            if let messageId = messageId, let chatManager = chatManager {
                statusMessageId = await MainActor.run {
                    let statusMessage = chatManager.addOperationStatusMessage(
                        forMessageId: messageId,
                        operationType: "Deleting Reminder",
                        status: .inProgress
                    )
                    return statusMessage.id
                }
            }
            
            result = await deleteReminder(id: id)
            
            // Update status message based on result
            if let messageId = messageId, let statusMessageId = statusMessageId, let chatManager = chatManager {
                if result {
                    await MainActor.run {
                        chatManager.updateOperationStatusMessage(
                            forMessageId: messageId,
                            statusMessageId: statusMessageId,
                            status: .success
                        )
                    }
                } else {
                    await MainActor.run {
                        chatManager.updateOperationStatusMessage(
                            forMessageId: messageId,
                            statusMessageId: statusMessageId,
                            status: .failure,
                            details: "Failed to delete reminder"
                        )
                    }
                }
            }
            
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 5.0)
        return result
    }
}
