import Foundation
import EventKit

struct CalendarEvent: Identifiable {
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
