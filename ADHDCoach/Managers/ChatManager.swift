import Foundation
import Combine

class ChatManager: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isProcessing = false
    @Published var currentStreamingMessageId: UUID?
    @Published var streamingUpdateCount: Int = 0  // Track streaming updates for scrolling
    
    private var apiKey: String {
        return UserDefaults.standard.string(forKey: "claude_api_key") ?? ""
    }
    private let maxTokens = 75000
    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let streamingURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private var memoryManager: MemoryManager?
    private var eventKitManager: EventKitManager?
    private var currentStreamingMessage: String = ""
    private var urlSession = URLSession.shared
    private var lastAppOpenTime: Date?
    
    // System prompt that defines Claude's role
    private let systemPrompt = """
    You are an empathic ADHD coach assistant that helps the user manage their tasks, calendar, and daily life. Your goal is to help them overcome overwhelm and make decisions about what to focus on.

    Guidelines:
    1. Be concise and clear in your responses
    2. Ask only one question at a time to minimize decision fatigue
    3. Proactively suggest task prioritization
    4. Check on daily basics (medicine, eating, drinking water)
    5. Analyze patterns in task completion over time
    6. Use the provided calendar events and reminders to give context-aware advice
    7. You can create, modify, or delete calendar events and reminders by using specific formatting
    8. Be empathetic and understanding of ADHD challenges
    9. Maintain important user information in structured memory categories

    To modify calendar or reminders, use the following format:
    [CALENDAR_ADD] Title | Start time | End time | Notes (optional)
    [CALENDAR_MODIFY] Event ID | New title | New start time | New end time | New notes (optional)
    [CALENDAR_DELETE] Event ID

    [REMINDER_ADD] Title | Due date/time or "No due date" | Notes (optional) | List name (optional)
    [REMINDER_MODIFY] Reminder ID | New title | New due date/time or "No due date" | New notes (optional) | List name (optional)
    
    Example: [REMINDER_ADD] Call doctor | No due date | Schedule appointment | Personal
    [REMINDER_DELETE] Reminder ID

    You have access to the user's memory which contains information about them that persists between conversations. This information is organized into categories:
    - Personal Information: Basic information about the user
    - Preferences: User preferences and likes/dislikes
    - Behavior Patterns: Patterns in user behavior and task completion
    - Daily Basics: Tracking of daily basics like eating and drinking water
    - Medications: Medication information and tracking
    - Goals: Short and long-term goals
    - Miscellaneous Notes: Other information to remember

    To add or update memories, use the following format:
    [MEMORY_ADD] Content | Category | Importance (1-5, optional)
    
    Examples:
    [MEMORY_ADD] User takes 20mg Adderall at 8am daily | Medications | 5
    [MEMORY_ADD] User prefers short, direct answers | Preferences | 4
    [MEMORY_ADD] User struggles with morning routines | Behavior Patterns | 3
    
    To remove outdated memories:
    [MEMORY_REMOVE] Exact content to match and remove
    
    Important:
    - Memories with higher importance (4-5) are most critical to refer to
    - Don't add redundant memories - check existing memories first 
    - Update memories when information changes rather than creating duplicates
    - Delete outdated information in memories
    - When adding specific facts, add them as separate memory items instead of combining multiple facts
    - The memory content is visible at the top of each conversation under USER MEMORY INFORMATION
    - DO NOT add calendar events or reminders as memories
    - Avoid duplicating memories
    """
    
    @MainActor
    init() {
        // Load previous messages from storage
        loadMessages()
        
        // Reset any incomplete messages from previous sessions
        resetIncompleteMessages()
        
        // Add initial assistant message if this is the first time
        if messages.isEmpty {
            let welcomeMessage = "Hi! I'm your ADHD Coach. I can help you manage your tasks, calendar, and overcome overwhelm. How are you feeling today?"
            addAssistantMessage(content: welcomeMessage)
        }
        
        // Record the time the app was opened
        lastAppOpenTime = Date()
    }
    
    @MainActor
    private func resetIncompleteMessages() {
        // Find any incomplete messages and mark them as complete
        // This handles cases where the app was closed during message streaming
        for (index, message) in messages.enumerated() {
            if !message.isComplete {
                // Mark as complete
                messages[index].isComplete = true
                
                // Only add the interruption tag if it's not already there
                if !message.content.hasSuffix("[Message was interrupted]") {
                    // Add the tag only if there's actual content
                    if !message.content.isEmpty {
                        messages[index].content += " [Message was interrupted]"
                    } else {
                        messages[index].content = "[Message was interrupted]"
                    }
                }
            }
        }
        
        // Reset streaming state
        currentStreamingMessageId = nil
        isProcessing = false
        
        // Clear any saved state in UserDefaults
        UserDefaults.standard.removeObject(forKey: "streaming_message_id")
        UserDefaults.standard.removeObject(forKey: "last_streaming_content")
        UserDefaults.standard.set(false, forKey: "chat_processing_state")
        
        // Save changes
        saveMessages()
    }
    
    func setMemoryManager(_ manager: MemoryManager) {
        self.memoryManager = manager
    }
    
    func setEventKitManager(_ manager: EventKitManager) {
        self.eventKitManager = manager
    }
    
    @MainActor
    func checkAndSendAutomaticMessage() async {
        // Check if automatic messages are enabled in settings
        guard UserDefaults.standard.bool(forKey: "enable_automatic_responses") else {
            print("Automatic message skipped: Automatic messages are disabled in settings")
            return
        }
        
        // Check if we have the API key
        guard !apiKey.isEmpty else {
            print("Automatic message skipped: No API key available")
            return
        }
        
        // Check if this is app open (we have a last open time and it's recent)
        guard let lastOpen = lastAppOpenTime, Date().timeIntervalSince(lastOpen) < 30 else {
            print("Automatic message skipped: Not a recent app open")
            return
        }
        
        // Check if the app hasn't been opened for at least 5 minutes
        let lastSessionKey = "last_app_session_time"
        
        // Always store current time when checking - this fixes the bug where
        // closing the app without fully terminating doesn't update the session time
        let currentTime = Date().timeIntervalSince1970
        
        if let lastSessionTimeInterval = UserDefaults.standard.object(forKey: lastSessionKey) as? TimeInterval {
            let lastSessionTime = Date(timeIntervalSince1970: lastSessionTimeInterval)
            let timeSinceLastSession = Date().timeIntervalSince(lastSessionTime)
            
            // If it's been less than 5 minutes, don't send automatic message
            if timeSinceLastSession < 300 { // 300 seconds = 5 minutes
                print("Automatic message skipped: App was opened less than 5 minutes ago")
                return
            }
        }
        
        // Store current session time for future reference
        UserDefaults.standard.set(currentTime, forKey: lastSessionKey)
        UserDefaults.standard.synchronize() // Force synchronize to ensure it's saved
        
        // If we get here, all conditions are met - send the automatic message
        await sendAutomaticMessage()
    }
    
    @MainActor
    func checkAndSendAutomaticMessageAfterHistoryDeletion() async {
        // Check if automatic messages are enabled in settings
        // For history deletion, we respect the setting but always provide a fallback message
        let automaticMessagesEnabled = UserDefaults.standard.bool(forKey: "enable_automatic_responses")
        
        if !automaticMessagesEnabled {
            print("Automatic message after history deletion skipped: Automatic messages are disabled in settings")
            // Always show a welcome message when chat history is cleared, even if automatic messages are disabled
            addAssistantMessage(content: "Hi! I'm your ADHD Coach. I can help you manage your tasks, calendar, and overcome overwhelm. How are you feeling today?")
            return
        }
        
        // Check if we have the API key
        guard !apiKey.isEmpty else {
            print("Automatic message after history deletion skipped: No API key available")
            // Fall back to a static welcome message if we can't query
            addAssistantMessage(content: "Hi! I'm your ADHD Coach. I can help you manage your tasks, calendar, and overcome overwhelm. How are you feeling today?")
            return
        }
        
        // If we get here, send an automatic message
        await sendAutomaticMessage(isAfterHistoryDeletion: true)
    }
    
    @MainActor
    func addUserMessage(content: String) {
        let message = ChatMessage(content: content, isUser: true)
        messages.append(message)
        saveMessages()
    }
    
    @MainActor
    func addAssistantMessage(content: String, isComplete: Bool = true) {
        let message = ChatMessage(content: content, isUser: false, isComplete: isComplete)
        
        if let streamingId = currentStreamingMessageId, !isComplete {
            // If we already have a streaming message, update it
            if let index = messages.firstIndex(where: { $0.id == streamingId }) {
                messages[index].content = content
            } else {
                // Otherwise create a new streaming message
                messages.append(message)
                currentStreamingMessageId = message.id
            }
        } else {
            // For complete messages or new streaming messages
            messages.append(message)
            if !isComplete {
                currentStreamingMessageId = message.id
            } else {
                currentStreamingMessageId = nil
            }
        }
        
        saveMessages()
    }
    
    @MainActor
    func updateStreamingMessage(content: String) {
        if let streamingId = currentStreamingMessageId,
           let index = messages.firstIndex(where: { $0.id == streamingId }) {
            // Update the message content
            messages[index].content = content
            // Increment counter to trigger scroll updates
            streamingUpdateCount += 1
            // Save messages to ensure they're persisted
            saveMessages()
        }
    }
    
    // This method both updates the UI and returns the accumulated content
    // It's isolated to the MainActor to avoid concurrency issues
    @MainActor
    func appendToStreamingMessage(newContent: String) -> String {
        if let streamingId = currentStreamingMessageId,
           let index = messages.firstIndex(where: { $0.id == streamingId }) {
            // Append the new content to the existing content
            let updatedContent = messages[index].content + newContent
            
            // Update the message
            messages[index].content = updatedContent
            
            // Increment counter to trigger scroll updates
            streamingUpdateCount += 1
            
            // Save messages to ensure they're persisted
            saveMessages()
            
            // Return the updated content
            return updatedContent
        }
        return ""
    }
    
    @MainActor
    func finalizeStreamingMessage() {
        if let streamingId = currentStreamingMessageId,
           let index = messages.firstIndex(where: { $0.id == streamingId }) {
            messages[index].isComplete = true
            currentStreamingMessageId = nil
            // Trigger one final update for scrolling
            streamingUpdateCount += 1
            // Save messages to persist the finalized state
            saveMessages()
        }
    }
    
    @MainActor
    func saveMessages() {
        // Save messages to UserDefaults for persistence
        if let encoded = try? JSONEncoder().encode(messages) {
            UserDefaults.standard.set(encoded, forKey: "chat_messages")
            
            // Save processing state for recovery after app restart
            UserDefaults.standard.set(isProcessing, forKey: "chat_processing_state")
            if let id = currentStreamingMessageId {
                UserDefaults.standard.set(id.uuidString, forKey: "streaming_message_id")
            } else {
                UserDefaults.standard.removeObject(forKey: "streaming_message_id")
            }
        }
    }
    
    @MainActor
    func loadMessages() {
        // Load messages from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "chat_messages"),
           let decoded = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            messages = decoded
            
            // Load saved streaming state (if any)
            if let savedStreamingIdString = UserDefaults.standard.string(forKey: "streaming_message_id"),
               let savedStreamingId = UUID(uuidString: savedStreamingIdString) {
                // Only set if the message actually exists
                if messages.contains(where: { $0.id == savedStreamingId }) {
                    currentStreamingMessageId = savedStreamingId
                }
            }
            
            // Load processing state, but we'll reset this in resetIncompleteMessages()
            isProcessing = UserDefaults.standard.bool(forKey: "chat_processing_state")
        }
    }
    
    func sendMessageToClaude(userMessage: String, calendarEvents: [CalendarEvent], reminders: [ReminderItem]) async {
        guard !apiKey.isEmpty else {
            await MainActor.run {
                addAssistantMessage(content: "Please set your Claude API key in settings.")
            }
            return
        }
        
        // Check if the API key looks like a Claude API key (should start with sk-ant)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.hasPrefix("sk-ant") {
            await MainActor.run {
                addAssistantMessage(content: "The API key doesn't appear to be a valid Claude API key. Claude API keys typically start with 'sk-ant-'. Please check your API key in settings.")
            }
            return
        }
        
        await MainActor.run {
            isProcessing = true
        }
        
        // Prepare context for Claude
        var memoryContent = "No memory available."
        if let manager = memoryManager {
            memoryContent = await manager.readMemory()
            print("Memory content loaded for Claude request. Length: \(memoryContent.count)")
        } else {
            print("WARNING: Memory manager not available when sending message to Claude")
        }
        
        // Format calendar events and reminders for context
        let calendarContext = formatCalendarEvents(calendarEvents)
        let remindersContext = formatReminders(reminders)
        
        // Get recent conversation history (limited by token count)
        let conversationHistory = await MainActor.run {
            return getRecentConversationHistory()
        }
        
        // Create the request body with system as a top-level parameter
        let requestBody: [String: Any] = [
            "model": "claude-3-7-sonnet-20250219",
            "max_tokens": 4000,
            "system": systemPrompt,
            "stream": true,
            "messages": [
                ["role": "user", "content": [
                    ["type": "text", "text": """
                    Current time: \(formatCurrentDateTime())
                    
                    USER MEMORY:
                    \(memoryContent)
                    
                    CALENDAR EVENTS:
                    \(calendarContext)
                    
                    REMINDERS:
                    \(remindersContext)
                    
                    CONVERSATION HISTORY:
                    \(conversationHistory)
                    
                    USER MESSAGE:
                    \(userMessage)
                    """]
                ]]
            ]
        ]
        
        // Create the request
        var request = URLRequest(url: streamingURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            // Initialize streaming message
            await MainActor.run {
                currentStreamingMessage = ""
                addAssistantMessage(content: "", isComplete: false)
            }
            
            // Create a URLSession data task with delegate
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                await MainActor.run {
                    self.addAssistantMessage(content: "Error: Invalid HTTP response")
                    self.isProcessing = false
                }
                return
            }
            
            if httpResponse.statusCode != 200 {
                var errorData = Data()
                for try await byte in asyncBytes {
                    errorData.append(byte)
                }
                
                // Try to extract error message from response
                let statusCode = httpResponse.statusCode
                var errorDetails = ""
                
                if let responseString = String(data: errorData, encoding: .utf8) {
                    print("API Error Response: \(responseString)")
                    
                    if let errorJson = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
                       let error = errorJson["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        errorDetails = ". \(message)"
                    }
                }
                
                let finalErrorMessage = "Error communicating with Claude API. Status code: \(statusCode)\(errorDetails)"
                
                await MainActor.run {
                    self.finalizeStreamingMessage()
                    self.addAssistantMessage(content: finalErrorMessage)
                    self.isProcessing = false
                }
                return
            }
            
            // Track the full response for post-processing
            var fullResponse = ""
            
            // Process the streaming response
            for try await line in asyncBytes.lines {
                // Skip empty lines
                guard !line.isEmpty else { continue }
                
                // SSE format has "data: " prefix
                guard line.hasPrefix("data: ") else { continue }
                
                // Remove the "data: " prefix
                let jsonStr = line.dropFirst(6)
                
                // Handle the stream end event
                if jsonStr == "[DONE]" {
                    break
                }
                
                // Parse the JSON
                if let data = jsonStr.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    
                    // Extract message content
                    if let contentDelta = json["delta"] as? [String: Any],
                       let contentItems = contentDelta["text"] as? String {
                        
                        // Send the new content to the MainActor for UI updates
                        // and get back the full accumulated content
                        let updatedContent = await MainActor.run {
                            return appendToStreamingMessage(newContent: contentItems)
                        }
                        
                        // Keep track of the full response for post-processing
                        fullResponse = updatedContent
                    }
                }
            }
            
            // Process the response for any calendar, reminder, or memory modifications
            await processClaudeResponse(fullResponse)
            
            // Look for memory update patterns and apply them
            await processMemoryUpdates(fullResponse)
            
            // Finalize the assistant message
            await MainActor.run {
                finalizeStreamingMessage()
                isProcessing = false
            }
            
        } catch {
            await MainActor.run {
                self.finalizeStreamingMessage()
                self.addAssistantMessage(content: "Error: \(error.localizedDescription)")
                self.isProcessing = false
            }
        }
    }
    
    private func formatCurrentDateTime() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .full
        formatter.timeZone = TimeZone.current
        return "\(formatter.string(from: Date())) (\(TimeZone.current.identifier))"
    }
    
    private func formatCalendarEvents(_ events: [CalendarEvent]) -> String {
        if events.isEmpty {
            return "No upcoming events."
        }
        
        return events.map { event in
            """
            ID: \(event.id)
            Title: \(event.title)
            Start: \(formatDate(event.startDate))
            End: \(formatDate(event.endDate))
            Notes: \(event.notes ?? "None")
            """
        }.joined(separator: "\n\n")
    }
    
    private func formatReminders(_ reminders: [ReminderItem]) -> String {
        if reminders.isEmpty {
            return "No reminders."
        }
        
        return reminders.map { reminder in
            """
            ID: \(reminder.id)
            Title: \(reminder.title)
            Due: \(reminder.dueDate != nil ? formatDate(reminder.dueDate!) : "No due date")
            Completed: \(reminder.isCompleted ? "Yes" : "No")
            Notes: \(reminder.notes ?? "None")
            List: \(reminder.listName)
            """
        }.joined(separator: "\n\n")
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
    
    @MainActor
    private func getRecentConversationHistory() -> String {
        // Get the most recent messages that fit within token limit
        // This is a simplified implementation - in a real app, you'd want to count tokens properly
        let recentMessages = messages.suffix(20) // Just use last 20 messages as a simple approach
        
        return recentMessages.map { message in
            let role = message.isUser ? "User" : "Assistant"
            let time = formatDate(message.timestamp)
            return "[\(time)] \(role): \(message.content)"
        }.joined(separator: "\n\n")
    }
    
    // Function to send an automatic message without user input
    private func sendAutomaticMessage(isAfterHistoryDeletion: Bool = false) async {
        // Get context data
        let calendarEvents = eventKitManager?.fetchUpcomingEvents(days: 7) ?? []
        let reminders = await eventKitManager?.fetchReminders() ?? []
        
        // Prepare context for Claude
        var memoryContent = "No memory available."
        if let manager = memoryManager {
            memoryContent = await manager.readMemory()
            print("Memory content loaded for automatic message request. Length: \(memoryContent.count)")
        } else {
            print("WARNING: Memory manager not available for automatic message")
        }
        
        // Format calendar events and reminders for context
        let calendarContext = formatCalendarEvents(calendarEvents)
        let remindersContext = formatReminders(reminders)
        
        // Get recent conversation history
        let conversationHistory = await MainActor.run {
            return getRecentConversationHistory()
        }
        
        // Set up the request with special context indicating this is an automatic message
        let requestBody: [String: Any] = [
            "model": "claude-3-7-sonnet-20250219",
            "max_tokens": 4000,
            "system": systemPrompt,
            "stream": true,
            "messages": [
                ["role": "user", "content": [
                    ["type": "text", "text": """
                    Current time: \(formatCurrentDateTime())
                    
                    USER MEMORY:
                    \(memoryContent)
                    
                    CALENDAR EVENTS:
                    \(calendarContext)
                    
                    REMINDERS:
                    \(remindersContext)
                    
                    CONVERSATION HISTORY:
                    \(conversationHistory)
                    
                    USER MESSAGE:
                    [THIS IS AN AUTOMATIC MESSAGE - \(isAfterHistoryDeletion ? "The user has just cleared their chat history." : "The user has just opened the app after not using it for at least 5 minutes.") There is no specific user message. Based on the time of day, calendar events, reminders, and what you know about the user, provide a helpful, proactive greeting or insight.]
                    """]
                ]]
            ]
        ]
        
        await MainActor.run {
            isProcessing = true
        }
        
        // Create the request
        var request = URLRequest(url: streamingURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            // Initialize streaming message
            await MainActor.run {
                currentStreamingMessage = ""
                addAssistantMessage(content: "", isComplete: false)
            }
            
            // Handle the streaming response like normal
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                await MainActor.run {
                    self.finalizeStreamingMessage()
                    self.isProcessing = false
                }
                print("Automatic message error: Invalid HTTP response")
                return
            }
            
            if httpResponse.statusCode != 200 {
                await MainActor.run {
                    self.finalizeStreamingMessage()
                    self.isProcessing = false
                }
                print("Automatic message HTTP error: \(httpResponse.statusCode)")
                return
            }
            
            // Track the full response for post-processing
            var fullResponse = ""
            
            // Process the streaming response
            for try await line in asyncBytes.lines {
                // Skip empty lines
                guard !line.isEmpty else { continue }
                
                // SSE format has "data: " prefix
                guard line.hasPrefix("data: ") else { continue }
                
                // Remove the "data: " prefix
                let jsonStr = line.dropFirst(6)
                
                // Handle the stream end event
                if jsonStr == "[DONE]" {
                    break
                }
                
                // Parse the JSON
                if let data = jsonStr.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    
                    // Extract message content
                    if let contentDelta = json["delta"] as? [String: Any],
                       let contentItems = contentDelta["text"] as? String {
                        
                        // Send the new content to the MainActor for UI updates
                        // and get back the full accumulated content
                        let updatedContent = await MainActor.run {
                            return appendToStreamingMessage(newContent: contentItems)
                        }
                        
                        // Keep track of the full response for post-processing
                        fullResponse = updatedContent
                    }
                }
            }
            
            // Process the response like normal
            await processClaudeResponse(fullResponse)
            await processMemoryUpdates(fullResponse)
            
            // Finalize the assistant message
            await MainActor.run {
                finalizeStreamingMessage()
                isProcessing = false
            }
            
        } catch {
            print("Automatic message error: \(error.localizedDescription)")
            await MainActor.run {
                self.finalizeStreamingMessage()
                self.isProcessing = false
            }
        }
    }
    
    // Simple function to test the API key
    func testApiKey() async -> String {
        // Get the API key from UserDefaults
        guard !apiKey.isEmpty else {
            return "❌ Error: API key is not set"
        }
        
        // Create a simple request to test the API key
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        // Use the API key with the correct header
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        
        // Simple request body with correct format, stream: false for simple testing
        let requestBody: [String: Any] = [
            "model": "claude-3-7-sonnet-20250219",
            "max_tokens": 10,
            "stream": false,
            "messages": [
                ["role": "user", "content": "Hello"]
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    return "✅ API key is valid!"
                } else {
                    // Try to extract error message
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("API Error Response: \(responseString)")
                        return "❌ Error: \(responseString)"
                    } else {
                        return "❌ Error: Status code \(httpResponse.statusCode)"
                    }
                }
            } else {
                return "❌ Error: Invalid HTTP response"
            }
        } catch {
            return "❌ Error: \(error.localizedDescription)"
        }
    }
    
    private func processMemoryUpdates(_ response: String) async {
        // Check if we have a memory manager
        guard let memManager = await MainActor.run(body: { [weak self] in
            return self?.memoryManager
        }) else {
            print("Error: MemoryManager not available for memory updates")
            return
        }
        
        // Support both old and new memory update formats for backward compatibility
        
        // 1. Check for old format memory updates
        let memoryUpdatePattern = "\\[MEMORY_UPDATE\\]([\\s\\S]*?)\\[\\/MEMORY_UPDATE\\]"
        if let regex = try? NSRegularExpression(pattern: memoryUpdatePattern, options: []) {
            let matches = regex.matches(in: response, range: NSRange(response.startIndex..., in: response))
            
            for match in matches {
                if let updateRange = Range(match.range(at: 1), in: response) {
                    let diffContent = String(response[updateRange])
                    print("Found legacy memory update instruction: \(diffContent.count) characters")
                    
                    // Apply the diff to the memory file
                    let success = await memManager.applyDiff(diff: diffContent.trimmingCharacters(in: .whitespacesAndNewlines))
                    
                    if success {
                        print("Successfully applied legacy memory update")
                    } else {
                        print("Failed to apply legacy memory update")
                    }
                }
            }
        }
        
        // 2. Check for new structured memory instructions
        // Process the new structured memory format
        // This uses the new method in MemoryManager
        let success = await memManager.processMemoryInstructions(instructions: response)
        
        if success {
            print("Successfully processed structured memory instructions")
        }
    }
    
    private func processClaudeResponse(_ response: String) async {
        // Get access to the EventKitManager
        guard let eventKitManager = await MainActor.run(body: { [weak self] in
            return self?.eventKitManager
        }) else {
            print("Error: EventKitManager not available")
            return
        }
        
        // Create a date formatter for parsing dates
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        
        // Process all calendar add commands in the response
        let calendarAddPattern = "\\[CALENDAR_ADD\\] (.*?) \\| (.*?) \\| (.*?)( \\| (.*?))?$"
        if let regex = try? NSRegularExpression(pattern: calendarAddPattern, options: .anchorsMatchLines) {
            let matches = regex.matches(in: response, range: NSRange(response.startIndex..., in: response))
            
            for match in matches {
                let title = response[Range(match.range(at: 1), in: response)!]
                let startDateString = String(response[Range(match.range(at: 2), in: response)!])
                let endDateString = String(response[Range(match.range(at: 3), in: response)!])
                let notes = match.range(at: 5).location != NSNotFound ? String(response[Range(match.range(at: 5), in: response)!]) : nil
                
                // Parse dates
                guard let startDate = dateFormatter.date(from: startDateString) else {
                    print("Error parsing start date: \(startDateString)")
                    continue
                }
                
                guard let endDate = dateFormatter.date(from: endDateString) else {
                    print("Error parsing end date: \(endDateString)")
                    continue
                }
                
                // Add the calendar event
                let success = await MainActor.run {
                    return eventKitManager.addCalendarEvent(title: String(title), startDate: startDate, endDate: endDate, notes: notes)
                }
                
                if success {
                    print("Successfully added calendar event: \(title)")
                } else {
                    print("Failed to add calendar event: \(title)")
                }
            }
        }
        
        // Process all reminder add commands in the response
        let reminderAddPattern = "\\[REMINDER_ADD\\] (.*?) \\| (.*?)( \\| (.*?))?( \\| (.*?))?$"
        if let regex = try? NSRegularExpression(pattern: reminderAddPattern, options: .anchorsMatchLines) {
            let matches = regex.matches(in: response, range: NSRange(response.startIndex..., in: response))
            
            for match in matches {
                let title = response[Range(match.range(at: 1), in: response)!]
                let dueDateString = String(response[Range(match.range(at: 2), in: response)!])
                
                // Extract notes and list name
                let notes: String?
                let listName: String?
                
                if match.range(at: 4).location != NSNotFound {
                    notes = String(response[Range(match.range(at: 4), in: response)!])
                    
                    // Check if there's a list name
                    if match.range(at: 6).location != NSNotFound {
                        listName = String(response[Range(match.range(at: 6), in: response)!])
                    } else {
                        listName = nil
                    }
                } else {
                    notes = nil
                    listName = nil
                }
                
                // Handle the case when "No due date" is specified
                let dueDate: Date?
                if dueDateString.lowercased() == "no due date" {
                    dueDate = nil
                } else {
                    // Parse due date for normal cases
                    guard let parsedDate = dateFormatter.date(from: dueDateString) else {
                        print("Error parsing due date: \(dueDateString)")
                        continue
                    }
                    dueDate = parsedDate
                }
                
                // Add the reminder
                let success = await MainActor.run {
                    return eventKitManager.addReminder(title: String(title), dueDate: dueDate, notes: notes, listName: listName)
                }
                
                if success {
                    print("Successfully added reminder: \(title)")
                } else {
                    print("Failed to add reminder: \(title)")
                }
            }
        }
        
        // Process calendar modify commands
        let calendarModifyPattern = "\\[CALENDAR_MODIFY\\] (.*?) \\| (.*?) \\| (.*?) \\| (.*?)( \\| (.*?))?$"
        if let regex = try? NSRegularExpression(pattern: calendarModifyPattern, options: .anchorsMatchLines) {
            let matches = regex.matches(in: response, range: NSRange(response.startIndex..., in: response))
            
            for match in matches {
                let eventId = String(response[Range(match.range(at: 1), in: response)!])
                let newTitle = String(response[Range(match.range(at: 2), in: response)!])
                let startDateString = String(response[Range(match.range(at: 3), in: response)!])
                let endDateString = String(response[Range(match.range(at: 4), in: response)!])
                let notes = match.range(at: 6).location != NSNotFound ? String(response[Range(match.range(at: 6), in: response)!]) : nil
                
                // Parse dates
                guard let startDate = dateFormatter.date(from: startDateString) else {
                    print("Error parsing start date: \(startDateString)")
                    continue
                }
                
                guard let endDate = dateFormatter.date(from: endDateString) else {
                    print("Error parsing end date: \(endDateString)")
                    continue
                }
                
                // Update the calendar event
                let success = await MainActor.run {
                    return eventKitManager.updateCalendarEvent(id: eventId, title: newTitle, startDate: startDate, endDate: endDate, notes: notes)
                }
                
                if success {
                    print("Successfully updated calendar event: \(newTitle)")
                } else {
                    print("Failed to update calendar event: \(newTitle)")
                }
            }
        }
        
        // Process calendar delete commands
        let calendarDeletePattern = "\\[CALENDAR_DELETE\\] (.*?)$"
        if let regex = try? NSRegularExpression(pattern: calendarDeletePattern, options: .anchorsMatchLines) {
            let matches = regex.matches(in: response, range: NSRange(response.startIndex..., in: response))
            
            for match in matches {
                let eventId = String(response[Range(match.range(at: 1), in: response)!])
                
                // Delete the calendar event
                let success = await MainActor.run {
                    return eventKitManager.deleteCalendarEvent(id: eventId)
                }
                
                if success {
                    print("Successfully deleted calendar event with ID: \(eventId)")
                } else {
                    print("Failed to delete calendar event with ID: \(eventId)")
                }
            }
        }
        
        // Process reminder modify commands
        let reminderModifyPattern = "\\[REMINDER_MODIFY\\] (.*?) \\| (.*?) \\| (.*?)( \\| (.*?))?( \\| (.*?))?$"
        if let regex = try? NSRegularExpression(pattern: reminderModifyPattern, options: .anchorsMatchLines) {
            let matches = regex.matches(in: response, range: NSRange(response.startIndex..., in: response))
            
            for match in matches {
                let reminderId = String(response[Range(match.range(at: 1), in: response)!])
                let newTitle = String(response[Range(match.range(at: 2), in: response)!])
                let dueDateString = String(response[Range(match.range(at: 3), in: response)!])
                
                // Extract notes and list name
                let notes: String?
                let listName: String?
                
                if match.range(at: 5).location != NSNotFound {
                    notes = String(response[Range(match.range(at: 5), in: response)!])
                    
                    // Check if there's a list name
                    if match.range(at: 7).location != NSNotFound {
                        listName = String(response[Range(match.range(at: 7), in: response)!])
                    } else {
                        listName = nil
                    }
                } else {
                    notes = nil
                    listName = nil
                }
                
                // Handle the case when "No due date" is specified
                let dueDate: Date?
                if dueDateString.lowercased() == "no due date" {
                    dueDate = nil
                } else {
                    // Parse due date for normal cases
                    guard let parsedDate = dateFormatter.date(from: dueDateString) else {
                        print("Error parsing due date: \(dueDateString)")
                        continue
                    }
                    dueDate = parsedDate
                }
                
                // Update the reminder
                let success = await eventKitManager.updateReminder(id: reminderId, title: newTitle, dueDate: dueDate, notes: notes, listName: listName)
                
                if success {
                    print("Successfully updated reminder: \(newTitle)")
                } else {
                    print("Failed to update reminder: \(newTitle)")
                }
            }
        }
        
        // Process reminder delete commands
        let reminderDeletePattern = "\\[REMINDER_DELETE\\] (.*?)$"
        if let regex = try? NSRegularExpression(pattern: reminderDeletePattern, options: .anchorsMatchLines) {
            let matches = regex.matches(in: response, range: NSRange(response.startIndex..., in: response))
            
            for match in matches {
                let reminderId = String(response[Range(match.range(at: 1), in: response)!])
                
                // Delete the reminder
                let success = await eventKitManager.deleteReminder(id: reminderId)
                
                if success {
                    print("Successfully deleted reminder with ID: \(reminderId)")
                } else {
                    print("Failed to delete reminder with ID: \(reminderId)")
                }
            }
        }
    }
}
