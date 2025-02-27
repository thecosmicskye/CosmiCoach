import Foundation
import Combine

// Models for JSON-based command parsing
// Calendar Commands
struct CalendarAddCommand: Decodable {
    let title: String
    let start: String
    let end: String
    let notes: String?
}

struct CalendarModifyCommand: Decodable {
    let id: String
    let title: String?
    let start: String?
    let end: String?
    let notes: String?
}

struct CalendarDeleteCommand: Decodable {
    let id: String
}

// Reminder Commands
struct ReminderAddCommand: Decodable {
    let title: String
    let due: String?
    let notes: String?
    let list: String?
}

struct ReminderModifyCommand: Decodable {
    let id: String
    let title: String?
    let due: String?
    let notes: String?
    let list: String?
}

struct ReminderDeleteCommand: Decodable {
    let id: String
}

// Memory Commands
struct MemoryAddCommand: Decodable {
    let content: String
    let category: String
    let importance: Int?
}

struct MemoryRemoveCommand: Decodable {
    let content: String
}

class ChatManager: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isProcessing = false
    @Published var currentStreamingMessageId: UUID?
    @Published var streamingUpdateCount: Int = 0  // Track streaming updates for scrolling
    @Published var operationStatusMessages: [UUID: [OperationStatusMessage]] = [:]  // Maps message IDs to their operation status messages
    
    private var apiKey: String {
        return UserDefaults.standard.string(forKey: "claude_api_key") ?? ""
    }
    private let maxTokens = 75000
    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let streamingURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private var memoryManager: MemoryManager?
    private var eventKitManager: EventKitManager?
    private var locationManager: LocationManager?
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
    10. When location information is provided, use it for context, but only mention it when relevant
        - For example, if the user said they're commuting and you see they're at a transit hub, you can acknowledge they're on track
        - Don't explicitly comment on location unless it's helpful in context

    To modify calendar or reminders, use the following JSON format:

    [CALENDAR_ADD]
    {
      "title": "Meeting with Doctor",     // REQUIRED
      "start": "Mar 15, 2025 at 2:00 PM", // REQUIRED
      "end": "Mar 15, 2025 at 3:00 PM",   // REQUIRED
      "notes": "Discuss medication options" // OPTIONAL
    }
    [/CALENDAR_ADD]

    [CALENDAR_MODIFY]
    {
      "id": "EVENT-ID-123",              // REQUIRED
      "title": "Updated Meeting Title",   // OPTIONAL
      "start": "Mar 16, 2025 at 3:00 PM", // OPTIONAL
      "end": "Mar 16, 2025 at 4:00 PM",   // OPTIONAL
      "notes": "New meeting notes"        // OPTIONAL
    }
    [/CALENDAR_MODIFY]

    [CALENDAR_DELETE]
    {
      "id": "EVENT-ID-123"  // REQUIRED
    }
    [/CALENDAR_DELETE]

    [REMINDER_ADD]
    {
      "title": "Call doctor",             // REQUIRED
      "due": "Mar 15, 2025 at 2:00 PM",   // OPTIONAL
      "notes": "Schedule appointment",     // OPTIONAL
      "list": "Personal"                  // OPTIONAL
    }
    [/REMINDER_ADD]

    [REMINDER_MODIFY]
    {
      "id": "REMINDER-ID-123",           // REQUIRED
      "title": "Updated reminder title",  // OPTIONAL
      "due": "Mar 16, 2025 at 3:00 PM",   // OPTIONAL
      "notes": "Updated notes",           // OPTIONAL
      "list": "Work"                      // OPTIONAL
    }
    [/REMINDER_MODIFY]

    [REMINDER_DELETE]
    {
      "id": "REMINDER-ID-123"  // REQUIRED
    }
    [/REMINDER_DELETE]

    Examples:
    - To add a reminder without a due date: Use "due": null or omit the "due" field
    - To modify only specific fields: Only include the fields you want to change

    You have access to the user's memory which contains information about them that persists between conversations. This information is organized into categories:
    - Personal Information: Basic information about the user
    - Preferences: User preferences and likes/dislikes
    - Behavior Patterns: Patterns in user behavior and task completion
    - Daily Basics: Tracking of daily basics like eating and drinking water
    - Medications: Medication information and tracking
    - Goals: Short and long-term goals
    - Miscellaneous Notes: Other information to remember

    To add or update memories, use the following JSON format:
    [MEMORY_ADD]
    {
      "content": "User takes 20mg Adderall at 8am daily", // REQUIRED
      "category": "Medications",                          // REQUIRED
      "importance": 5                                     // OPTIONAL (default: 3)
    }
    [/MEMORY_ADD]
    
    Examples:
    [MEMORY_ADD]
    {
      "content": "User prefers short, direct answers",
      "category": "Preferences",
      "importance": 4
    }
    [/MEMORY_ADD]
    
    [MEMORY_ADD]
    {
      "content": "User struggles with morning routines",
      "category": "Behavior Patterns",
      "importance": 3
    }
    [/MEMORY_ADD]
    
    To remove outdated memories:
    [MEMORY_REMOVE]
    {
      "content": "Exact content to match and remove"  // REQUIRED
    }
    [/MEMORY_REMOVE]
    
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
        print("⏱️ ChatManager initializing")
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
        print("⏱️ ChatManager initialized - lastAppOpenTime set to: \(lastAppOpenTime!)")
        
        // Check automatic message settings
        let automaticMessagesEnabled = UserDefaults.standard.bool(forKey: "enable_automatic_responses")
        print("⏱️ ChatManager init - Automatic messages enabled: \(automaticMessagesEnabled)")
        
        // Check the API key availability
        let hasApiKey = !apiKey.isEmpty
        print("⏱️ ChatManager init - API key available: \(hasApiKey)")
        
        // Set a default value for automatic messages if not already set
        if UserDefaults.standard.object(forKey: "enable_automatic_responses") == nil {
            print("⏱️ ChatManager init - Setting default value for enable_automatic_responses to TRUE")
            UserDefaults.standard.set(true, forKey: "enable_automatic_responses")
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
    
    func setLocationManager(_ manager: LocationManager) {
        self.locationManager = manager
    }
    
    func getLastAppOpenTime() -> Date? {
        return lastAppOpenTime
    }
    
    @MainActor
    func checkAndSendAutomaticMessage() async {
        print("⏱️ AUTOMATIC MESSAGE CHECK START - \(Date())")
        
        // Check if automatic messages are enabled in settings
        let automaticMessagesEnabled = UserDefaults.standard.bool(forKey: "enable_automatic_responses")
        print("⏱️ Automatic messages enabled in settings: \(automaticMessagesEnabled)")
        guard automaticMessagesEnabled else {
            print("⏱️ Automatic message skipped: Automatic messages are disabled in settings")
            return
        }
        
        // Check if we have the API key
        let hasApiKey = !apiKey.isEmpty
        print("⏱️ API key available: \(hasApiKey)")
        guard hasApiKey else {
            print("⏱️ Automatic message skipped: No API key available")
            return
        }
        
        // Always update lastAppOpenTime to ensure background->active transitions work properly
        lastAppOpenTime = Date()
        print("⏱️ Updated lastAppOpenTime to current time: \(lastAppOpenTime!)")
        
        // Check if the app hasn't been opened for at least 5 minutes (temporarily changed from 5 minutes)
        let lastSessionKey = "last_app_session_time"
        
        // Always store current time when checking - this fixes the bug where
        // closing the app without fully terminating doesn't update the session time
        let currentTime = Date().timeIntervalSince1970
        print("⏱️ Current time: \(Date(timeIntervalSince1970: currentTime))")
        
        // IMPORTANT: Get the current store time BEFORE updating it
        var timeSinceLastSession: TimeInterval = 999999 // Default to a large value to ensure we run
        
        if let lastSessionTimeInterval = UserDefaults.standard.object(forKey: lastSessionKey) as? TimeInterval {
            let lastSessionTime = Date(timeIntervalSince1970: lastSessionTimeInterval)
            timeSinceLastSession = Date().timeIntervalSince(lastSessionTime)
            
            print("⏱️ Last session time: \(lastSessionTime)")
            print("⏱️ Time since last session: \(timeSinceLastSession) seconds")
        } else {
            print("⏱️ No previous session time found in UserDefaults")
        }
        
        // Store current session time for future reference
        UserDefaults.standard.set(currentTime, forKey: lastSessionKey)
        UserDefaults.standard.synchronize() // Force synchronize to ensure it's saved
        print("⏱️ Updated session timestamp in UserDefaults: \(Date(timeIntervalSince1970: currentTime))")
        
        // Check if app was opened less than 5 minutes ago
        if timeSinceLastSession < 300 { // 300 seconds = 5 minutes
            print("⏱️ Automatic message skipped: App was opened less than 5 minutes ago (timeSinceLastSession = \(timeSinceLastSession))")
            return
        }
        
        // If we get here, all conditions are met - send the automatic message
        print("⏱️ All conditions met - sending automatic message")
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
        
        // Save operation status messages
        if let encoded = try? JSONEncoder().encode(operationStatusMessages) {
            UserDefaults.standard.set(encoded, forKey: "operation_status_messages")
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
        
        // Load operation status messages
        if let data = UserDefaults.standard.data(forKey: "operation_status_messages"),
           let decoded = try? JSONDecoder().decode([UUID: [OperationStatusMessage]].self, from: data) {
            operationStatusMessages = decoded
        }
    }
    
    // MARK: - Operation Status Methods
    
    /// Returns all operation status messages associated with a specific chat message
    @MainActor
    func statusMessagesForMessage(_ message: ChatMessage) -> [OperationStatusMessage] {
        return operationStatusMessages[message.id] ?? []
    }
    
    /// Adds a new operation status message for a specific chat message
    @MainActor
    func addOperationStatusMessage(forMessageId messageId: UUID, operationType: String, status: OperationStatus = .inProgress, details: String? = nil) -> OperationStatusMessage {
        let statusMessage = OperationStatusMessage(
            operationType: operationType,
            status: status,
            details: details
        )
        
        // Initialize the array if it doesn't exist
        if operationStatusMessages[messageId] == nil {
            operationStatusMessages[messageId] = []
        }
        
        // Add the status message
        operationStatusMessages[messageId]?.append(statusMessage)
        
        // Save to persistence
        saveMessages()
        
        return statusMessage
    }
    
    /// Updates an existing operation status message
    @MainActor
    func updateOperationStatusMessage(forMessageId messageId: UUID, statusMessageId: UUID, status: OperationStatus, details: String? = nil) {
        // Find the status message
        if var statusMessages = operationStatusMessages[messageId],
           let index = statusMessages.firstIndex(where: { $0.id == statusMessageId }) {
            // Update the status
            statusMessages[index].status = status
            
            // Update details if provided
            if let details = details {
                statusMessages[index].details = details
            }
            
            // Save the updated array
            operationStatusMessages[messageId] = statusMessages
            
            // Save to persistence
            saveMessages()
        }
    }
    
    /// Removes an operation status message
    @MainActor
    func removeOperationStatusMessage(forMessageId messageId: UUID, statusMessageId: UUID) {
        // Find and remove the status message
        if var statusMessages = operationStatusMessages[messageId] {
            statusMessages.removeAll(where: { $0.id == statusMessageId })
            
            // Update the array or remove it if empty
            if statusMessages.isEmpty {
                operationStatusMessages.removeValue(forKey: messageId)
            } else {
                operationStatusMessages[messageId] = statusMessages
            }
            
            // Save to persistence
            saveMessages()
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
        
        // Get location information if enabled
        let locationContext = await getLocationContext()
        
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
                    
                    \(locationContext)
                    
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
    
    private func getLocationContext() async -> String {
        let enableLocationAwareness = UserDefaults.standard.bool(forKey: "enable_location_awareness")
        print("📍 getLocationContext - Location awareness enabled: \(enableLocationAwareness)")
        
        guard enableLocationAwareness else {
            print("📍 getLocationContext - Location awareness feature is disabled")
            return ""
        }
        
        guard let locationManager = await MainActor.run(body: { [weak self] in self?.locationManager }) else {
            print("📍 getLocationContext - LocationManager is nil")
            return ""
        }
        
        let accessGranted = await MainActor.run(body: { locationManager.locationAccessGranted })
        print("📍 getLocationContext - Location access granted: \(accessGranted)")
        
        guard accessGranted else {
            print("📍 getLocationContext - Location permission not granted")
            return ""
        }
        
        let location = await MainActor.run(body: { locationManager.currentLocation })
        print("📍 getLocationContext - Current location: \(String(describing: location))")
        
        guard let location = location else {
            print("📍 getLocationContext - No location data available")
            return ""
        }
        
        // Ensure we have a description
        if let locationDescription = await MainActor.run(body: { locationManager.locationDescription }) {
            print("📍 getLocationContext - Using location description: \(locationDescription)")
            return """
            USER LOCATION:
            \(locationDescription)
            """
        } else {
            // Fallback to coordinates if description isn't available
            let locationText = "Coordinates: \(location.coordinate.latitude), \(location.coordinate.longitude)"
            print("📍 getLocationContext - Using location coordinates: \(locationText)")
            return """
            USER LOCATION:
            \(locationText)
            """
        }
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
        print("⏱️ SENDING AUTOMATIC MESSAGE - \(isAfterHistoryDeletion ? "After history deletion" : "After app open")")
        
        // Get context data
        let calendarEvents = eventKitManager?.fetchUpcomingEvents(days: 7) ?? []
        print("⏱️ Retrieved \(calendarEvents.count) calendar events for automatic message")
        
        let reminders = await eventKitManager?.fetchReminders() ?? []
        print("⏱️ Retrieved \(reminders.count) reminders for automatic message")
        
        // Prepare context for Claude
        var memoryContent = "No memory available."
        if let manager = memoryManager {
            memoryContent = await manager.readMemory()
            print("⏱️ Memory content loaded for automatic message. Length: \(memoryContent.count)")
        } else {
            print("⏱️ WARNING: Memory manager not available for automatic message")
        }
        
        // Format calendar events and reminders for context
        let calendarContext = formatCalendarEvents(calendarEvents)
        let remindersContext = formatReminders(reminders)
        
        // Get location information if enabled
        let locationContext = await getLocationContext()
        
        // Get recent conversation history
        let conversationHistory = await MainActor.run {
            return getRecentConversationHistory()
        }
        print("⏱️ Got conversation history for automatic message. Length: \(conversationHistory.count)")
        
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
                    
                    \(locationContext)
                    
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
            print("⏱️ Set isProcessing to true for automatic message")
        }
        
        // Create the request
        var request = URLRequest(url: streamingURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            print("⏱️ Prepared request body for automatic message")
            
            // Initialize streaming message
            await MainActor.run {
                currentStreamingMessage = ""
                addAssistantMessage(content: "", isComplete: false)
                print("⏱️ Added empty assistant message for streaming")
            }
            
            print("⏱️ Sending automatic message request to Claude API...")
            // Handle the streaming response like normal
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                await MainActor.run {
                    self.finalizeStreamingMessage()
                    self.isProcessing = false
                }
                print("⏱️ Automatic message error: Invalid HTTP response")
                return
            }
            
            print("⏱️ Received response from Claude API with status code: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode != 200 {
                await MainActor.run {
                    self.finalizeStreamingMessage()
                    self.isProcessing = false
                }
                print("⏱️ Automatic message HTTP error: \(httpResponse.statusCode)")
                return
            }
            
            // Track the full response for post-processing
            var fullResponse = ""
            print("⏱️ Beginning to process streaming response for automatic message")
            
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
                    print("⏱️ Received [DONE] event, stream complete")
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
            
            print("⏱️ Automatic message streaming complete, processing response actions")
            // Process the response like normal
            await processClaudeResponse(fullResponse)
            await processMemoryUpdates(fullResponse)
            
            // Finalize the assistant message
            await MainActor.run {
                finalizeStreamingMessage()
                isProcessing = false
                print("⏱️ Automatic message complete and finalized")
            }
            
        } catch {
            print("⏱️ Automatic message error: \(error.localizedDescription)")
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
    
    // Function to test an API key passed in as parameter
    func testAPIKey(_ key: String) async -> Bool {
        // Create a simple request to test the API key
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        // Use the provided API key
        request.addValue(key, forHTTPHeaderField: "x-api-key")
        
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
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            print("API key test error: \(error.localizedDescription)")
            return false
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
        
        // Create a JSON decoder
        let decoder = JSONDecoder()
        
        // Process CALENDAR_ADD commands
        let calendarAddPattern = "\\[CALENDAR_ADD\\]\\s*(\\{[\\s\\S]*?\\})\\s*\\[\\/CALENDAR_ADD\\]"
        if let regex = try? NSRegularExpression(pattern: calendarAddPattern, options: []) {
            let matches = regex.matches(in: response, range: NSRange(response.startIndex..., in: response))
            
            for match in matches {
                if let jsonRange = Range(match.range(at: 1), in: response) {
                    let jsonString = String(response[jsonRange])
                    
                    do {
                        let command = try decoder.decode(CalendarAddCommand.self, from: jsonString.data(using: .utf8)!)
                        
                        // Parse dates
                        guard let startDate = dateFormatter.date(from: command.start) else {
                            print("Error parsing start date: \(command.start)")
                            continue
                        }
                        
                        guard let endDate = dateFormatter.date(from: command.end) else {
                            print("Error parsing end date: \(command.end)")
                            continue
                        }
                        
                        // Make copies of the variables to avoid capturing them in the closure
                        let startDateCopy = startDate
                        let endDateCopy = endDate
                        let notesCopy = command.notes
                        let titleCopy = command.title
                        
                        // Add the calendar event
                        let success = await MainActor.run {
                            // Get the ID of the current message being processed
                            let messageId = self.messages.last?.id
                            
                            return eventKitManager.addCalendarEvent(
                                title: titleCopy,
                                startDate: startDateCopy,
                                endDate: endDateCopy,
                                notes: notesCopy,
                                messageId: messageId,
                                chatManager: self
                            )
                        }
                        
                        if success {
                            print("📅 ChatManager: Successfully added calendar event - \(command.title)")
                        } else {
                            print("📅 ChatManager: Failed to add calendar event - \(command.title)")
                        }
                    } catch {
                        print("Error decoding calendar add command: \(error)")
                    }
                }
            }
        }
        
        // Process CALENDAR_MODIFY commands
        let calendarModifyPattern = "\\[CALENDAR_MODIFY\\]\\s*(\\{[\\s\\S]*?\\})\\s*\\[\\/CALENDAR_MODIFY\\]"
        if let regex = try? NSRegularExpression(pattern: calendarModifyPattern, options: []) {
            let matches = regex.matches(in: response, range: NSRange(response.startIndex..., in: response))
            
            for match in matches {
                if let jsonRange = Range(match.range(at: 1), in: response) {
                    let jsonString = String(response[jsonRange])
                    
                    do {
                        let command = try decoder.decode(CalendarModifyCommand.self, from: jsonString.data(using: .utf8)!)
                        
                        // Parse dates if provided
                        var startDate: Date? = nil
                        if let startString = command.start {
                            guard let parsedDate = dateFormatter.date(from: startString) else {
                                print("Error parsing start date: \(startString)")
                                continue
                            }
                            startDate = parsedDate
                        }
                        
                        var endDate: Date? = nil
                        if let endString = command.end {
                            guard let parsedDate = dateFormatter.date(from: endString) else {
                                print("Error parsing end date: \(endString)")
                                continue
                            }
                            endDate = parsedDate
                        }
                        
                        // Make copies of the variables to avoid capturing them in the closure
                        let startDateCopy = startDate
                        let endDateCopy = endDate
                        let idCopy = command.id
                        let titleCopy = command.title
                        let notesCopy = command.notes
                        
                        // Update the calendar event
                        let success = await MainActor.run {
                            // Get the ID of the current message being processed
                            let messageId = self.messages.last?.id
                            
                            return eventKitManager.updateCalendarEvent(
                                id: idCopy,
                                title: titleCopy,
                                startDate: startDateCopy,
                                endDate: endDateCopy,
                                notes: notesCopy,
                                messageId: messageId,
                                chatManager: self
                            )
                        }
                        
                        if success {
                            print("📅 ChatManager: Successfully updated calendar event with ID - \(command.id)")
                        } else {
                            print("📅 ChatManager: Failed to update calendar event with ID - \(command.id)")
                        }
                    } catch {
                        print("Error decoding calendar modify command: \(error)")
                    }
                }
            }
        }
        
        // Process CALENDAR_DELETE commands
        let calendarDeletePattern = "\\[CALENDAR_DELETE\\]\\s*(\\{[\\s\\S]*?\\})\\s*\\[\\/CALENDAR_DELETE\\]"
        if let regex = try? NSRegularExpression(pattern: calendarDeletePattern, options: []) {
            let matches = regex.matches(in: response, range: NSRange(response.startIndex..., in: response))
            
            for match in matches {
                if let jsonRange = Range(match.range(at: 1), in: response) {
                    let jsonString = String(response[jsonRange])
                    
                    do {
                        let command = try decoder.decode(CalendarDeleteCommand.self, from: jsonString.data(using: .utf8)!)
                        
                        // Make a copy of the ID to avoid capturing it in the closure
                        let idCopy = command.id
                        
                        // Delete the calendar event
                        let success = await MainActor.run {
                            // Get the ID of the current message being processed
                            let messageId = self.messages.last?.id
                            
                            return eventKitManager.deleteCalendarEvent(
                                id: idCopy,
                                messageId: messageId,
                                chatManager: self
                            )
                        }
                        
                        if success {
                            print("📅 ChatManager: Successfully deleted calendar event with ID - \(command.id)")
                        } else {
                            print("📅 ChatManager: Failed to delete calendar event with ID - \(command.id)")
                        }
                    } catch {
                        print("Error decoding calendar delete command: \(error)")
                    }
                }
            }
        }
        
        // Process REMINDER_ADD commands
        let reminderAddPattern = "\\[REMINDER_ADD\\]\\s*(\\{[\\s\\S]*?\\})\\s*\\[\\/REMINDER_ADD\\]"
        if let regex = try? NSRegularExpression(pattern: reminderAddPattern, options: []) {
            let matches = regex.matches(in: response, range: NSRange(response.startIndex..., in: response))
            
            for match in matches {
                if let jsonRange = Range(match.range(at: 1), in: response) {
                    let jsonString = String(response[jsonRange])
                    
                    do {
                        let command = try decoder.decode(ReminderAddCommand.self, from: jsonString.data(using: .utf8)!)
                        
                        // Parse due date if provided
                        var dueDate: Date? = nil
                        if let dueString = command.due {
                            if dueString.lowercased() == "null" || dueString.lowercased() == "no due date" {
                                dueDate = nil
                            } else {
                                guard let parsedDate = dateFormatter.date(from: dueString) else {
                                    print("Error parsing due date: \(dueString)")
                                    continue
                                }
                                dueDate = parsedDate
                            }
                        }
                        
                        // Make copies of the variables to avoid capturing them in the closure
                        let dueDateCopy = dueDate
                        let titleCopy = command.title
                        let notesCopy = command.notes
                        let listCopy = command.list
                        
                        // Add the reminder
                        let success = await MainActor.run {
                            // Get the ID of the current message being processed
                            let messageId = self.messages.last?.id
                            
                            return eventKitManager.addReminder(
                                title: titleCopy,
                                dueDate: dueDateCopy,
                                notes: notesCopy,
                                listName: listCopy,
                                messageId: messageId,
                                chatManager: self
                            )
                        }
                        
                        if success {
                            print("📅 ChatManager: Successfully added reminder - \(command.title)")
                        } else {
                            print("📅 ChatManager: Failed to add reminder - \(command.title)")
                        }
                    } catch {
                        print("Error decoding reminder add command: \(error)")
                    }
                }
            }
        }
        
        // Process REMINDER_MODIFY commands
        let reminderModifyPattern = "\\[REMINDER_MODIFY\\]\\s*(\\{[\\s\\S]*?\\})\\s*\\[\\/REMINDER_MODIFY\\]"
        if let regex = try? NSRegularExpression(pattern: reminderModifyPattern, options: []) {
            let matches = regex.matches(in: response, range: NSRange(response.startIndex..., in: response))
            
            for match in matches {
                if let jsonRange = Range(match.range(at: 1), in: response) {
                    let jsonString = String(response[jsonRange])
                    
                    do {
                        let command = try decoder.decode(ReminderModifyCommand.self, from: jsonString.data(using: .utf8)!)
                        
                        // Parse due date if provided
                        var dueDate: Date? = nil
                        if let dueString = command.due {
                            if dueString.lowercased() == "null" || dueString.lowercased() == "no due date" {
                                dueDate = nil
                            } else {
                                guard let parsedDate = dateFormatter.date(from: dueString) else {
                                    print("Error parsing due date: \(dueString)")
                                    continue
                                }
                                dueDate = parsedDate
                            }
                        }
                        
                        // Make copies of the variables to avoid capturing them in the closure
                        let dueDateCopy = dueDate
                        let idCopy = command.id
                        let titleCopy = command.title
                        let notesCopy = command.notes
                        let listCopy = command.list
                        
                        // Update the reminder
                        let success = await MainActor.run {
                            // Get the ID of the current message being processed
                            let messageId = self.messages.last?.id
                            
                            return eventKitManager.updateReminder(
                                id: idCopy,
                                title: titleCopy,
                                dueDate: dueDateCopy,
                                notes: notesCopy,
                                listName: listCopy,
                                messageId: messageId,
                                chatManager: self
                            )
                        }
                        
                        if success {
                            print("📅 ChatManager: Successfully updated reminder with ID - \(command.id)")
                        } else {
                            print("📅 ChatManager: Failed to update reminder with ID - \(command.id)")
                        }
                    } catch {
                        print("Error decoding reminder modify command: \(error)")
                    }
                }
            }
        }
        
        // Process REMINDER_DELETE commands
        let reminderDeletePattern = "\\[REMINDER_DELETE\\]\\s*(\\{[\\s\\S]*?\\})\\s*\\[\\/REMINDER_DELETE\\]"
        if let regex = try? NSRegularExpression(pattern: reminderDeletePattern, options: []) {
            let matches = regex.matches(in: response, range: NSRange(response.startIndex..., in: response))
            
            for match in matches {
                if let jsonRange = Range(match.range(at: 1), in: response) {
                    let jsonString = String(response[jsonRange])
                    
                    do {
                        let command = try decoder.decode(ReminderDeleteCommand.self, from: jsonString.data(using: .utf8)!)
                        
                        // Make a copy of the ID to avoid capturing it in the closure
                        let idCopy = command.id
                        
                        // Delete the reminder
                        let success = await MainActor.run {
                            // Get the ID of the current message being processed
                            let messageId = self.messages.last?.id
                            
                            return eventKitManager.deleteReminder(
                                id: idCopy,
                                messageId: messageId,
                                chatManager: self
                            )
                        }
                        
                        if success {
                            print("📅 ChatManager: Successfully deleted reminder with ID - \(command.id)")
                        } else {
                            print("📅 ChatManager: Failed to delete reminder with ID - \(command.id)")
                        }
                    } catch {
                        print("Error decoding reminder delete command: \(error)")
                    }
                }
            }
        }
        
        // Process MEMORY_ADD commands
        let memoryAddPattern = "\\[MEMORY_ADD\\]\\s*(\\{[\\s\\S]*?\\})\\s*\\[\\/MEMORY_ADD\\]"
        if let regex = try? NSRegularExpression(pattern: memoryAddPattern, options: []) {
            let matches = regex.matches(in: response, range: NSRange(response.startIndex..., in: response))
            
            for match in matches {
                if let jsonRange = Range(match.range(at: 1), in: response) {
                    let jsonString = String(response[jsonRange])
                    
                    do {
                        let command = try decoder.decode(MemoryAddCommand.self, from: jsonString.data(using: .utf8)!)
                        
                        // Process memory add command
                        // This will be handled by the memoryManager.processMemoryInstructions method
                        // We don't need to do anything here as it's already processed in processMemoryUpdates
                        print("📝 ChatManager: Found memory add command - \(command.content)")
                    } catch {
                        print("Error decoding memory add command: \(error)")
                    }
                }
            }
        }
        
        // Process MEMORY_REMOVE commands
        let memoryRemovePattern = "\\[MEMORY_REMOVE\\]\\s*(\\{[\\s\\S]*?\\})\\s*\\[\\/MEMORY_REMOVE\\]"
        if let regex = try? NSRegularExpression(pattern: memoryRemovePattern, options: []) {
            let matches = regex.matches(in: response, range: NSRange(response.startIndex..., in: response))
            
            for match in matches {
                if let jsonRange = Range(match.range(at: 1), in: response) {
                    let jsonString = String(response[jsonRange])
                    
                    do {
                        let command = try decoder.decode(MemoryRemoveCommand.self, from: jsonString.data(using: .utf8)!)
                        
                        // Process memory remove command
                        // This will be handled by the memoryManager.processMemoryInstructions method
                        // We don't need to do anything here as it's already processed in processMemoryUpdates
                        print("📝 ChatManager: Found memory remove command - \(command.content)")
                    } catch {
                        print("Error decoding memory remove command: \(error)")
                    }
                }
            }
        }
    }
}
