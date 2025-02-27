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
    
    func addCalendarEvent(title: String, startDate: Date, endDate: Date, notes: String? = nil) -> Bool {
        guard calendarAccessGranted else { return false }
        
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.notes = notes
        
        // Use default calendar
        event.calendar = eventStore.defaultCalendarForNewEvents
        
        do {
            try eventStore.save(event, span: .thisEvent)
            return true
        } catch {
            print("Failed to save event: \(error.localizedDescription)")
            return false
        }
    }
    
    func updateCalendarEvent(id: String, title: String? = nil, startDate: Date? = nil, endDate: Date? = nil, notes: String? = nil) -> Bool {
        guard calendarAccessGranted else { return false }
        
        guard let event = eventStore.event(withIdentifier: id) else {
            print("Event not found with ID: \(id)")
            return false
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
            try eventStore.save(event, span: .thisEvent)
            return true
        } catch {
            print("Failed to update event: \(error.localizedDescription)")
            return false
        }
    }
    
    func deleteCalendarEvent(id: String) -> Bool {
        guard calendarAccessGranted else { return false }
        
        guard let event = eventStore.event(withIdentifier: id) else {
            print("Event not found with ID: \(id)")
            return false
        }
        
        do {
            try eventStore.remove(event, span: .thisEvent)
            return true
        } catch {
            print("Failed to delete event: \(error.localizedDescription)")
            return false
        }
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
    
    func addReminder(title: String, dueDate: Date? = nil, notes: String? = nil, listName: String? = nil) -> Bool {
        guard reminderAccessGranted else { return false }
        
        var success = false
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            success = await addReminderAsync(title: title, dueDate: dueDate, notes: notes, listName: listName)
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 5.0)
        return success
    }
    
    func addReminderAsync(title: String, dueDate: Date? = nil, notes: String? = nil, listName: String? = nil) async -> Bool {
        guard reminderAccessGranted else { return false }
        
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
                print("Reminder list '\(listName)' not found, using default list")
            }
        } else {
            // Use default reminder list if no list name provided
            if let calendar = eventStore.defaultCalendarForNewReminders() {
                reminder.calendar = calendar
            }
        }
        
        do {
            try eventStore.save(reminder, commit: true)
            return true
        } catch {
            print("Failed to save reminder: \(error.localizedDescription)")
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
        guard reminderAccessGranted else { return false }
        
        // Fetch the reminder by ID
        guard let reminder = await fetchReminderById(id: id) else {
            print("Reminder not found with ID: \(id)")
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
                print("Reminder list '\(listName)' not found, keeping the current list")
            }
        }
        
        do {
            try eventStore.save(reminder, commit: true)
            return true
        } catch {
            print("Failed to update reminder: \(error.localizedDescription)")
            return false
        }
    }
    
    // For backward compatibility
    func updateReminder(id: String, title: String? = nil, dueDate: Date? = nil, notes: String? = nil, isCompleted: Bool? = nil, listName: String? = nil) -> Bool {
        var result = false
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            result = await updateReminder(id: id, title: title, dueDate: dueDate, notes: notes, isCompleted: isCompleted, listName: listName)
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 5.0)
        return result
    }
    
    func deleteReminder(id: String) async -> Bool {
        guard reminderAccessGranted else { return false }
        
        // Fetch the reminder by ID
        guard let reminder = await fetchReminderById(id: id) else {
            print("Reminder not found with ID: \(id)")
            return false
        }
        
        do {
            try eventStore.remove(reminder, commit: true)
            return true
        } catch {
            print("Failed to delete reminder: \(error.localizedDescription)")
            return false
        }
    }
    
    // For backward compatibility
    func deleteReminder(id: String) -> Bool {
        var result = false
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            result = await deleteReminder(id: id)
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 5.0)
        return result
    }
}
