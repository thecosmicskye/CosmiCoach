import Foundation
import EventKit

struct ReminderItem: Identifiable {
    let id: String
    let title: String
    let dueDate: Date?
    let notes: String?
    let isCompleted: Bool
    let list: EKCalendar
    
    var listName: String {
        return list.title
    }
    
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
        
        // Create a mock calendar for testing - using a synchronous approach
        let eventStore = EKEventStore()
        let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
        calendar.title = "Test Calendar"
        self.list = calendar
    }
}
