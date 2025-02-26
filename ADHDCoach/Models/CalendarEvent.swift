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
}
