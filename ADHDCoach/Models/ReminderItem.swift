import Foundation
import EventKit

struct ReminderItem: Identifiable, Hashable {
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
    
    // Implement Hashable for more reliable hashing
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(isCompleted)
        
        // Handle dueDate specially to prevent tiny timestamp differences
        if let dueDate = dueDate {
            let dueInterval = dueDate.timeIntervalSince1970
            let roundedDueInterval = round(dueInterval / 60) * 60 // Round to nearest minute
            hasher.combine(roundedDueInterval)
        } else {
            // Use a consistent value for nil dates
            hasher.combine(-1)
        }
        
        // Include notes in hash if present
        if let notes = notes {
            hasher.combine(notes)
        }
        
        // Include list name
        hasher.combine(listName)
    }
    
    // Required for Hashable
    static func == (lhs: ReminderItem, rhs: ReminderItem) -> Bool {
        // For dates, check if they're within a minute of each other
        let datesEqual: Bool
        if let lhsDate = lhs.dueDate, let rhsDate = rhs.dueDate {
            datesEqual = abs(lhsDate.timeIntervalSince(rhsDate)) < 60 // within a minute
        } else {
            datesEqual = lhs.dueDate == nil && rhs.dueDate == nil // both nil
        }
        
        return lhs.id == rhs.id &&
               lhs.title == rhs.title &&
               datesEqual &&
               lhs.notes == rhs.notes &&
               lhs.isCompleted == rhs.isCompleted &&
               lhs.listName == rhs.listName
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
