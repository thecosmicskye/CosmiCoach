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
    9. Keep important information in the memory file so you can reference it in future conversations

    To modify calendar or reminders, use the following format:
    [CALENDAR_ADD] Title | Start time | End time | Notes (optional)
    [CALENDAR_MODIFY] Event ID | New title | New start time | New end time | New notes (optional)
    [CALENDAR_DELETE] Event ID

    [REMINDER_ADD] Title | Due date/time | Notes (optional)
    [REMINDER_MODIFY] Reminder ID | New title | New due date/time | New notes (optional)
    [REMINDER_DELETE] Reminder ID

    You have access to the user's memory file which contains information about them that persists between conversations. You should update this file when you learn important information about the user, their preferences, or patterns you observe. 
    
    To update the memory file, use the following format:
    [MEMORY_UPDATE]
    +This line will be added to the memory file
    -This line will be removed from the memory file
    [/MEMORY_UPDATE]
    
    Be careful not to remove too much content at once. Focus on adding new information or updating specific sections. The memory file content is visible at the top of each conversation under USER MEMORY.
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
            
            // Initialize accumulated complete response and streaming message
            var completeResponse = ""
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
                        
                        // Append to the complete response
                        completeResponse += contentItems
                        
                        // Update the UI
                        await MainActor.run {
                            updateStreamingMessage(content: completeResponse)
                        }
                    }
                }
            }
            
            // Process the response for any calendar, reminder, or memory modifications
            await processClaudeResponse(completeResponse)
            
            // Look for memory update patterns and apply them
            await processMemoryUpdates(completeResponse)
            
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
        
        // Look for memory update commands in the format:
        // [MEMORY_UPDATE]
        // +Added line
        // -Removed line
        // [/MEMORY_UPDATE]
        
        let memoryUpdatePattern = "\\[MEMORY_UPDATE\\]([\\s\\S]*?)\\[\\/MEMORY_UPDATE\\]"
        if let regex = try? NSRegularExpression(pattern: memoryUpdatePattern, options: []) {
            let matches = regex.matches(in: response, range: NSRange(response.startIndex..., in: response))
            
            for match in matches {
                if let updateRange = Range(match.range(at: 1), in: response) {
                    let diffContent = String(response[updateRange])
                    print("Found memory update instruction: \(diffContent.count) characters")
                    
                    // Apply the diff to the memory file
                    let success = await memManager.applyDiff(diff: diffContent.trimmingCharacters(in: .whitespacesAndNewlines))
                    
                    if success {
                        print("Successfully updated memory file")
                    } else {
                        print("Failed to update memory file")
                    }
                }
            }
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
        let reminderAddPattern = "\\[REMINDER_ADD\\] (.*?) \\| (.*?)( \\| (.*?))?$"
        if let regex = try? NSRegularExpression(pattern: reminderAddPattern, options: .anchorsMatchLines) {
            let matches = regex.matches(in: response, range: NSRange(response.startIndex..., in: response))
            
            for match in matches {
                let title = response[Range(match.range(at: 1), in: response)!]
                let dueDateString = String(response[Range(match.range(at: 2), in: response)!])
                let notes = match.range(at: 4).location != NSNotFound ? String(response[Range(match.range(at: 4), in: response)!]) : nil
                
                // Parse due date
                guard let dueDate = dateFormatter.date(from: dueDateString) else {
                    print("Error parsing due date: \(dueDateString)")
                    continue
                }
                
                // Add the reminder
                let success = await MainActor.run {
                    return eventKitManager.addReminder(title: String(title), dueDate: dueDate, notes: notes)
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
        let reminderModifyPattern = "\\[REMINDER_MODIFY\\] (.*?) \\| (.*?) \\| (.*?)( \\| (.*?))?$"
        if let regex = try? NSRegularExpression(pattern: reminderModifyPattern, options: .anchorsMatchLines) {
            let matches = regex.matches(in: response, range: NSRange(response.startIndex..., in: response))
            
            for match in matches {
                let reminderId = String(response[Range(match.range(at: 1), in: response)!])
                let newTitle = String(response[Range(match.range(at: 2), in: response)!])
                let dueDateString = String(response[Range(match.range(at: 3), in: response)!])
                let notes = match.range(at: 5).location != NSNotFound ? String(response[Range(match.range(at: 5), in: response)!]) : nil
                
                // Parse due date
                guard let dueDate = dateFormatter.date(from: dueDateString) else {
                    print("Error parsing due date: \(dueDateString)")
                    continue
                }
                
                // Update the reminder
                let success = await eventKitManager.updateReminder(id: reminderId, title: newTitle, dueDate: dueDate, notes: notes)
                
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
