import XCTest
import EventKit
@testable import ADHDCoach

final class ReminderItemTests: XCTestCase {
    
    func testInitializationFromProperties() {
        // Given
        let id = "test-id-123"
        let title = "Test Reminder"
        let dueDate = Date()
        let notes = "Test notes"
        let isCompleted = true
        
        // When
        let reminder = ReminderItem(id: id, title: title, dueDate: dueDate, notes: notes, isCompleted: isCompleted)
        
        // Then
        XCTAssertEqual(reminder.id, id)
        XCTAssertEqual(reminder.title, title)
        XCTAssertEqual(reminder.dueDate, dueDate)
        XCTAssertEqual(reminder.notes, notes)
        XCTAssertEqual(reminder.isCompleted, isCompleted)
    }
    
    func testInitializationFromPropertiesWithOptionals() {
        // Given
        let id = "test-id-123"
        let title = "Test Reminder"
        
        // When - Initialize with nil dueDate and notes
        let reminder = ReminderItem(id: id, title: title, dueDate: nil, notes: nil, isCompleted: false)
        
        // Then
        XCTAssertEqual(reminder.id, id)
        XCTAssertEqual(reminder.title, title)
        XCTAssertNil(reminder.dueDate)
        XCTAssertNil(reminder.notes)
        XCTAssertFalse(reminder.isCompleted)
    }
    
    func testInitializationFromEKReminder() {
        // Given
        let eventStore = EKEventStore()
        let ekReminder = EKReminder(eventStore: eventStore)
        
        ekReminder.title = "Test EK Reminder"
        
        // Set due date
        let dueDate = Date()
        ekReminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        
        ekReminder.notes = "Test EK notes"
        ekReminder.isCompleted = true
        
        // We need to set a calendar for the reminder to have a valid calendarItemIdentifier
        if let calendar = eventStore.defaultCalendarForNewReminders() {
            ekReminder.calendar = calendar
        }
        
        // When
        let reminder = ReminderItem(from: ekReminder)
        
        // Then
        XCTAssertEqual(reminder.id, ekReminder.calendarItemIdentifier)
        XCTAssertEqual(reminder.title, ekReminder.title)
        XCTAssertEqual(reminder.notes, ekReminder.notes)
        XCTAssertEqual(reminder.isCompleted, ekReminder.isCompleted)
        
        // Check dueDate - should approximately match ekReminder.dueDateComponents
        // but won't be exactly equal because of how EKReminder stores dates
        if let reminderDueDate = reminder.dueDate, let ekDueComponents = ekReminder.dueDateComponents {
            let calendar = Calendar.current
            XCTAssertEqual(calendar.component(.year, from: reminderDueDate), ekDueComponents.year)
            XCTAssertEqual(calendar.component(.month, from: reminderDueDate), ekDueComponents.month)
            XCTAssertEqual(calendar.component(.day, from: reminderDueDate), ekDueComponents.day)
        } else {
            XCTFail("Due date should not be nil")
        }
    }
    
    func testInitializationFromEKReminderWithNilFields() {
        // Given
        let eventStore = EKEventStore()
        let ekReminder = EKReminder(eventStore: eventStore)
        
        ekReminder.title = "Test EK Reminder"
        ekReminder.dueDateComponents = nil
        ekReminder.notes = nil
        ekReminder.isCompleted = false
        
        // We need to set a calendar for the reminder to have a valid calendarItemIdentifier
        if let calendar = eventStore.defaultCalendarForNewReminders() {
            ekReminder.calendar = calendar
        }
        
        // When
        let reminder = ReminderItem(from: ekReminder)
        
        // Then
        XCTAssertEqual(reminder.id, ekReminder.calendarItemIdentifier)
        XCTAssertEqual(reminder.title, ekReminder.title)
        XCTAssertNil(reminder.notes)
        XCTAssertNil(reminder.dueDate)
        XCTAssertFalse(reminder.isCompleted)
    }
    
    func testRemindersWithEqualPropertiesAreEqual() {
        // Given
        let now = Date()
        
        let reminder1 = ReminderItem(id: "test-id", title: "Test", dueDate: now, notes: "Notes", isCompleted: true)
        let reminder2 = ReminderItem(id: "test-id", title: "Test", dueDate: now, notes: "Notes", isCompleted: true)
        
        // Then
        XCTAssertEqual(reminder1.id, reminder2.id)
        XCTAssertEqual(reminder1.title, reminder2.title)
        XCTAssertEqual(reminder1.dueDate, reminder2.dueDate)
        XCTAssertEqual(reminder1.notes, reminder2.notes)
        XCTAssertEqual(reminder1.isCompleted, reminder2.isCompleted)
    }
}
