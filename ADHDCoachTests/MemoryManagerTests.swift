import XCTest
@testable import ADHDCoach

final class MemoryManagerTests: XCTestCase {
    var memoryManager: MemoryManager!
    let testFileManager = FileManager.default
    var testFileURL: URL!
    
    override func setUp() {
        super.setUp()
        memoryManager = MemoryManager()
        
        // Create a test-specific URL for the memory file
        do {
            let documentsDirectory = try testFileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            testFileURL = documentsDirectory.appendingPathComponent("test_memory.md")
            
            // Ensure the test file doesn't exist from a previous run
            if testFileManager.fileExists(atPath: testFileURL.path) {
                try testFileManager.removeItem(at: testFileURL)
            }
        } catch {
            XCTFail("Failed to set up test environment: \(error.localizedDescription)")
        }
    }
    
    override func tearDown() {
        memoryManager = nil
        
        // Clean up the test file
        do {
            if testFileManager.fileExists(atPath: testFileURL.path) {
                try testFileManager.removeItem(at: testFileURL)
            }
        } catch {
            print("Error cleaning up test file: \(error.localizedDescription)")
        }
        
        super.tearDown()
    }
    
    func testInitialMemoryCreation() async {
        // When
        await memoryManager.loadMemory()
        
        // Then
        XCTAssertFalse(memoryManager.memoryContent.isEmpty)
        XCTAssertTrue(memoryManager.memoryContent.contains("# User Memory File"))
        XCTAssertTrue(memoryManager.memoryContent.contains("## Basic Information"))
    }
    
    func testReadMemory() async {
        // Given
        let initialContent = "Test memory content"
        try? initialContent.write(to: testFileURL, atomically: true, encoding: .utf8)
        
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
        
        // When
        let content = await testManager.readMemory()
        
        // Then
        XCTAssertEqual(content, initialContent)
    }
    
    func testUpdateMemory() async {
        // Given
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
        let newContent = "Updated memory content"
        
        // When
        let success = await testManager.updateMemory(newContent: newContent)
        
        // Then
        XCTAssertTrue(success)
        
        // Verify file was updated
        let fileContent = try? String(contentsOf: testFileURL, encoding: .utf8)
        XCTAssertEqual(fileContent, newContent)
        
        // Verify in-memory content was updated
        XCTAssertEqual(testManager.memoryContent, newContent)
    }
    
    func testApplyDiff_AdditionsOnly() async {
        // Given
        let initialContent = """
        # User Memory File
        
        ## Basic Information
        User name: Test
        """
        
        class TestMemoryManager: MemoryManager {
            var initialContent: String
            let testURL: URL
            
            init(initialContent: String, testURL: URL) {
                self.initialContent = initialContent
                self.testURL = testURL
                super.init()
                
                // Set initial memory content
                Task {
                    await updateMemory(newContent: initialContent)
                }
            }
            
            override func getMemoryFileURL() -> URL? {
                return testURL
            }
            
            override func readMemory() async -> String {
                return initialContent
            }
            
            override func updateMemory(newContent: String) async -> Bool {
                self.initialContent = newContent
                return true
            }
        }
        
        let testManager = TestMemoryManager(initialContent: initialContent, testURL: testFileURL)
        
        // When
        let diff = """
        +User age: 30
        +User location: Test City
        """
        
        let success = await testManager.applyDiff(diff: diff)
        
        // Then
        XCTAssertTrue(success)
        XCTAssertTrue(testManager.initialContent.contains("User age: 30"))
        XCTAssertTrue(testManager.initialContent.contains("User location: Test City"))
    }
    
    func testApplyDiff_RemovalsOnly() async {
        // Given
        let initialContent = """
        # User Memory File
        
        ## Basic Information
        User name: Test
        User age: 30
        User location: Test City
        """
        
        class TestMemoryManager: MemoryManager {
            var initialContent: String
            let testURL: URL
            
            init(initialContent: String, testURL: URL) {
                self.initialContent = initialContent
                self.testURL = testURL
                super.init()
                
                // Set initial memory content
                Task {
                    await updateMemory(newContent: initialContent)
                }
            }
            
            override func getMemoryFileURL() -> URL? {
                return testURL
            }
            
            override func readMemory() async -> String {
                return initialContent
            }
            
            override func updateMemory(newContent: String) async -> Bool {
                self.initialContent = newContent
                return true
            }
        }
        
        let testManager = TestMemoryManager(initialContent: initialContent, testURL: testFileURL)
        
        // When
        let diff = """
        -User age: 30
        """
        
        let success = await testManager.applyDiff(diff: diff)
        
        // Then
        XCTAssertTrue(success)
        XCTAssertFalse(testManager.initialContent.contains("User age: 30"))
        XCTAssertTrue(testManager.initialContent.contains("User name: Test"))
        XCTAssertTrue(testManager.initialContent.contains("User location: Test City"))
    }
    
    func testApplyDiff_MixedAdditionsAndRemovals() async {
        // Given
        let initialContent = """
        # User Memory File
        
        ## Basic Information
        User name: Test
        User age: 30
        """
        
        class TestMemoryManager: MemoryManager {
            var initialContent: String
            let testURL: URL
            
            init(initialContent: String, testURL: URL) {
                self.initialContent = initialContent
                self.testURL = testURL
                super.init()
                
                // Set initial memory content
                Task {
                    await updateMemory(newContent: initialContent)
                }
            }
            
            override func getMemoryFileURL() -> URL? {
                return testURL
            }
            
            override func readMemory() async -> String {
                return initialContent
            }
            
            override func updateMemory(newContent: String) async -> Bool {
                self.initialContent = newContent
                return true
            }
        }
        
        let testManager = TestMemoryManager(initialContent: initialContent, testURL: testFileURL)
        
        // When
        let diff = """
        -User age: 30
        +User age: 31
        +User location: Test City
        """
        
        let success = await testManager.applyDiff(diff: diff)
        
        // Then
        XCTAssertTrue(success)
        XCTAssertFalse(testManager.initialContent.contains("User age: 30"))
        XCTAssertTrue(testManager.initialContent.contains("User age: 31"))
        XCTAssertTrue(testManager.initialContent.contains("User location: Test City"))
    }
    
    func testApplyDiff_EmptyResult() async {
        // Given
        let initialContent = """
        # User Memory File
        
        ## Basic Information
        User name: Test
        """
        
        class TestMemoryManager: MemoryManager {
            var initialContent: String
            let testURL: URL
            
            init(initialContent: String, testURL: URL) {
                self.initialContent = initialContent
                self.testURL = testURL
                super.init()
                
                // Set initial memory content
                Task {
                    await updateMemory(newContent: initialContent)
                }
            }
            
            override func getMemoryFileURL() -> URL? {
                return testURL
            }
            
            override func readMemory() async -> String {
                return initialContent
            }
            
            override func updateMemory(newContent: String) async -> Bool {
                self.initialContent = newContent
                return true
            }
        }
        
        let testManager = TestMemoryManager(initialContent: initialContent, testURL: testFileURL)
        
        // When - Try to remove everything
        let diff = "-# User Memory File\n-\n-## Basic Information\n-User name: Test"
        
        let success = await testManager.applyDiff(diff: diff)
        
        // Then - Should fail because it would result in empty content
        XCTAssertFalse(success)
        XCTAssertTrue(testManager.initialContent.contains("User name: Test"))
    }
}
