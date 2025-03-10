import Foundation
import EventKit

struct CalendarEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let notes: String?
    let calendar: EKCalendar
    
    init(from ekEvent: EKEvent) {
        self.id = ekEvent.eventIdentifier ?? UUID().uuidString
        self.title = ekEvent.title ?? "Untitled Event"
        self.startDate = ekEvent.startDate
        self.endDate = ekEvent.endDate
        self.notes = ekEvent.notes
        self.calendar = ekEvent.calendar
    }
    
    // Implement Hashable for more reliable hashing
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        // Round dates to nearest minute to prevent tiny timestamp differences
        let startInterval = startDate.timeIntervalSince1970
        let roundedStartInterval = round(startInterval / 60) * 60
        hasher.combine(roundedStartInterval)
        
        let endInterval = endDate.timeIntervalSince1970
        let roundedEndInterval = round(endInterval / 60) * 60
        hasher.combine(roundedEndInterval)
        
        // Include notes in hash if present
        if let notes = notes {
            hasher.combine(notes)
        }
        
        // Include calendar information
        hasher.combine(calendar.title)
    }
    
    // Required for Hashable
    static func == (lhs: CalendarEvent, rhs: CalendarEvent) -> Bool {
        return lhs.id == rhs.id &&
               lhs.title == rhs.title &&
               abs(lhs.startDate.timeIntervalSince(rhs.startDate)) < 60 && // Within 1 minute
               abs(lhs.endDate.timeIntervalSince(rhs.endDate)) < 60 &&     // Within 1 minute
               lhs.notes == rhs.notes &&
               lhs.calendar.title == rhs.calendar.title
    }
    
    // For testing purposes
    init(from ekEvent: EKEvent? = nil, id: String, title: String, startDate: Date, endDate: Date, notes: String?) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
        
        // Create a mock calendar for testing
        let eventStore = EKEventStore()
        self.calendar = ekEvent?.calendar ?? eventStore.defaultCalendarForNewEvents ?? EKCalendar(for: .event, eventStore: eventStore)
    }
}
