import Foundation
import Combine

// Memory item represents an individual memory entry
struct MemoryItem: Identifiable, Codable {
    let id: UUID
    let content: String
    let category: MemoryCategory
    let timestamp: Date
    var importance: Int // 1-5 scale, with 5 being most important
    
    init(id: UUID = UUID(), content: String, category: MemoryCategory, importance: Int = 3, timestamp: Date = Date()) {
        self.id = id
        self.content = content
        self.category = category
        self.importance = importance
        self.timestamp = timestamp
    }
}

// Defines the different categories of memories
enum MemoryCategory: String, Codable, CaseIterable {
    case personalInfo = "Personal Information"
    case preferences = "Preferences"
    case patterns = "Behavior Patterns"
    case dailyBasics = "Daily Basics"
    case medications = "Medications"
    case goals = "Goals"
    case notes = "Miscellaneous Notes"
    
    var description: String {
        switch self {
        case .personalInfo:
            return "Basic information about the user"
        case .preferences:
            return "User preferences and likes/dislikes"
        case .patterns:
            return "Patterns in user behavior and task completion"
        case .dailyBasics:
            return "Tracking of daily basics like eating and drinking water"
        case .medications:
            return "Medication information and tracking"
        case .goals:
            return "Short and long-term goals"
        case .notes:
            return "Miscellaneous information to remember"
        }
    }
}

class MemoryManager: ObservableObject {
    private let memoryFileName = "user_memories.json"
    private let fileManager = FileManager.default
    
    @Published var memories: [MemoryItem] = []
    @Published var memoryContent: String = "" // For backward compatibility
    
    init() {
        Task {
            print("MemoryManager initializing...")
            await loadMemories()
            print("Memory loaded successfully: \(memories.count) items")
        }
    }
    
    // Internal access for testing
    func getMemoryFileURL() -> URL? {
        do {
            let documentsDirectory = try fileManager.url(for: .documentDirectory, 
                                                        in: .userDomainMask, 
                                                        appropriateFor: nil, 
                                                        create: true)
            return documentsDirectory.appendingPathComponent(memoryFileName)
        } catch {
            print("Error getting documents directory: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func createInitialMemories() -> [MemoryItem] {
        return [
            MemoryItem(
                content: "This is a new user. No memories have been collected yet.",
                category: .notes,
                importance: 3
            )
        ]
    }
    
    func loadMemories() async {
        guard let fileURL = getMemoryFileURL() else { return }
        
        do {
            // Check if file exists, if not create it with default content
            if !fileManager.fileExists(atPath: fileURL.path) {
                let initialMemories = createInitialMemories()
                try JSONEncoder().encode(initialMemories).write(to: fileURL)
                
                await MainActor.run {
                    self.memories = initialMemories
                    self.memoryContent = formatMemoriesForClaude()
                }
            } else {
                // Read existing file
                let data = try Data(contentsOf: fileURL)
                let loadedMemories = try JSONDecoder().decode([MemoryItem].self, from: data)
                
                await MainActor.run {
                    self.memories = loadedMemories
                    self.memoryContent = formatMemoriesForClaude()
                }
            }
        } catch {
            print("Error loading memories: \(error.localizedDescription)")
            
            // If there was an error loading, create initial memories
            let initialMemories = createInitialMemories()
            await MainActor.run {
                self.memories = initialMemories
                self.memoryContent = formatMemoriesForClaude()
            }
            
            // Try to save them to fix the file
            try? await saveMemories()
        }
    }
    
    func saveMemories() async throws {
        guard let fileURL = getMemoryFileURL() else {
            throw NSError(domain: "MemoryManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not get memory file URL"])
        }
        
        do {
            let memoriesToSave = await MainActor.run { return memories }
            let data = try JSONEncoder().encode(memoriesToSave)
            try data.write(to: fileURL, options: .atomic)
            
            // Update memory content for backward compatibility
            await MainActor.run {
                self.memoryContent = formatMemoriesForClaude()
            }
        } catch {
            print("Error saving memories: \(error.localizedDescription)")
            throw error
        }
    }
    
    func addMemory(content: String, category: MemoryCategory, importance: Int = 3) async throws {
        print("📝 Attempting to add memory: \"\(content)\" with category: \(category.rawValue), importance: \(importance)")
        
        // Check if content seems to be a calendar event or reminder
        let (isRestricted, restrictedTerm) = isCalendarOrReminderItem(content: content)
        if isRestricted {
            print("📝 ERROR: Memory addition rejected - Content appears to be a calendar event or reminder. Detected term: \"\(restrictedTerm)\"")
            throw NSError(domain: "MemoryManager", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Memory content appears to be a calendar event or reminder. Detected term: \"\(restrictedTerm)\". Please use the appropriate tools instead."
            ])
        }
        
        let newMemory = MemoryItem(content: content, category: category, importance: importance)
        
        await MainActor.run {
            memories.append(newMemory)
            self.memoryContent = formatMemoriesForClaude()
            print("📝 Memory successfully added with ID: \(newMemory.id)")
        }
        
        try await saveMemories()
        print("📝 Memory saved to persistent storage")
    }
    
    // Function to detect if content is likely a calendar event or reminder
    // Made public so it can be used by the tool processing logic
    // Returns a tuple: (isRestricted, restrictedTerm)
    func isCalendarOrReminderItem(content: String) -> (Bool, String) {
        print("🔍 Checking if content is calendar/reminder: \"\(content)\"")
        
        // Common keywords that might indicate a calendar event or reminder
        let calendarKeywords = ["appointment", "meeting", "schedule", "event", "starts at", "ends at", 
                               "on Monday", "on Tuesday", "on Wednesday", "on Thursday", "on Friday", "on Saturday", "on Sunday"]
        let reminderKeywords = ["reminder", "don't forget to", "remember to", "to-do", "todo", "task", "due"]
        
        // Define date/time patterns
        let dateTimePatterns = ["\\d{1,2}:\\d{2}", "\\d{1,2}(am|pm)", "\\d{1,2} (am|pm)", "Jan\\w* \\d{1,2}", "Feb\\w* \\d{1,2}", 
                              "Mar\\w* \\d{1,2}", "Apr\\w* \\d{1,2}", "May \\d{1,2}", "Jun\\w* \\d{1,2}", "Jul\\w* \\d{1,2}", 
                              "Aug\\w* \\d{1,2}", "Sep\\w* \\d{1,2}", "Oct\\w* \\d{1,2}", "Nov\\w* \\d{1,2}", "Dec\\w* \\d{1,2}"]
        
        // Check for calendar keywords
        for keyword in calendarKeywords {
            if content.lowercased().contains(keyword.lowercased()) {
                print("🔍 Calendar keyword detected: \"\(keyword)\" in content")
                return (true, keyword)
            }
        }
        
        // Check for reminder keywords
        for keyword in reminderKeywords {
            if content.lowercased().contains(keyword.lowercased()) {
                print("🔍 Reminder keyword detected: \"\(keyword)\" in content")
                return (true, keyword)
            }
        }
        
        // Check for date/time patterns
        for pattern in dateTimePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(content.startIndex..., in: content)
                if let match = regex.firstMatch(in: content, options: [], range: range) {
                    let matchRange = match.range
                    if let range = Range(matchRange, in: content) {
                        let matchedText = String(content[range])
                        print("🔍 Date/time pattern detected: \"\(matchedText)\" (pattern: \(pattern)) in content")
                        return (true, matchedText)
                    } else {
                        print("🔍 Date/time pattern detected: pattern \"\(pattern)\" in content")
                        return (true, pattern)
                    }
                }
            }
        }
        
        print("🔍 No calendar/reminder patterns detected in content")
        return (false, "")
    }
    
    func updateMemory(id: UUID, newContent: String? = nil, newCategory: MemoryCategory? = nil, newImportance: Int? = nil) async throws {
        guard let index = await MainActor.run(body: { memories.firstIndex(where: { $0.id == id }) }) else {
            throw NSError(domain: "MemoryManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Memory not found"])
        }
        
        // If new content is provided, check if it's a calendar event or reminder
        if let newContent = newContent {
            let (isRestricted, restrictedTerm) = isCalendarOrReminderItem(content: newContent)
            if isRestricted {
                throw NSError(domain: "MemoryManager", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "Memory content appears to be a calendar event or reminder. Detected term: \"\(restrictedTerm)\". Please use the appropriate tools instead."
                ])
            }
        }
        
        await MainActor.run {
            let existingMemory = memories[index]
            
            // Create a new memory item with updated values
            let updatedMemory = MemoryItem(
                id: existingMemory.id,
                content: newContent ?? existingMemory.content,
                category: newCategory ?? existingMemory.category,
                importance: newImportance ?? existingMemory.importance,
                timestamp: existingMemory.timestamp
            )
            
            memories[index] = updatedMemory
            self.memoryContent = formatMemoriesForClaude()
        }
        
        try await saveMemories()
    }
    
    func deleteMemory(id: UUID) async throws {
        guard let index = await MainActor.run(body: { memories.firstIndex(where: { $0.id == id }) }) else {
            throw NSError(domain: "MemoryManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Memory not found"])
        }
        
        await MainActor.run {
            memories.remove(at: index)
            self.memoryContent = formatMemoriesForClaude()
        }
        
        try await saveMemories()
    }
    
    // Get all memories as a formatted string for Claude
    func formatMemoriesForClaude() -> String {
        let sortedMemories = memories.sorted { 
            if $0.importance != $1.importance {
                return $0.importance > $1.importance  // Sort by importance (higher first)
            } else {
                return $0.timestamp > $1.timestamp  // Then by timestamp (newer first)
            }
        }
        
        // Group memories by category
        let groupedMemories = Dictionary(grouping: sortedMemories, by: { $0.category })
        
        // Format the memories
        var result = "USER MEMORY INFORMATION:\n\n"
        
        for category in MemoryCategory.allCases {
            if let categoryMemories = groupedMemories[category], !categoryMemories.isEmpty {
                result += "## \(category.rawValue)\n"
                
                for memory in categoryMemories {
                    result += "- \(memory.content)\n"
                }
                
                result += "\n"
            }
        }
        
        return result
    }
    
    // Compatibility methods for existing API
    func loadMemory() async {
        await loadMemories()
    }
    
    func readMemory() async -> String {
        await loadMemories()
        return memoryContent
    }
    
    func updateMemory(newContent: String) async -> Bool {
        // Legacy method - convert markdown content to memory items
        // This is a simplistic approach - in a real implementation, 
        // we might want to preserve more of the structure
        
        print("Legacy memory update method called - converting markdown to memory items")
        
        // Clear existing memories
        await MainActor.run {
            memories = []
        }
        
        // Split by sections and parse content
        let sections = newContent.components(separatedBy: "##")
        
        for section in sections {
            let lines = section.split(separator: "\n")
            if lines.isEmpty { continue }
            
            // First line should be section title
            let sectionTitle = lines[0].trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Find matching category
            let category = MemoryCategory.allCases.first { $0.rawValue == sectionTitle } ?? .notes
            
            // Process items (lines starting with -)
            for i in 1..<lines.count {
                let line = lines[i]
                if line.hasPrefix("-") {
                    let content = line.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
                    if !content.isEmpty {
                        do {
                            try await addMemory(content: content, category: category)
                        } catch {
                            print("Error adding memory: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
        
        do {
            try await saveMemories()
            return true
        } catch {
            print("Error saving converted memories: \(error.localizedDescription)")
            return false
        }
    }
    
    // Process memory update instructions from Claude in the format [MEMORY_UPDATE] +add -remove [/MEMORY_UPDATE]
    func applyDiff(diff: String) async -> Bool {
        print("Processing memory update from Claude...")
        
        let lines = diff.split(separator: "\n")
        var addedCount = 0
        var removedCount = 0
        
        for line in lines {
            if line.hasPrefix("+") {
                // Addition - simple implementation for now
                let content = String(line.dropFirst())
                
                // Skip if content is likely a calendar event or reminder
                let (isRestricted, restrictedTerm) = isCalendarOrReminderItem(content: content)
                if isRestricted {
                    print("Skipping memory addition: Content appears to be a calendar event or reminder. Detected term: \"\(restrictedTerm)\"")
                    continue
                }
                
                do {
                    try await addMemory(content: content, category: .notes)
                    addedCount += 1
                } catch {
                    print("Error adding memory: \(error.localizedDescription)")
                }
            } else if line.hasPrefix("-") {
                // Removal - do a content match
                let contentToRemove = String(line.dropFirst())
                
                // Find memory with matching content
                if let memoryToRemove = await MainActor.run(body: {
                    return memories.first(where: { $0.content == contentToRemove })
                }) {
                    do {
                        try await deleteMemory(id: memoryToRemove.id)
                        removedCount += 1
                    } catch {
                        print("Error removing memory: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        print("Memory update complete: \(addedCount) additions, \(removedCount) removals")
        return addedCount > 0 || removedCount > 0
    }
    
    // Process structured memory instructions in JSON format for Claude
    func processMemoryInstructions(instructions: String) async -> Bool {
        print("Processing structured memory instructions...")
        
        // Create a JSON decoder
        let decoder = JSONDecoder()
        
        // Process MEMORY_ADD commands
        let memoryAddPattern = "\\[MEMORY_ADD\\]\\s*(\\{[\\s\\S]*?\\})\\s*\\[\\/MEMORY_ADD\\]"
        let memoryRemovePattern = "\\[MEMORY_REMOVE\\]\\s*(\\{[\\s\\S]*?\\})\\s*\\[\\/MEMORY_REMOVE\\]"
        
        // Also support legacy format for backward compatibility
        let legacyAddPattern = "\\[MEMORY_ADD\\] (.*?) \\| (.*?)( \\| (\\d))?$"
        let legacyRemovePattern = "\\[MEMORY_REMOVE\\] (.*)$"
        
        var addedCount = 0
        var removedCount = 0
        
        // Process JSON-based MEMORY_ADD commands
        if let regex = try? NSRegularExpression(pattern: memoryAddPattern, options: []) {
            let matches = regex.matches(in: instructions, range: NSRange(instructions.startIndex..., in: instructions))
            
            for match in matches {
                if let jsonRange = Range(match.range(at: 1), in: instructions) {
                    let jsonString = String(instructions[jsonRange])
                    
                    do {
                        let command = try decoder.decode(MemoryAddCommand.self, from: jsonString.data(using: .utf8)!)
                        
                        // Skip if content is likely a calendar event or reminder
                        let (isRestricted, restrictedTerm) = isCalendarOrReminderItem(content: command.content)
                        if isRestricted {
                            print("Skipping memory instruction: Content appears to be a calendar event or reminder. Detected term: \"\(restrictedTerm)\"")
                            continue
                        }
                        
                        // Map string to category
                        let category = MemoryCategory.allCases.first { $0.rawValue.lowercased() == command.category.lowercased() } ?? .notes
                        
                        // Use provided importance or default to 3
                        let importance = command.importance ?? 3
                        
                        try await addMemory(content: command.content, category: category, importance: importance)
                        addedCount += 1
                        print("Added memory: \(command.content)")
                    } catch {
                        print("Error decoding memory add command: \(error)")
                    }
                }
            }
        }
        
        // Process JSON-based MEMORY_REMOVE commands
        if let regex = try? NSRegularExpression(pattern: memoryRemovePattern, options: []) {
            let matches = regex.matches(in: instructions, range: NSRange(instructions.startIndex..., in: instructions))
            
            for match in matches {
                if let jsonRange = Range(match.range(at: 1), in: instructions) {
                    let jsonString = String(instructions[jsonRange])
                    
                    do {
                        let command = try decoder.decode(MemoryRemoveCommand.self, from: jsonString.data(using: .utf8)!)
                        
                        // Content match
                        if let memoryToRemove = await MainActor.run(body: {
                            return memories.first(where: { $0.content == command.content })
                        }) {
                            try await deleteMemory(id: memoryToRemove.id)
                            removedCount += 1
                            print("Removed memory: \(command.content)")
                        }
                    } catch {
                        print("Error decoding memory remove command: \(error)")
                    }
                }
            }
        }
        
        // Process legacy format for backward compatibility
        if let addRegex = try? NSRegularExpression(pattern: legacyAddPattern, options: .anchorsMatchLines) {
            let matches = addRegex.matches(in: instructions, range: NSRange(instructions.startIndex..., in: instructions))
            
            for match in matches {
                let content = String(instructions[Range(match.range(at: 1), in: instructions)!])
                
                // Skip if content is likely a calendar event or reminder
                let (isRestricted, restrictedTerm) = isCalendarOrReminderItem(content: content)
                if isRestricted {
                    print("Skipping legacy memory instruction: Content appears to be a calendar event or reminder. Detected term: \"\(restrictedTerm)\"")
                    continue
                }
                
                let categoryString = String(instructions[Range(match.range(at: 2), in: instructions)!])
                let importance = match.range(at: 4).location != NSNotFound ? 
                                 Int(String(instructions[Range(match.range(at: 4), in: instructions)!])) ?? 3 : 3
                
                // Map string to category
                let category = MemoryCategory.allCases.first { $0.rawValue.lowercased() == categoryString.lowercased() } ?? .notes
                
                do {
                    try await addMemory(content: content, category: category, importance: importance)
                    addedCount += 1
                    print("Added memory (legacy format): \(content)")
                } catch {
                    print("Error adding memory (legacy format): \(error.localizedDescription)")
                }
            }
        }
        
        if let removeRegex = try? NSRegularExpression(pattern: legacyRemovePattern, options: .anchorsMatchLines) {
            let matches = removeRegex.matches(in: instructions, range: NSRange(instructions.startIndex..., in: instructions))
            
            for match in matches {
                let target = String(instructions[Range(match.range(at: 1), in: instructions)!])
                
                // Try to interpret as UUID first
                if let uuid = UUID(uuidString: target) {
                    // Memory ID
                    do {
                        try await deleteMemory(id: uuid)
                        removedCount += 1
                        print("Removed memory by ID (legacy format): \(uuid)")
                    } catch {
                        print("Error removing memory by ID (legacy format): \(error.localizedDescription)")
                    }
                } else {
                    // Content match
                    if let memoryToRemove = await MainActor.run(body: {
                        return memories.first(where: { $0.content == target })
                    }) {
                        do {
                            try await deleteMemory(id: memoryToRemove.id)
                            removedCount += 1
                            print("Removed memory by content (legacy format): \(target)")
                        } catch {
                            print("Error removing memory by content (legacy format): \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
        
        print("Memory instruction processing complete: \(addedCount) additions, \(removedCount) removals")
        return addedCount > 0 || removedCount > 0
    }
}
