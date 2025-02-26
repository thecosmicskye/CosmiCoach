import XCTest
import EventKit
@testable import ADHDCoach

final class CalendarEventTests: XCTestCase {
    
    func testInitializationFromProperties() {
        // Given
        let id = "test-id-123"
        let title = "Test Event"
        let startDate = Date()
        let endDate = Date(timeIntervalSinceNow: 3600) // 1 hour later
        let notes = "Test notes"
        
        // When
        let event = CalendarEvent(id: id, title: title, startDate: startDate, endDate: endDate, notes: notes)
        
        // Then
        XCTAssertEqual(event.id, id)
        XCTAssertEqual(event.title, title)
        XCTAssertEqual(event.startDate, startDate)
        XCTAssertEqual(event.endDate, endDate)
        XCTAssertEqual(event.notes, notes)
    }
    
    func testInitializationFromPropertiesWithNilNotes() {
        // Given
        let id = "test-id-123"
        let title = "Test Event"
        let startDate = Date()
        let endDate = Date(timeIntervalSinceNow: 3600) // 1 hour later
        
        // When
        let event = CalendarEvent(id: id, title: title, startDate: startDate, endDate: endDate, notes: nil)
        
        // Then
        XCTAssertEqual(event.id, id)
        XCTAssertEqual(event.title, title)
        XCTAssertEqual(event.startDate, startDate)
        XCTAssertEqual(event.endDate, endDate)
        XCTAssertNil(event.notes)
    }
    
    func testInitializationFromEKEvent() {
        // Given
        let eventStore = EKEventStore()
        let ekEvent = EKEvent(eventStore: eventStore)
        
        ekEvent.title = "Test EK Event"
        ekEvent.startDate = Date()
        ekEvent.endDate = Date(timeIntervalSinceNow: 3600)
        ekEvent.notes = "Test EK notes"
        
        // We need to set a calendar for the event to have a valid calendarItemIdentifier
        if let calendar = eventStore.defaultCalendarForNewEvents {
            ekEvent.calendar = calendar
        }
        
        // When
        let event = CalendarEvent(from: ekEvent)
        
        // Then
        XCTAssertEqual(event.id, ekEvent.calendarItemIdentifier)
        XCTAssertEqual(event.title, ekEvent.title)
        XCTAssertEqual(event.startDate, ekEvent.startDate)
        XCTAssertEqual(event.endDate, ekEvent.endDate)
        XCTAssertEqual(event.notes, ekEvent.notes)
    }
    
    func testInitializationFromEKEventWithNilNotes() {
        // Given
        let eventStore = EKEventStore()
        let ekEvent = EKEvent(eventStore: eventStore)
        
        ekEvent.title = "Test EK Event"
        ekEvent.startDate = Date()
        ekEvent.endDate = Date(timeIntervalSinceNow: 3600)
        ekEvent.notes = nil
        
        // We need to set a calendar for the event to have a valid calendarItemIdentifier
        if let calendar = eventStore.defaultCalendarForNewEvents {
            ekEvent.calendar = calendar
        }
        
        // When
        let event = CalendarEvent(from: ekEvent)
        
        // Then
        XCTAssertEqual(event.id, ekEvent.calendarItemIdentifier)
        XCTAssertEqual(event.title, ekEvent.title)
        XCTAssertEqual(event.startDate, ekEvent.startDate)
        XCTAssertEqual(event.endDate, ekEvent.endDate)
        XCTAssertNil(event.notes)
    }
    
    func testEventsWithEqualPropertiesAreEqual() {
        // Given
        let now = Date()
        let later = Date(timeIntervalSinceNow: 3600)
        
        let event1 = CalendarEvent(id: "test-id", title: "Test", startDate: now, endDate: later, notes: "Notes")
        let event2 = CalendarEvent(id: "test-id", title: "Test", startDate: now, endDate: later, notes: "Notes")
        
        // Then
        XCTAssertEqual(event1.id, event2.id)
        XCTAssertEqual(event1.title, event2.title)
        XCTAssertEqual(event1.startDate, event2.startDate)
        XCTAssertEqual(event1.endDate, event2.endDate)
        XCTAssertEqual(event1.notes, event2.notes)
    }
}
