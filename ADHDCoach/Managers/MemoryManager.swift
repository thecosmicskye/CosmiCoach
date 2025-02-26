import Foundation
import Combine

class MemoryManager: ObservableObject {
    private let memoryFileName = "claude_memory.md"
    private let fileManager = FileManager.default
    
    @Published var memoryContent: String = ""
    
    init() {
        // Load memory content on initialization
        Task {
            await loadMemory()
        }
    }
    
    func getMemoryFileURL() -> URL? {
        do {
            let documentsDirectory = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            return documentsDirectory.appendingPathComponent(memoryFileName)
        } catch {
            print("Error getting documents directory: \(error.localizedDescription)")
            return nil
        }
    }
    
    func loadMemory() async {
        guard let fileURL = getMemoryFileURL() else { return }
        
        do {
            // Check if file exists, if not create it with default content
            if !fileManager.fileExists(atPath: fileURL.path) {
                let initialContent = """
                # User Memory File
                
                This file contains persistent information about the user that Claude can reference and update.
                
                ## Basic Information
                
                (This section will be filled in as Claude learns about the user)
                
                ## Preferences
                
                (This section will be filled in as Claude learns about the user's preferences)
                
                ## Patterns
                
                (This section will track patterns in the user's behavior and task completion)
                
                ## Daily Basics Tracking
                
                (This section will track daily basics like medication, eating, and drinking water)
                
                ## Notes
                
                (This section contains miscellaneous notes that Claude wants to remember)
                """
                
                try initialContent.write(to: fileURL, atomically: true, encoding: .utf8)
                await MainActor.run {
                    self.memoryContent = initialContent
                }
            } else {
                // Read existing file
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                await MainActor.run {
                    self.memoryContent = content
                }
            }
        } catch {
            print("Error loading memory file: \(error.localizedDescription)")
        }
    }
    
    func readMemory() async -> String {
        await loadMemory()
        return memoryContent
    }
    
    func updateMemory(newContent: String) async -> Bool {
        guard let fileURL = getMemoryFileURL() else { return false }
        
        do {
            try newContent.write(to: fileURL, atomically: true, encoding: .utf8)
            await MainActor.run {
                self.memoryContent = newContent
            }
            return true
        } catch {
            print("Error updating memory file: \(error.localizedDescription)")
            return false
        }
    }
    
    func applyDiff(diff: String) async -> Bool {
        // This function applies a diff to the memory file
        // The diff format is simplified for this example
        // In a real implementation, you'd want a more robust diff parsing system
        
        let currentContent = await readMemory()
        
        // Simple line-by-line diff application
        // Format expected: 
        // - Lines starting with "+" are additions
        // - Lines starting with "-" are removals
        // - Lines without "+" or "-" are context
        
        var newContent = currentContent
        let diffLines = diff.split(separator: "\n")
        
        for line in diffLines {
            if line.hasPrefix("+") {
                // Addition
                let addedLine = String(line.dropFirst())
                newContent += "\n" + addedLine
            } else if line.hasPrefix("-") {
                // Removal
                let removedLine = String(line.dropFirst())
                newContent = newContent.replacingOccurrences(of: removedLine, with: "")
            }
        }
        
        return await updateMemory(newContent: newContent)
    }
}
