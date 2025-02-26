import XCTest
@testable import ADHDCoach

final class ChatMessageTests: XCTestCase {
    
    func testInitialization() {
        // Given
        let id = UUID()
        let content = "Test message"
        let timestamp = Date()
        let isUser = true
        
        // When
        let message = ChatMessage(id: id, content: content, timestamp: timestamp, isUser: isUser)
        
        // Then
        XCTAssertEqual(message.id, id)
        XCTAssertEqual(message.content, content)
        XCTAssertEqual(message.timestamp, timestamp)
        XCTAssertEqual(message.isUser, isUser)
        XCTAssertTrue(message.isComplete)
    }
    
    func testInitializationWithDefaults() {
        // When
        let message = ChatMessage(content: "Test message", isUser: true)
        
        // Then
        XCTAssertNotNil(message.id)
        XCTAssertEqual(message.content, "Test message")
        XCTAssertEqual(message.isUser, true)
        XCTAssertTrue(message.isComplete)
        
        // Timestamp should be close to now
        let now = Date()
        let differenceInSeconds = message.timestamp.timeIntervalSince(now)
        XCTAssertTrue(abs(differenceInSeconds) < 1.0)
    }
    
    func testInitializationWithIncompleteFlag() {
        // When
        let message = ChatMessage(content: "Test message", isUser: false, isComplete: false)
        
        // Then
        XCTAssertFalse(message.isComplete)
    }
    
    func testFormattedTimestamp() {
        // Given
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = dateFormatter.date(from: "2023-05-15 14:30:00")!
        
        // When
        let message = ChatMessage(content: "Test message", timestamp: timestamp, isUser: true)
        
        // Then
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let expectedFormatted = formatter.string(from: timestamp)
        
        XCTAssertEqual(message.formattedTimestamp, expectedFormatted)
    }
    
    func testEncodingAndDecoding() throws {
        // Given
        let id = UUID()
        let content = "Test message"
        let timestamp = Date()
        let isUser = true
        let isComplete = false
        
        let originalMessage = ChatMessage(id: id, content: content, timestamp: timestamp, isUser: isUser, isComplete: isComplete)
        
        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(originalMessage)
        
        let decoder = JSONDecoder()
        let decodedMessage = try decoder.decode(ChatMessage.self, from: data)
        
        // Then
        XCTAssertEqual(decodedMessage.id, originalMessage.id)
        XCTAssertEqual(decodedMessage.content, originalMessage.content)
        XCTAssertEqual(decodedMessage.timestamp.timeIntervalSince1970, originalMessage.timestamp.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(decodedMessage.isUser, originalMessage.isUser)
        XCTAssertEqual(decodedMessage.isComplete, originalMessage.isComplete)
    }
    
    func testContentModification() {
        // Given
        var message = ChatMessage(content: "Original content", isUser: false)
        
        // When
        message.content = "Updated content"
        
        // Then
        XCTAssertEqual(message.content, "Updated content")
    }
    
    func testCompletionStatusModification() {
        // Given
        var message = ChatMessage(content: "Test message", isUser: false, isComplete: false)
        
        // When
        message.isComplete = true
        
        // Then
        XCTAssertTrue(message.isComplete)
    }
}
