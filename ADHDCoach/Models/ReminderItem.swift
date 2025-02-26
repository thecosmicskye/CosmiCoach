import Foundation
import EventKit

struct ReminderItem: Identifiable {
    let id: String
    let title: String
    let dueDate: Date?
    let notes: String?
    let isCompleted: Bool
    let list: EKCalendar
    
    init(from ekReminder: EKReminder) {
        self.id = ekReminder.calendarItemIdentifier
        self.title = ekReminder.title ?? "Untitled Reminder"
        self.dueDate = ekReminder.dueDateComponents?.date
        self.notes = ekReminder.notes
        self.isCompleted = ekReminder.isCompleted
        self.list = ekReminder.calendar
    }
    
    // For testing purposes
    init(id: String, title: String, dueDate: Date?, notes: String?, isCompleted: Bool) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.notes = notes 
        self.isCompleted = isCompleted
        
        // Create a mock calendar for testing
        let eventStore = EKEventStore()
        self.list = eventStore.defaultCalendarForNewReminders() ?? EKCalendar(for: .reminder, eventStore: eventStore)
    }
}
