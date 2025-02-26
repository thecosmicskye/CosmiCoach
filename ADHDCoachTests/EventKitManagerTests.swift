import XCTest
import EventKit
@testable import ADHDCoach

final class EventKitManagerTests: XCTestCase {
    
    var eventKitManager: EventKitManagerMock!
    
    override func setUp() async throws {
        try await super.setUp()
        eventKitManager = EventKitManagerMock()
    }
    
    override func tearDown() async throws {
        eventKitManager = nil
        try await super.tearDown()
    }
    
    func testCheckPermissions() async {
        // When
        eventKitManager.checkPermissions()
        
        // Then - This just tests the method exists and doesn't crash
        XCTAssertTrue(true)
    }
    
    func testFetchUpcomingEvents() async {
        // Given
        let event1 = CalendarEvent(id: "event-1", title: "Test Event 1", startDate: Date(), endDate: Date().addingTimeInterval(3600), notes: "Notes 1")
        let event2 = CalendarEvent(id: "event-2", title: "Test Event 2", startDate: Date(), endDate: Date().addingTimeInterval(7200), notes: "Notes 2")
        
        eventKitManager.mockCalendarEvents = [event1, event2]
        
        // When
        let events = eventKitManager.fetchUpcomingEvents(days: 7)
        
        // Then
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].id, "event-1")
        XCTAssertEqual(events[1].id, "event-2")
    }
    
    func testAddCalendarEvent() async {
        // Given
        let title = "New Test Event"
        let startDate = Date()
        let endDate = Date().addingTimeInterval(3600)
        let notes = "Test notes"
        
        // When
        let success = eventKitManager.addCalendarEvent(title: title, startDate: startDate, endDate: endDate, notes: notes)
        
        // Then
        XCTAssertTrue(success)
        XCTAssertEqual(eventKitManager.mockCalendarEvents.count, 1)
        
        let addedEvent = eventKitManager.mockCalendarEvents[0]
        XCTAssertEqual(addedEvent.title, title)
        XCTAssertEqual(addedEvent.startDate, startDate)
        XCTAssertEqual(addedEvent.endDate, endDate)
        XCTAssertEqual(addedEvent.notes, notes)
    }
    
    func testUpdateCalendarEvent() async {
        // Given
        let event = CalendarEvent(id: "event-id", title: "Original Title", startDate: Date(), endDate: Date().addingTimeInterval(3600), notes: "Original notes")
        eventKitManager.mockCalendarEvents = [event]
        
        let newTitle = "Updated Title"
        let newStartDate = Date().addingTimeInterval(1800)
        let newEndDate = Date().addingTimeInterval(5400)
        let newNotes = "Updated notes"
        
        // When
        let success = eventKitManager.updateCalendarEvent(id: "event-id", title: newTitle, startDate: newStartDate, endDate: newEndDate, notes: newNotes)
        
        // Then
        XCTAssertTrue(success)
        XCTAssertEqual(eventKitManager.mockCalendarEvents.count, 1)
        
        let updatedEvent = eventKitManager.mockCalendarEvents[0]
        XCTAssertEqual(updatedEvent.title, newTitle)
        XCTAssertEqual(updatedEvent.startDate, newStartDate)
        XCTAssertEqual(updatedEvent.endDate, newEndDate)
        XCTAssertEqual(updatedEvent.notes, newNotes)
    }
    
    func testDeleteCalendarEvent() async {
        // Given
        let event1 = CalendarEvent(id: "event-1", title: "Event 1", startDate: Date(), endDate: Date().addingTimeInterval(3600), notes: nil)
        let event2 = CalendarEvent(id: "event-2", title: "Event 2", startDate: Date(), endDate: Date().addingTimeInterval(3600), notes: nil)
        
        eventKitManager.mockCalendarEvents = [event1, event2]
        
        // When
        let success = eventKitManager.deleteCalendarEvent(id: "event-1")
        
        // Then
        XCTAssertTrue(success)
        XCTAssertEqual(eventKitManager.mockCalendarEvents.count, 1)
        XCTAssertEqual(eventKitManager.mockCalendarEvents[0].id, "event-2")
    }
    
    func testFetchReminders() async {
        // Given
        let reminder1 = ReminderItem(id: "reminder-1", title: "Test Reminder 1", dueDate: Date(), notes: "Notes 1", isCompleted: false)
        let reminder2 = ReminderItem(id: "reminder-2", title: "Test Reminder 2", dueDate: Date().addingTimeInterval(86400), notes: "Notes 2", isCompleted: true)
        
        eventKitManager.mockReminders = [reminder1, reminder2]
        
        // When - use the async version now
        let reminders = await eventKitManager.fetchReminders()
        
        // Then
        XCTAssertEqual(reminders.count, 2)
        XCTAssertEqual(reminders[0].id, "reminder-1")
        XCTAssertEqual(reminders[1].id, "reminder-2")
    }
    
    func testAddReminder() async {
        // Given
        let title = "New Test Reminder"
        let dueDate = Date().addingTimeInterval(86400)
        let notes = "Test reminder notes"
        
        // When - use async version
        let success = await eventKitManager.addReminderAsync(title: title, dueDate: dueDate, notes: notes)
        
        // Then
        XCTAssertTrue(success)
        XCTAssertEqual(eventKitManager.mockReminders.count, 1)
        
        let addedReminder = eventKitManager.mockReminders[0]
        XCTAssertEqual(addedReminder.title, title)
        XCTAssertEqual(addedReminder.dueDate, dueDate)
        XCTAssertEqual(addedReminder.notes, notes)
        XCTAssertFalse(addedReminder.isCompleted)
    }
    
    func testUpdateReminder() async {
        // Given
        let reminder = ReminderItem(id: "reminder-id", title: "Original Title", dueDate: Date(), notes: "Original notes", isCompleted: false)
        eventKitManager.mockReminders = [reminder]
        
        let newTitle = "Updated Title"
        let newDueDate = Date().addingTimeInterval(172800) // 2 days later
        let newNotes = "Updated notes"
        let newCompletionStatus = true
        
        // When - use the async version now
        let success = await eventKitManager.updateReminder(id: "reminder-id", title: newTitle, dueDate: newDueDate, notes: newNotes, isCompleted: newCompletionStatus)
        
        // Then
        XCTAssertTrue(success)
        XCTAssertEqual(eventKitManager.mockReminders.count, 1)
        
        let updatedReminder = eventKitManager.mockReminders[0]
        XCTAssertEqual(updatedReminder.title, newTitle)
        XCTAssertEqual(updatedReminder.dueDate, newDueDate)
        XCTAssertEqual(updatedReminder.notes, newNotes)
        XCTAssertEqual(updatedReminder.isCompleted, newCompletionStatus)
    }
    
    func testDeleteReminder() async {
        // Given
        let reminder1 = ReminderItem(id: "reminder-1", title: "Reminder 1", dueDate: Date(), notes: nil, isCompleted: false)
        let reminder2 = ReminderItem(id: "reminder-2", title: "Reminder 2", dueDate: Date().addingTimeInterval(86400), notes: nil, isCompleted: false)
        
        eventKitManager.mockReminders = [reminder1, reminder2]
        
        // When - use the async version now
        let success = await eventKitManager.deleteReminder(id: "reminder-1")
        
        // Then
        XCTAssertTrue(success)
        XCTAssertEqual(eventKitManager.mockReminders.count, 1)
        XCTAssertEqual(eventKitManager.mockReminders[0].id, "reminder-2")
    }
}

// MARK: - Mock EventKitManager for Testing

class EventKitManagerMock: EventKitManager {
    var mockCalendarEvents: [CalendarEvent] = []
    var mockReminders: [ReminderItem] = []
    
    override func fetchUpcomingEvents(days: Int) -> [CalendarEvent] {
        return mockCalendarEvents
    }
    
    override func addCalendarEvent(title: String, startDate: Date, endDate: Date, notes: String? = nil) -> Bool {
        let newEvent = CalendarEvent(id: "mock-event-\(UUID().uuidString)", title: title, startDate: startDate, endDate: endDate, notes: notes)
        mockCalendarEvents.append(newEvent)
        return true
    }
    
    override func updateCalendarEvent(id: String, title: String? = nil, startDate: Date? = nil, endDate: Date? = nil, notes: String? = nil) -> Bool {
        if let index = mockCalendarEvents.firstIndex(where: { $0.id == id }) {
            var event = mockCalendarEvents[index]
            
            if let title = title {
                let updatedEvent = CalendarEvent(
                    id: event.id,
                    title: title,
                    startDate: startDate ?? event.startDate,
                    endDate: endDate ?? event.endDate,
                    notes: notes ?? event.notes
                )
                mockCalendarEvents[index] = updatedEvent
            }
            return true
        }
        return false
    }
    
    override func deleteCalendarEvent(id: String) -> Bool {
        if let index = mockCalendarEvents.firstIndex(where: { $0.id == id }) {
            mockCalendarEvents.remove(at: index)
            return true
        }
        return false
    }
    
    override func fetchReminders() async -> [ReminderItem] {
        return mockReminders
    }
    
    // Non-async version for testing
    override func fetchReminders() -> [ReminderItem] {
        return mockReminders
    }
    
    override func addReminder(title: String, dueDate: Date? = nil, notes: String? = nil) -> Bool {
        let newReminder = ReminderItem(id: "mock-reminder-\(UUID().uuidString)", title: title, dueDate: dueDate, notes: notes, isCompleted: false)
        mockReminders.append(newReminder)
        return true
    }
    
    override func addReminderAsync(title: String, dueDate: Date? = nil, notes: String? = nil) async -> Bool {
        let newReminder = ReminderItem(id: "mock-reminder-\(UUID().uuidString)", title: title, dueDate: dueDate, notes: notes, isCompleted: false)
        mockReminders.append(newReminder)
        return true
    }
    
    override func updateReminder(id: String, title: String? = nil, dueDate: Date? = nil, notes: String? = nil, isCompleted: Bool? = nil) async -> Bool {
        if let index = mockReminders.firstIndex(where: { $0.id == id }) {
            var reminder = mockReminders[index]
            
            let updatedReminder = ReminderItem(
                id: reminder.id,
                title: title ?? reminder.title,
                dueDate: dueDate ?? reminder.dueDate,
                notes: notes ?? reminder.notes,
                isCompleted: isCompleted ?? reminder.isCompleted
            )
            mockReminders[index] = updatedReminder
            return true
        }
        return false
    }
    
    // Non-async version for testing
    override func updateReminder(id: String, title: String? = nil, dueDate: Date? = nil, notes: String? = nil, isCompleted: Bool? = nil) -> Bool {
        if let index = mockReminders.firstIndex(where: { $0.id == id }) {
            var reminder = mockReminders[index]
            
            let updatedReminder = ReminderItem(
                id: reminder.id,
                title: title ?? reminder.title,
                dueDate: dueDate ?? reminder.dueDate,
                notes: notes ?? reminder.notes,
                isCompleted: isCompleted ?? reminder.isCompleted
            )
            mockReminders[index] = updatedReminder
            return true
        }
        return false
    }
    
    override func deleteReminder(id: String) async -> Bool {
        if let index = mockReminders.firstIndex(where: { $0.id == id }) {
            mockReminders.remove(at: index)
            return true
        }
        return false
    }
    
    // Non-async version for testing
    override func deleteReminder(id: String) -> Bool {
        if let index = mockReminders.firstIndex(where: { $0.id == id }) {
            mockReminders.remove(at: index)
            return true
        }
        return false
    }
}
