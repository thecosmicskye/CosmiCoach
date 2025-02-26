import XCTest
@testable import ADHDCoach

final class ChatManagerTests: XCTestCase {
    var chatManager: ChatManager!
    var mockMemoryManager: MemoryManagerMock!
    var mockEventKitManager: EventKitManagerForChatTests!
    
    override func setUp() async throws {
        try await super.setUp()
        
        await MainActor.run {
            chatManager = ChatManager()
            mockMemoryManager = MemoryManagerMock()
            mockEventKitManager = EventKitManagerForChatTests()
            chatManager.setMemoryManager(mockMemoryManager)
            chatManager.setEventKitManager(mockEventKitManager)
        }
    }
    
    override func tearDown() async throws {
        await MainActor.run {
            chatManager = nil
            mockMemoryManager = nil
            mockEventKitManager = nil
            
            // Clean up UserDefaults
            UserDefaults.standard.removeObject(forKey: "chat_messages")
            UserDefaults.standard.removeObject(forKey: "streaming_message_id")
            UserDefaults.standard.removeObject(forKey: "last_streaming_content")
            UserDefaults.standard.removeObject(forKey: "chat_processing_state")
        }
        
        await super.tearDown()
    }
    
    func testAddUserMessage() async throws {
        // Given
        let messageContent = "Test user message"
        
        // When
        await MainActor.run {
            chatManager.addUserMessage(content: messageContent)
        }
        
        // Then
        let messagesCount = await MainActor.run {
            return chatManager.messages.count
        }
        
        let lastMessageContent = await MainActor.run {
            return chatManager.messages.last?.content
        }
        
        let isUserMessage = await MainActor.run {
            return chatManager.messages.last?.isUser ?? false
        }
        
        let isComplete = await MainActor.run {
            return chatManager.messages.last?.isComplete ?? false
        }
        
        XCTAssertEqual(messagesCount, 2) // Initial welcome message + new user message
        XCTAssertEqual(lastMessageContent, messageContent)
        XCTAssertTrue(isUserMessage)
        XCTAssertTrue(isComplete)
    }
    
    func testAddAssistantMessage() async throws {
        // Given
        let messageContent = "Test assistant message"
        
        // When
        await MainActor.run {
            chatManager.addAssistantMessage(content: messageContent)
        }
        
        // Then
        let messagesCount = await MainActor.run {
            return chatManager.messages.count
        }
        
        let lastMessageContent = await MainActor.run {
            return chatManager.messages.last?.content
        }
        
        let isUserMessage = await MainActor.run {
            return chatManager.messages.last?.isUser ?? true
        }
        
        let isComplete = await MainActor.run {
            return chatManager.messages.last?.isComplete ?? false
        }
        
        XCTAssertEqual(messagesCount, 2) // Initial welcome message + new assistant message
        XCTAssertEqual(lastMessageContent, messageContent)
        XCTAssertFalse(isUserMessage)
        XCTAssertTrue(isComplete)
    }
    
    func testStreamingMessageFlow() async throws {
        // Given/When - Start a streaming message
        await MainActor.run {
            chatManager.addAssistantMessage(content: "", isComplete: false)
        }
        
        // Then - We should have a streaming message
        let streamingId = await MainActor.run {
            return chatManager.currentStreamingMessageId
        }
        
        let initialContent = await MainActor.run {
            return chatManager.messages.last?.content
        }
        
        let initialComplete = await MainActor.run {
            return chatManager.messages.last?.isComplete ?? true
        }
        
        XCTAssertNotNil(streamingId)
        XCTAssertEqual(initialContent, "")
        XCTAssertFalse(initialComplete)
        
        // When - Update the streaming message
        let update1 = "Hello"
        await MainActor.run {
            chatManager.updateStreamingMessage(content: update1)
        }
        
        // Then - The message should be updated
        let updatedContent1 = await MainActor.run {
            return chatManager.messages.last?.content
        }
        
        let updatedComplete1 = await MainActor.run {
            return chatManager.messages.last?.isComplete ?? true
        }
        
        XCTAssertEqual(updatedContent1, update1)
        XCTAssertFalse(updatedComplete1)
        
        // When - Update again
        let update2 = "Hello, user!"
        await MainActor.run {
            chatManager.updateStreamingMessage(content: update2)
        }
        
        // Then - The message should be updated again
        let updatedContent2 = await MainActor.run {
            return chatManager.messages.last?.content
        }
        
        let updatedComplete2 = await MainActor.run {
            return chatManager.messages.last?.isComplete ?? true
        }
        
        XCTAssertEqual(updatedContent2, update2)
        XCTAssertFalse(updatedComplete2)
        
        // When - Finalize the message
        await MainActor.run {
            chatManager.finalizeStreamingMessage()
        }
        
        // Then - The message should be complete
        let finalStreamingId = await MainActor.run {
            return chatManager.currentStreamingMessageId
        }
        
        let finalContent = await MainActor.run {
            return chatManager.messages.last?.content
        }
        
        let finalComplete = await MainActor.run {
            return chatManager.messages.last?.isComplete ?? false
        }
        
        XCTAssertNil(finalStreamingId)
        XCTAssertEqual(finalContent, update2)
        XCTAssertTrue(finalComplete)
    }
    
    func testSaveAndLoadMessages() async throws {
        // Given - Add some messages
        let userMessage = "User test message"
        let assistantMessage = "Assistant test message"
        
        await MainActor.run {
            chatManager.addUserMessage(content: userMessage)
            chatManager.addAssistantMessage(content: assistantMessage)
        }
        
        // When - Create a new chat manager to load from UserDefaults
        let newChatManager = await MainActor.run {
            return ChatManager()
        }
        
        // Then - The new manager should have the same messages
        let messagesCount = await MainActor.run {
            return newChatManager.messages.count
        }
        
        let secondMessageContent = await MainActor.run {
            return newChatManager.messages[1].content
        }
        
        let thirdMessageContent = await MainActor.run {
            return newChatManager.messages[2].content
        }
        
        XCTAssertEqual(messagesCount, 3) // Welcome + our 2 added messages
        XCTAssertEqual(secondMessageContent, userMessage)
        XCTAssertEqual(thirdMessageContent, assistantMessage)
    }
    
    func testResetIncompleteMessages() async throws {
        // Given - Add a streaming message that won't be completed
        await MainActor.run {
            chatManager.addAssistantMessage(content: "Streaming message", isComplete: false)
        }
        
        // When - Create a new chat manager which will reset incomplete messages
        let newChatManager = await MainActor.run {
            return ChatManager()
        }
        
        // Then - The streaming message should be marked as interrupted
        let messagesCount = await MainActor.run {
            return newChatManager.messages.count
        }
        
        let isComplete = await MainActor.run {
            return newChatManager.messages[1].isComplete
        }
        
        let contentHasSuffix = await MainActor.run {
            return newChatManager.messages[1].content.hasSuffix("[Message was interrupted]")
        }
        
        XCTAssertEqual(messagesCount, 2) // Welcome + our streaming message
        XCTAssertTrue(isComplete)
        XCTAssertTrue(contentHasSuffix)
    }
}

// MARK: - Mock Classes

class MemoryManagerMock: MemoryManager {
    var memoryContentString = "Mock memory content"
    var diffApplicationCalled = false
    var latestDiff: String?
    
    override func readMemory() async -> String {
        return memoryContentString
    }
    
    override func applyDiff(diff: String) async -> Bool {
        diffApplicationCalled = true
        latestDiff = diff
        return true
    }
}

class EventKitManagerForChatTests: EventKitManager {
    var calendarEvents: [CalendarEvent] = []
    var reminders: [ReminderItem] = []
    
    var calendarAddCalled = false
    var calendarModifyCalled = false
    var calendarDeleteCalled = false
    var reminderAddCalled = false
    var reminderModifyCalled = false
    var reminderDeleteCalled = false
    
    override func fetchUpcomingEvents(days: Int) -> [CalendarEvent] {
        return calendarEvents
    }
    
    override func fetchReminders() -> [ReminderItem] {
        return reminders
    }
    
    override func addCalendarEvent(title: String, startDate: Date, endDate: Date, notes: String? = nil) -> Bool {
        calendarAddCalled = true
        let event = CalendarEvent(id: "mock-event-\(UUID().uuidString)", title: title, startDate: startDate, endDate: endDate, notes: notes)
        calendarEvents.append(event)
        return true
    }
    
    override func updateCalendarEvent(id: String, title: String? = nil, startDate: Date? = nil, endDate: Date? = nil, notes: String? = nil) -> Bool {
        calendarModifyCalled = true
        return true
    }
    
    override func deleteCalendarEvent(id: String) -> Bool {
        calendarDeleteCalled = true
        return true
    }
    
    override func addReminder(title: String, dueDate: Date? = nil, notes: String? = nil) -> Bool {
        reminderAddCalled = true
        let reminder = ReminderItem(id: "mock-reminder-\(UUID().uuidString)", title: title, dueDate: dueDate, notes: notes, isCompleted: false)
        reminders.append(reminder)
        return true
    }
    
    override func updateReminder(id: String, title: String? = nil, dueDate: Date? = nil, notes: String? = nil, isCompleted: Bool? = nil) -> Bool {
        reminderModifyCalled = true
        return true
    }
    
    override func deleteReminder(id: String) -> Bool {
        reminderDeleteCalled = true
        return true
    }
}
