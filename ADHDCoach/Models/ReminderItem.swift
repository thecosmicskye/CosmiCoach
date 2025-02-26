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
}
