import XCTest
@testable import ADHDCoach

final class MemoryManagerTests: XCTestCase {
    var memoryManager: MemoryManager!
    let testFileManager = FileManager.default
    var testFileURL: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        memoryManager = MemoryManager()
        
        // Create a test-specific URL for the memory file
        do {
            let documentsDirectory = try testFileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            testFileURL = documentsDirectory.appendingPathComponent("test_memories.json")
            
            // Ensure the test file doesn't exist from a previous run
            if testFileManager.fileExists(atPath: testFileURL.path) {
                try testFileManager.removeItem(at: testFileURL)
            }
        } catch {
            XCTFail("Failed to set up test environment: \(error.localizedDescription)")
        }
    }
    
    override func tearDown() async throws {
        memoryManager = nil
        
        // Clean up the test file
        do {
            if testFileManager.fileExists(atPath: testFileURL.path) {
                try testFileManager.removeItem(at: testFileURL)
            }
        } catch {
            print("Error cleaning up test file: \(error.localizedDescription)")
        }
        
        try await super.tearDown()
    }
    
    func testAddMemory() async throws {
        // Create a custom memory manager that uses our test file
        class TestMemoryManager: MemoryManager {
            let testURL: URL
            
            init(testURL: URL) {
                self.testURL = testURL
                super.init()
            }
            
            override func getMemoryFileURL() -> URL? {
                return testURL
            }
        }
        
        let testManager = TestMemoryManager(testURL: testFileURL)
        await testManager.loadMemories()
        
        // Get initial count
        let initialCount = await MainActor.run { testManager.memories.count }
        
        // Add a memory
        try await testManager.addMemory(
            content: "Test memory content",
            category: .notes,
            importance: 3
        )
        
        // Verify it was added
        let newCount = await MainActor.run { testManager.memories.count }
        XCTAssertEqual(newCount, initialCount + 1)
        
        // Verify content is correct
        let memories = await MainActor.run { testManager.memories }
        let addedMemory = memories.last
        XCTAssertEqual(addedMemory?.content, "Test memory content")
        XCTAssertEqual(addedMemory?.category, .notes)
        XCTAssertEqual(addedMemory?.importance, 3)
    }
    
    func testUpdateMemory() async throws {
        // Create a custom memory manager that uses our test file
        class TestMemoryManager: MemoryManager {
            let testURL: URL
            
            init(testURL: URL) {
                self.testURL = testURL
                super.init()
            }
            
            override func getMemoryFileURL() -> URL? {
                return testURL
            }
        }
        
        let testManager = TestMemoryManager(testURL: testFileURL)
        await testManager.loadMemories()
        
        // Add a memory first
        try await testManager.addMemory(
            content: "Original content",
            category: .notes
        )
        
        // Get the ID of the added memory
        let memories = await MainActor.run { testManager.memories }
        guard let memoryId = memories.last?.id else {
            XCTFail("Could not get memory ID")
            return
        }
        
        // Update the memory
        try await testManager.updateMemory(
            id: memoryId,
            newContent: "Updated content",
            newCategory: .preferences,
            newImportance: 4
        )
        
        // Verify it was updated correctly
        let updatedMemories = await MainActor.run { testManager.memories }
        let updatedMemory = updatedMemories.first(where: { $0.id == memoryId })
        
        XCTAssertEqual(updatedMemory?.content, "Updated content")
        XCTAssertEqual(updatedMemory?.category, .preferences)
        XCTAssertEqual(updatedMemory?.importance, 4)
    }
    
    func testDeleteMemory() async throws {
        // Create a custom memory manager that uses our test file
        class TestMemoryManager: MemoryManager {
            let testURL: URL
            
            init(testURL: URL) {
                self.testURL = testURL
                super.init()
            }
            
            override func getMemoryFileURL() -> URL? {
                return testURL
            }
        }
        
        let testManager = TestMemoryManager(testURL: testFileURL)
        await testManager.loadMemories()
        
        // Add a memory first
        try await testManager.addMemory(
            content: "Memory to delete",
            category: .notes
        )
        
        // Get the ID of the added memory
        let memories = await MainActor.run { testManager.memories }
        guard let memoryId = memories.last?.id else {
            XCTFail("Could not get memory ID")
            return
        }
        
        // Get initial count
        let initialCount = await MainActor.run { testManager.memories.count }
        
        // Delete the memory
        try await testManager.deleteMemory(id: memoryId)
        
        // Verify it was deleted
        let newCount = await MainActor.run { testManager.memories.count }
        XCTAssertEqual(newCount, initialCount - 1)
        
        // Verify it's no longer in the list
        let updatedMemories = await MainActor.run { testManager.memories }
        XCTAssertFalse(updatedMemories.contains(where: { $0.id == memoryId }))
    }
    
    func testFormatMemoriesForClaude() async throws {
        // Create a custom memory manager that uses our test file
        class TestMemoryManager: MemoryManager {
            let testURL: URL
            
            init(testURL: URL) {
                self.testURL = testURL
                super.init()
            }
            
            override func getMemoryFileURL() -> URL? {
                return testURL
            }
        }
        
        let testManager = TestMemoryManager(testURL: testFileURL)
        await testManager.loadMemories()
        
        // Clear existing memories for a clean slate
        let memories = await MainActor.run { testManager.memories }
        for memory in memories {
            try await testManager.deleteMemory(id: memory.id)
        }
        
        // Add test memories in different categories
        try await testManager.addMemory(
            content: "User takes medication at 9am",
            category: .medications,
            importance: 5
        )
        
        try await testManager.addMemory(
            content: "User prefers direct communication",
            category: .preferences,
            importance: 4
        )
        
        try await testManager.addMemory(
            content: "User struggles with task initiation",
            category: .patterns,
            importance: 3
        )
        
        // Get formatted memories
        let formatted = testManager.formatMemoriesForClaude()
        
        // Verify format includes categories and content
        XCTAssertTrue(formatted.contains("## Medications"))
        XCTAssertTrue(formatted.contains("## Preferences"))
        XCTAssertTrue(formatted.contains("## Behavior Patterns"))
        
        XCTAssertTrue(formatted.contains("- User takes medication at 9am"))
        XCTAssertTrue(formatted.contains("- User prefers direct communication"))
        XCTAssertTrue(formatted.contains("- User struggles with task initiation"))
    }
    
    func testProcessMemoryInstructions() async throws {
        // Create a custom memory manager that uses our test file
        class TestMemoryManager: MemoryManager {
            let testURL: URL
            
            init(testURL: URL) {
                self.testURL = testURL
                super.init()
            }
            
            override func getMemoryFileURL() -> URL? {
                return testURL
            }
        }
        
        let testManager = TestMemoryManager(testURL: testFileURL)
        await testManager.loadMemories()
        
        // Clear existing memories for a clean slate
        let memories = await MainActor.run { testManager.memories }
        for memory in memories {
            try await testManager.deleteMemory(id: memory.id)
        }
        
        // Test adding memories via instructions
        let instructions = """
        [MEMORY_ADD] User takes 20mg Adderall at 8am | Medications | 5
        [MEMORY_ADD] User prefers short answers | Preferences | 4
        Not a memory instruction
        [MEMORY_ADD] User has a dog named Rex | Personal Information
        """
        
        let initialCount = await MainActor.run { testManager.memories.count }
        let success = await testManager.processMemoryInstructions(instructions: instructions)
        
        // Verify success and count
        XCTAssertTrue(success)
        let newCount = await MainActor.run { testManager.memories.count }
        XCTAssertEqual(newCount, initialCount + 3)
        
        // Verify content
        let updatedMemories = await MainActor.run { testManager.memories }
        XCTAssertTrue(updatedMemories.contains(where: { $0.content == "User takes 20mg Adderall at 8am" && $0.category == .medications && $0.importance == 5 }))
        XCTAssertTrue(updatedMemories.contains(where: { $0.content == "User prefers short answers" && $0.category == .preferences && $0.importance == 4 }))
        XCTAssertTrue(updatedMemories.contains(where: { $0.content == "User has a dog named Rex" && $0.category == .personalInfo }))
    }
    
    func testApplyDiff() async throws {
        // Create a custom memory manager that uses our test file
        class TestMemoryManager: MemoryManager {
            let testURL: URL
            
            init(testURL: URL) {
                self.testURL = testURL
                super.init()
            }
            
            override func getMemoryFileURL() -> URL? {
                return testURL
            }
        }
        
        let testManager = TestMemoryManager(testURL: testFileURL)
        await testManager.loadMemories()
        
        // Clear existing memories for a clean slate
        let memories = await MainActor.run { testManager.memories }
        for memory in memories {
            try await testManager.deleteMemory(id: memory.id)
        }
        
        // Add an initial memory
        try await testManager.addMemory(
            content: "User takes 10mg medication",
            category: .medications
        )
        
        // Apply diff to add and remove memories
        let diff = """
        +User prefers dark mode
        -User takes 10mg medication
        +User takes 20mg medication
        """
        
        let success = await testManager.applyDiff(diff: diff)
        XCTAssertTrue(success)
        
        // Verify the result
        let updatedMemories = await MainActor.run { testManager.memories }
        
        // The original memory should be removed
        XCTAssertFalse(updatedMemories.contains(where: { $0.content == "User takes 10mg medication" }))
        
        // The new memories should be added
        XCTAssertTrue(updatedMemories.contains(where: { $0.content == "User prefers dark mode" }))
        XCTAssertTrue(updatedMemories.contains(where: { $0.content == "User takes 20mg medication" }))
    }
    
    func testLegacyUpdateMemory() async throws {
        // Create a custom memory manager that uses our test file
        class TestMemoryManager: MemoryManager {
            let testURL: URL
            
            init(testURL: URL) {
                self.testURL = testURL
                super.init()
            }
            
            override func getMemoryFileURL() -> URL? {
                return testURL
            }
        }
        
        let testManager = TestMemoryManager(testURL: testFileURL)
        await testManager.loadMemories()
        
        // Clear existing memories for a clean slate
        let memories = await MainActor.run { testManager.memories }
        for memory in memories {
            try await testManager.deleteMemory(id: memory.id)
        }
        
        // Create markdown content to update memories
        let markdownContent = """
        # User Memory File
        
        ## Medications
        - User takes 15mg medication every morning
        
        ## Preferences
        - User prefers dark mode
        - User likes notifications
        """
        
        // Use legacy update method
        let success = await testManager.updateMemory(newContent: markdownContent)
        XCTAssertTrue(success)
        
        // Verify the result
        let updatedMemories = await MainActor.run { testManager.memories }
        
        // Should have created new memory items from the markdown
        XCTAssertEqual(updatedMemories.count, 3)
        XCTAssertTrue(updatedMemories.contains(where: { $0.content == "User takes 15mg medication every morning" && $0.category == .medications }))
        XCTAssertTrue(updatedMemories.contains(where: { $0.content == "User prefers dark mode" && $0.category == .preferences }))
        XCTAssertTrue(updatedMemories.contains(where: { $0.content == "User likes notifications" && $0.category == .preferences }))
    }
}
