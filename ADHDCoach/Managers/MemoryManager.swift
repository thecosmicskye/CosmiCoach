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
    
    func addMemory(content: String, category: MemoryCategory, importance: Int = 3, messageId: UUID? = nil, chatManager: ChatManager? = nil) async throws {
        print("📝 Attempting to add memory: \"\(content)\" with category: \(category.rawValue), importance: \(importance)")

        var statusMessageId: UUID? = nil
        
        // Create status message if chat context is available
        if let messageId = messageId, let chatManager = chatManager {
            await MainActor.run {
                let statusMessage = chatManager.addOperationStatusMessage(
                    forMessageId: messageId,
                    operationType: OperationType.addMemory,
                    status: .inProgress
                )
                statusMessageId = statusMessage.id
            }
        }

        let newMemory = MemoryItem(content: content, category: category, importance: importance)
        
        do {
            await MainActor.run {
                memories.append(newMemory)
                self.memoryContent = formatMemoriesForClaude()
                print("📝 Memory successfully added with ID: \(newMemory.id)")
                
                // Post notification for sync between devices
                NotificationCenter.default.post(name: NSNotification.Name("MemoryItemAdded"), object: newMemory)
            }
            
            try await saveMemories()
            print("📝 Memory saved to persistent storage")
            
            // Update operation status to success
            if let messageId = messageId, let statusMessageId = statusMessageId, let chatManager = chatManager {
                await MainActor.run {
                    chatManager.updateOperationStatusMessage(
                        forMessageId: messageId,
                        statusMessageId: statusMessageId,
                        status: .success
                    )
                }
            }
            
            return
        } catch {
            print("📝 Error adding memory: \(error.localizedDescription)")
            
            // Update operation status to failure
            if let messageId = messageId, let statusMessageId = statusMessageId, let chatManager = chatManager {
                await MainActor.run {
                    chatManager.updateOperationStatusMessage(
                        forMessageId: messageId,
                        statusMessageId: statusMessageId,
                        status: .failure,
                        details: error.localizedDescription
                    )
                }
            }
            
            throw error
        }
    }
    
    /// Add a memory received from another device (without triggering notification)
    func addReceivedMemory(_ memory: MemoryItem) async throws {
        print("📝 Adding received memory from sync: \"\(memory.content)\"")
        
        await MainActor.run {
            memories.append(memory)
            self.memoryContent = formatMemoriesForClaude()
            print("📝 Synced memory added with ID: \(memory.id)")
        }
        
        try await saveMemories()
        print("📝 Synced memory saved to persistent storage")
    }
    
    func updateMemory(id: UUID, newContent: String? = nil, newCategory: MemoryCategory? = nil, newImportance: Int? = nil, messageId: UUID? = nil, chatManager: ChatManager? = nil) async throws {
        var statusMessageId: UUID? = nil
        
        // Create status message if chat context is available
        if let messageId = messageId, let chatManager = chatManager {
            await MainActor.run {
                let statusMessage = chatManager.addOperationStatusMessage(
                    forMessageId: messageId,
                    operationType: OperationType.updateMemory,
                    status: .inProgress
                )
                statusMessageId = statusMessage.id
            }
        }
        
        guard let index = await MainActor.run(body: { memories.firstIndex(where: { $0.id == id }) }) else {
            let errorMessage = "Memory not found with ID: \(id)"
            
            // Update operation status to failure
            if let messageId = messageId, let statusMessageId = statusMessageId, let chatManager = chatManager {
                await MainActor.run {
                    chatManager.updateOperationStatusMessage(
                        forMessageId: messageId,
                        statusMessageId: statusMessageId,
                        status: .failure,
                        details: errorMessage
                    )
                }
            }
            
            throw NSError(domain: "MemoryManager", code: 2, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }

        do {
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
                
                // Post notification for sync between devices
                NotificationCenter.default.post(name: NSNotification.Name("MemoryItemAdded"), object: updatedMemory)
            }
            
            try await saveMemories()
            
            // Update operation status to success
            if let messageId = messageId, let statusMessageId = statusMessageId, let chatManager = chatManager {
                await MainActor.run {
                    chatManager.updateOperationStatusMessage(
                        forMessageId: messageId,
                        statusMessageId: statusMessageId,
                        status: .success
                    )
                }
            }
        } catch {
            // Update operation status to failure
            if let messageId = messageId, let statusMessageId = statusMessageId, let chatManager = chatManager {
                await MainActor.run {
                    chatManager.updateOperationStatusMessage(
                        forMessageId: messageId,
                        statusMessageId: statusMessageId,
                        status: .failure,
                        details: error.localizedDescription
                    )
                }
            }
            
            throw error
        }
    }
    
    func deleteMemory(id: UUID, messageId: UUID? = nil, chatManager: ChatManager? = nil) async throws {
        var statusMessageId: UUID? = nil
        
        // Create status message if chat context is available
        if let messageId = messageId, let chatManager = chatManager {
            await MainActor.run {
                let statusMessage = chatManager.addOperationStatusMessage(
                    forMessageId: messageId,
                    operationType: OperationType.deleteMemory,
                    status: .inProgress
                )
                statusMessageId = statusMessage.id
            }
        }
        
        guard let index = await MainActor.run(body: { memories.firstIndex(where: { $0.id == id }) }) else {
            let errorMessage = "Memory not found with ID: \(id)"
            
            // Update operation status to failure
            if let messageId = messageId, let statusMessageId = statusMessageId, let chatManager = chatManager {
                await MainActor.run {
                    chatManager.updateOperationStatusMessage(
                        forMessageId: messageId,
                        statusMessageId: statusMessageId,
                        status: .failure,
                        details: errorMessage
                    )
                }
            }
            
            throw NSError(domain: "MemoryManager", code: 2, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
        
        do {
            await MainActor.run {
                // Get the memory item before removal for notification
                let removedMemory = memories[index]
                
                // Remove from memory array
                memories.remove(at: index)
                self.memoryContent = formatMemoriesForClaude()
                
                // For now, we don't handle deletes across devices - we would need to create a special sync message
                // type for deletes or provide a "deleted" flag in the memory model
            }
            
            try await saveMemories()
            
            // Update operation status to success
            if let messageId = messageId, let statusMessageId = statusMessageId, let chatManager = chatManager {
                await MainActor.run {
                    chatManager.updateOperationStatusMessage(
                        forMessageId: messageId,
                        statusMessageId: statusMessageId,
                        status: .success
                    )
                }
            }
        } catch {
            // Update operation status to failure
            if let messageId = messageId, let statusMessageId = statusMessageId, let chatManager = chatManager {
                await MainActor.run {
                    chatManager.updateOperationStatusMessage(
                        forMessageId: messageId,
                        statusMessageId: statusMessageId,
                        status: .failure,
                        details: error.localizedDescription
                    )
                }
            }
            
            throw error
        }
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
    
    // Main method to read memory for API consumption
    func readMemory() async -> String {
        await loadMemories()
        return memoryContent
    }
    
    func updateMemory(newContent: String) async -> Bool {
        // Legacy method - no longer supported
        print("Legacy memory update method called but is no longer supported")
        return false
    }

    func applyDiff(diff: String) async -> Bool {
        print("Legacy diff format memory updates are no longer supported - use JSON-based commands instead")
        return false
    }
    
    // Process structured memory instructions in JSON format for Claude
    func processMemoryInstructions(instructions: String) async -> Bool {
        print("Processing structured memory instructions...")
        
        // Create a JSON decoder
        let decoder = JSONDecoder()
        
        // Process MEMORY_ADD commands
        let memoryAddPattern = "\\[MEMORY_ADD\\]\\s*(\\{[\\s\\S]*?\\})\\s*\\[\\/MEMORY_ADD\\]"
        let memoryRemovePattern = "\\[MEMORY_REMOVE\\]\\s*(\\{[\\s\\S]*?\\})\\s*\\[\\/MEMORY_REMOVE\\]"

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
                        
                        // We no longer filter by content type
                        // Claude is instructed to use appropriate tools for calendar and reminders
                        
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

        print("Memory instruction processing complete: \(addedCount) additions, \(removedCount) removals")
        return addedCount > 0 || removedCount > 0
    }
}
