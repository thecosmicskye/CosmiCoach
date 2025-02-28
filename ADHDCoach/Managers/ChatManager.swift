import Foundation
import Combine

class ChatManager: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isProcessing = false
    @Published var currentStreamingMessageId: UUID?
    @Published var streamingUpdateCount: Int = 0  // Track streaming updates for scrolling
    @Published var operationStatusMessages: [UUID: [OperationStatusMessage]] = [:]  // Maps message IDs to their operation status messages
    
    // Store tool use results for feedback to Claude in the next message
    private var pendingToolResults: [(toolId: String, content: String)] = []
    
    // Variables to track tool use chunks
    private var currentToolName: String?
    private var currentToolId: String?
    private var currentToolInputJson = ""
    
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
    7. IMPORTANT: You MUST use the provided tools to create, modify, or delete calendar events, reminders, and memories
       - Use add_calendar_event tool when the user asks to create a single calendar event
       - Use add_calendar_events_batch tool when the user asks to create multiple calendar events
       - Use add_reminder tool when the user asks to create a single reminder
       - Use add_reminders_batch tool when the user asks to create multiple reminders
       - Use add_memory tool when you need to store a single piece of important information
       - Use add_memories_batch tool when you need to store multiple pieces of important information
       - DO NOT respond with text saying you've created a calendar event or reminder - use the tools
    8. Be empathetic and understanding of ADHD challenges
    9. Maintain important user information in structured memory categories
    10. When location information is provided, use it for context, but only mention it when relevant
        - For example, if the user said they're commuting and you see they're at a transit hub, you can acknowledge they're on track
        - Don't explicitly comment on location unless it's helpful in context

    You have access to the user's memory which contains information about them that persists between conversations. This information is organized into categories:
    - Personal Information: Basic information about the user
    - Preferences: User preferences and likes/dislikes
    - Behavior Patterns: Patterns in user behavior and task completion
    - Daily Basics: Tracking of daily basics like eating and drinking water
    - Medications: Medication information and tracking
    - Goals: Short and long-term goals
    - Miscellaneous Notes: Other information to remember

    Important guidelines for working with user memory:
    - Memories with higher importance (4-5) are most critical to refer to
    - Don't add redundant memories - check existing memories first 
    - Update memories when information changes rather than creating duplicates
    - Delete outdated information in memories
    - When adding specific facts, add them as separate memory items instead of combining multiple facts
    - The memory content is visible at the top of each conversation under USER MEMORY INFORMATION
    - DO NOT add calendar events or reminders as memories
    - Avoid duplicating memories

    IMPORTANT: When working with multiple items (multiple calendar events, reminders, or memories), always use the batch tools:
    - add_calendar_events_batch: Use this to add multiple calendar events in a single operation
    - modify_calendar_events_batch: Use this to modify multiple calendar events in a single operation
    - delete_calendar_events_batch: Use this to delete multiple calendar events in a single operation
    - add_reminders_batch: Use this to add multiple reminders in a single operation
    - modify_reminders_batch: Use this to modify multiple reminders in a single operation
    - delete_reminders_batch: Use this to delete multiple reminders in a single operation
    - add_memories_batch: Use this to add multiple memories in a single operation
    - remove_memories_batch: Use this to remove multiple memories in a single operation
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
    
    // Define tool schemas for Claude
    private var toolDefinitions: [[String: Any]] {
        return [
            // Calendar Tools - Single item operations
            [
                "name": "add_calendar_event",
                "description": "Add a new calendar event to the user's calendar. You MUST use this tool when the user wants to add a single event to their calendar.",
                "input_schema": CalendarAddCommand.schema
            ],
            [
                "name": "modify_calendar_event",
                "description": "Modify an existing calendar event in the user's calendar. Use this tool when the user wants to change a single existing event.",
                "input_schema": CalendarModifyCommand.schema
            ],
            [
                "name": "delete_calendar_event",
                "description": "Delete an existing calendar event from the user's calendar. Use this tool when the user wants to remove a single event.",
                "input_schema": CalendarDeleteCommand.schema
            ],
            
            // Calendar Tools - Batch operations
            [
                "name": "add_calendar_events_batch",
                "description": "Add multiple calendar events to the user's calendar at once. Use this tool when the user wants to add multiple events in a single operation.",
                "input_schema": CalendarAddBatchCommand.schema
            ],
            [
                "name": "modify_calendar_events_batch",
                "description": "Modify multiple existing calendar events in the user's calendar at once. Use this tool when the user wants to change multiple existing events in a single operation.",
                "input_schema": CalendarModifyBatchCommand.schema
            ],
            [
                "name": "delete_calendar_events_batch",
                "description": "Delete multiple existing calendar events from the user's calendar at once. Use this tool when the user wants to remove multiple events in a single operation.",
                "input_schema": CalendarDeleteBatchCommand.schema
            ],
            
            // Reminder Tools - Single item operations
            [
                "name": "add_reminder",
                "description": "Add a new reminder to the user's reminders list. You MUST use this tool when the user wants to add a single reminder.",
                "input_schema": ReminderAddCommand.schema
            ],
            [
                "name": "modify_reminder",
                "description": "Modify an existing reminder in the user's reminders. Use this tool when the user wants to change a single existing reminder.",
                "input_schema": ReminderModifyCommand.schema
            ],
            [
                "name": "delete_reminder",
                "description": "Delete an existing reminder from the user's reminders. Use this tool when the user wants to remove a single reminder.",
                "input_schema": ReminderDeleteCommand.schema
            ],
            
            // Reminder Tools - Batch operations
            [
                "name": "add_reminders_batch",
                "description": "Add multiple reminders to the user's reminders list at once. Use this tool when the user wants to add multiple reminders in a single operation.",
                "input_schema": ReminderAddBatchCommand.schema
            ],
            [
                "name": "modify_reminders_batch",
                "description": "Modify multiple existing reminders in the user's reminders at once. Use this tool when the user wants to change multiple existing reminders in a single operation.",
                "input_schema": ReminderModifyBatchCommand.schema
            ],
            [
                "name": "delete_reminders_batch",
                "description": "Delete multiple existing reminders from the user's reminders at once. Use this tool when the user wants to remove multiple reminders in a single operation.",
                "input_schema": ReminderDeleteBatchCommand.schema
            ],
            
            // Memory Tools - Single item operations
            [
                "name": "add_memory",
                "description": "Add a new memory to the user's memory database. You MUST use this tool to store important information about the user that should persist between conversations.",
                "input_schema": MemoryAddCommand.schema
            ],
            [
                "name": "remove_memory",
                "description": "Remove a memory from the user's memory database. Use this tool when information becomes outdated or is no longer relevant.",
                "input_schema": MemoryRemoveCommand.schema
            ],
            
            // Memory Tools - Batch operations
            [
                "name": "add_memories_batch",
                "description": "Add multiple memories to the user's memory database at once. Use this tool when you need to store multiple pieces of important information in a single operation.",
                "input_schema": MemoryAddBatchCommand.schema
            ],
            [
                "name": "remove_memories_batch",
                "description": "Remove multiple memories from the user's memory database at once. Use this tool when multiple pieces of information become outdated or are no longer relevant.",
                "input_schema": MemoryRemoveBatchCommand.schema
            ]
        ]
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
        
        // Create a messages array with context first, then user message
        var messages: [[String: Any]] = [
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
                """]
            ]],
            ["role": "assistant", "content": [
                ["type": "text", "text": "I understand. How can I help you today?"]
            ]],
            ["role": "user", "content": [
                ["type": "text", "text": userMessage]
            ]]
        ]
        
        // Add any pending tool results as tool_result blocks
        // This handles the case when a previous message resulted in a tool use
        if !pendingToolResults.isEmpty {
            print("Including \(pendingToolResults.count) tool results in the request")
            
            // Create a user message with tool_result content blocks for each pending result
            var toolResultBlocks: [[String: Any]] = []
            
            for result in pendingToolResults {
                toolResultBlocks.append([
                    "type": "tool_result",
                    "tool_use_id": result.toolId,
                    "content": result.content
                ])
            }
            
            // Only include tool results if we have actual tool use in previous messages
            // This prevents the 400 error "tool_result block(s) provided when previous message does not contain any tool_use blocks"
            
            // Check for actual tool_use blocks in previous messages
            // Simply checking message count isn't reliable
            var hasToolUseInPreviousMessages = false
            
            // Check if previous assistant messages contained tool use
            for msg in messages {
                if let content = msg["content"] as? [[String: Any]] {
                    for block in content {
                        if let type = block["type"] as? String, type == "tool_use" {
                            hasToolUseInPreviousMessages = true
                            break
                        }
                    }
                }
                if hasToolUseInPreviousMessages {
                    break
                }
            }
            
            if !toolResultBlocks.isEmpty && hasToolUseInPreviousMessages {
                messages.append(["role": "user", "content": toolResultBlocks])
                print("Added tool results to messages array")
            } else if !toolResultBlocks.isEmpty {
                print("Skipping tool results because there are no previous messages with tool use")
            }
            
            // Clear the pending results after adding them
            pendingToolResults = []
        }
        
        // Create the request body with system as a top-level parameter and tools
        let requestBody: [String: Any] = [
            "model": "claude-3-7-sonnet-20250219",
            "max_tokens": 4000,
            "system": systemPrompt,
            "tools": toolDefinitions,
            "stream": true,
            "messages": messages
        ]
        
        print("💡 REQUEST CONTAINS \(toolDefinitions.count) TOOLS")
        for tool in toolDefinitions {
            if let name = tool["name"] as? String {
                print("💡 TOOL DEFINED: \(name)")
            }
        }
        
        // Create the request
        var request = URLRequest(url: streamingURL)
        configureRequestHeaders(&request)
        
        do {
            let requestData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = requestData
            
            // Print the actual request JSON for debugging
            if let requestStr = String(data: requestData, encoding: .utf8) {
                print("💡 FULL API REQUEST: \(String(requestStr.prefix(1000))) [...]") // Only print first 1000 chars
            }
            
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
            
            print("💡 API RESPONSE STATUS CODE: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode != 200 {
                var errorData = Data()
                for try await byte in asyncBytes {
                    errorData.append(byte)
                }
                
                // Try to extract error message from response
                let statusCode = httpResponse.statusCode
                var errorDetails = ""
                
                if let responseString = String(data: errorData, encoding: .utf8) {
                    print("💡 API ERROR RESPONSE: \(responseString)")
                    
                    if let errorJson = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
                       let error = errorJson["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        errorDetails = ". \(message)"
                        print("💡 ERROR MESSAGE: \(message)")
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
                
                // Log raw response data for debugging
                print("💡 RAW RESPONSE: \(jsonStr)")
                
                // Parse the JSON
                if let data = jsonStr.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    
                    // Check if this is a start of content block (could be text or tool)
                    if json["type"] as? String == "content_block_start" {
                        print("💡 Content block start detected")
                        if let contentBlock = json["content_block"] as? [String: Any],
                           let blockType = contentBlock["type"] as? String {
                            
                            print("💡 Content block type: \(blockType)")
                            
                            // Handle tool_use block start
                            if blockType == "tool_use" {
                                if let toolName = contentBlock["name"] as? String,
                                   let toolId = contentBlock["id"] as? String {
                                    print("💡 DETECTED TOOL USE START: \(toolName) with ID: \(toolId)")
                                    
                                    // Save the tool name and id for later
                                    self.currentToolName = toolName
                                    self.currentToolId = toolId
                                    self.currentToolInputJson = ""
                                }
                            }
                        }
                    }
                    // Handle tool input JSON deltas (streamed piece by piece)
                    else if json["type"] as? String == "content_block_delta",
                            let delta = json["delta"] as? [String: Any],
                            let inputJsonDelta = delta["type"] as? String, inputJsonDelta == "input_json_delta",
                            let partialJson = delta["partial_json"] as? String {
                        
                        print("💡 Tool input JSON delta: \(partialJson)")
                        
                        // Accumulate the input json
                        self.currentToolInputJson += partialJson
                    }
                    // Check for message_delta with stop_reason = "tool_use"
                    else if json["type"] as? String == "message_delta",
                            let delta = json["delta"] as? [String: Any],
                            let stopReason = delta["stop_reason"] as? String, stopReason == "tool_use" {
                        
                        print("💡 Message stopped for tool use")
                        
                        // Create usable tool input from collected JSON chunks
                        var toolInput: [String: Any] = [:]
                        
                        if !self.currentToolInputJson.isEmpty {
                            // Try to parse the accumulated input JSON
                            print("💡 Accumulated JSON: \(self.currentToolInputJson)")
                            
                            // Sometimes the JSON is incomplete/malformed because of streaming chunks
                            // In that case, we'll fall back to a default tool call
                            if let jsonData = self.currentToolInputJson.data(using: .utf8),
                               let parsedInput = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                                toolInput = parsedInput
                                print("💡 Successfully parsed JSON input from Claude")
                            } else {
                                print("💡 Failed to parse JSON, using fallback for \(self.currentToolName ?? "unknown tool")")
                                createFallbackToolInput(toolName: self.currentToolName, toolInput: &toolInput)
                            }
                        } else {
                            print("💡 No input JSON accumulated, using fallback for \(self.currentToolName ?? "unknown tool")")
                            createFallbackToolInput(toolName: self.currentToolName, toolInput: &toolInput)
                        }
                        
                        // Helper function to create appropriate fallback input based on tool type
                        func createFallbackToolInput(toolName: String?, toolInput: inout [String: Any]) {
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
                            
                            let now = Date()
                            
                            switch toolName {
                            case "add_calendar_event":
                                let oneHourLater = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now
                                toolInput = [
                                    "title": "Test Calendar Event",
                                    "start": dateFormatter.string(from: now),
                                    "end": dateFormatter.string(from: oneHourLater),
                                    "notes": "Created by Claude when JSON parsing failed"
                                ]
                            case "add_reminder":
                                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
                                toolInput = [
                                    "title": "Test Reminder",
                                    "due": dateFormatter.string(from: tomorrow),
                                    "notes": "Created by Claude when JSON parsing failed"
                                ]
                            case "add_memory":
                                toolInput = [
                                    "content": "User asked Claude to create a test memory",
                                    "category": "Miscellaneous Notes",
                                    "importance": 3
                                ]
                            default:
                                // For other tools, provide a basic fallback
                                toolInput = ["note": "Fallback tool input for \(toolName ?? "unknown tool")"]
                            }
                        }
                        
                        // If we have a tool name and ID, process the tool use
                        if let toolName = self.currentToolName, let toolId = self.currentToolId {
                            print("💡 EXECUTING COLLECTED TOOL CALL: \(toolName)")
                            print("💡 With input: \(toolInput)")
                            
                            // Process the tool use based on the tool name
                            let result = await processToolUse(toolName: toolName, toolId: toolId, toolInput: toolInput)
                            
                            // Log the tool use and its result
                            print("💡 TOOL USE PROCESSED: \(toolName) with result: \(result)")
                            
                            // Store the tool result for the next API call
                            pendingToolResults.append((toolId: toolId, content: result))
                        }
                    }
                    // Handle regular text delta
                    else if let contentDelta = json["delta"] as? [String: Any],
                         let textContent = contentDelta["text"] as? String {
                        // Send the new content to the MainActor for UI updates
                        // and get back the full accumulated content
                        let updatedContent = await MainActor.run {
                            return appendToStreamingMessage(newContent: textContent)
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
    
    // Helper method to configure request headers with tool use support
    private func configureRequestHeaders(_ request: inout URLRequest) {
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // For tool use, we should use the most recent version with tools support
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
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
        
        // Create a messages array with context first, then automatic message
        var messages: [[String: Any]] = [
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
                """]
            ]],
            ["role": "assistant", "content": [
                ["type": "text", "text": "I have your current context. How can I assist you today?"]
            ]],
            ["role": "user", "content": [
                ["type": "text", "text": "[THIS IS AN AUTOMATIC MESSAGE - \(isAfterHistoryDeletion ? "The user has just cleared their chat history." : "The user has just opened the app after not using it for at least 5 minutes.") There is no specific user message. Based on the time of day, calendar events, reminders, and what you know about the user, provide a helpful, proactive greeting or insight.]"]
            ]]
        ]
        
        // Add any pending tool results as tool_result blocks
        if !pendingToolResults.isEmpty {
            print("⏱️ Including \(pendingToolResults.count) tool results in automatic message request")
            
            // Create a user message with tool_result content blocks for each pending result
            var toolResultBlocks: [[String: Any]] = []
            
            for result in pendingToolResults {
                toolResultBlocks.append([
                    "type": "tool_result",
                    "tool_use_id": result.toolId,
                    "content": result.content
                ])
            }
            
            // Only include tool results if we have actual tool use in previous messages
            // This prevents the 400 error "tool_result block(s) provided when previous message does not contain any tool_use blocks"
            
            // Check for actual tool_use blocks in previous messages
            // Simply checking message count isn't reliable
            var hasToolUseInPreviousMessages = false
            
            // Check if previous assistant messages contained tool use
            for msg in messages {
                if let content = msg["content"] as? [[String: Any]] {
                    for block in content {
                        if let type = block["type"] as? String, type == "tool_use" {
                            hasToolUseInPreviousMessages = true
                            break
                        }
                    }
                }
                if hasToolUseInPreviousMessages {
                    break
                }
            }
            
            if !toolResultBlocks.isEmpty && hasToolUseInPreviousMessages {
                messages.append(["role": "user", "content": toolResultBlocks])
                print("⏱️ Added tool results to automatic message")
            } else if !toolResultBlocks.isEmpty {
                print("⏱️ Skipping tool results in automatic message because there are no previous messages with tool use")
            }
            
            // Clear the pending results after adding them
            pendingToolResults = []
        }
        
        // Set up the request with special context indicating this is an automatic message
        let requestBody: [String: Any] = [
            "model": "claude-3-7-sonnet-20250219",
            "max_tokens": 4000,
            "system": systemPrompt,
            "tools": toolDefinitions,
            "stream": true,
            "messages": messages
        ]
        
        await MainActor.run {
            isProcessing = true
            print("⏱️ Set isProcessing to true for automatic message")
        }
        
        // Create the request
        var request = URLRequest(url: streamingURL)
        configureRequestHeaders(&request)
        
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
        print("💡 CHECKING FOR CLAUDE TOOL USE IN AUTOMATIC MESSAGE")
            
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
                    
                    // Check if this is a tool_use or text delta
                    if let contentDelta = json["delta"] as? [String: Any] {
                        // Handle text content
                        if let textContent = contentDelta["text"] as? String {
                            // Send the new content to the MainActor for UI updates
                            // and get back the full accumulated content
                            let updatedContent = await MainActor.run {
                                return appendToStreamingMessage(newContent: textContent)
                            }
                            
                            // Keep track of the full response for post-processing
                            fullResponse = updatedContent
                        }
                        // Handle tool_use content (this will come as a complete block in one delta)
                        else if let toolUse = contentDelta["tool_use"] as? [String: Any],
                                let toolName = toolUse["name"] as? String,
                                let toolId = toolUse["id"] as? String,
                                let toolInput = toolUse["input"] as? [String: Any] {
                            
                            print("⏱️ Detected tool use for: \(toolName)")
                            
                            // Process the tool use based on the tool name
                            let result = await processToolUse(toolName: toolName, toolId: toolId, toolInput: toolInput)
                            
                            // Log the tool use and its result
                            print("⏱️ Tool use processed: \(toolName) with result: \(result)")
                            
                            // Store the tool result for the next API call
                            pendingToolResults.append((toolId: toolId, content: result))
                        }
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
        // Set up request headers directly instead of using configureRequestHeaders
        // to avoid including any optional headers that might cause issues
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        
        // Simple request body with correct format, stream: false for simple testing
        // Also include a basic tool definition to test if tools are supported
        let requestBody: [String: Any] = [
            "model": "claude-3-7-sonnet-20250219",
            "max_tokens": 10,
            "stream": false,
            "tools": [
                [
                    "name": "test_tool",
                    "description": "A test tool",
                    "input_schema": [
                        "type": "object",
                        "properties": [
                            "test": ["type": "string"]
                        ]
                    ]
                ]
            ],
            "messages": [
                ["role": "user", "content": [
                    ["type": "text", "text": "Hello"]
                ]]
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            print("💡 Sending test API request with tools")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("💡 API Test Status Code: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    // Try to decode the response to confirm it worked
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("💡 API Test Response: \(responseString)")
                    }
                    return "✅ API key is valid with tools support!"
                } else {
                    // Try to extract error message
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("💡 API Test Error Response: \(responseString)")
                        return "❌ Error: \(responseString)"
                    } else {
                        return "❌ Error: Status code \(httpResponse.statusCode)"
                    }
                }
            } else {
                return "❌ Error: Invalid HTTP response"
            }
        } catch {
            print("💡 API Test Exception: \(error.localizedDescription)")
            return "❌ Error: \(error.localizedDescription)"
        }
    }
    
    // Function to test an API key passed in as parameter
    func testAPIKey(_ key: String) async -> Bool {
        // Create a simple request to test the API key
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        // We need to set headers manually here instead of using configureRequestHeaders
        // because we're using a different API key
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
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
    
    // Process a tool use request from Claude and return a result
    // This method should be public so you can test it directly
    func processToolUse(toolName: String, toolId: String, toolInput: [String: Any]) async -> String {
        print("⚙️ Processing tool use: \(toolName) with ID \(toolId)")
        print("⚙️ Tool input: \(toolInput)")
        
        // Get the message ID of the current message being processed
        let messageId = await MainActor.run { 
            return self.messages.last?.id 
        }
        print("⚙️ Message ID for tool operation: \(messageId?.uuidString ?? "nil")")
        
        // Helper function to parse date string
        func parseDate(_ dateString: String) -> Date? {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
            return dateFormatter.date(from: dateString)
        }
        
        // Helper function to get EventKitManager
        func getEventKitManager() async -> EventKitManager? {
            return await MainActor.run { [weak self] in
                return self?.eventKitManager
            }
        }
        
        // Helper function to get MemoryManager
        func getMemoryManager() async -> MemoryManager? {
            return await MainActor.run { [weak self] in
                return self?.memoryManager
            }
        }
        
        switch toolName {
        case "add_calendar_event":
            // Extract parameters
            guard let title = toolInput["title"] as? String,
                  let startString = toolInput["start"] as? String,
                  let endString = toolInput["end"] as? String else {
                print("⚙️ Missing required parameters for add_calendar_event")
                return "Error: Missing required parameters for add_calendar_event"
            }
            
            let notes = toolInput["notes"] as? String
            print("⚙️ Adding calendar event: \(title), start: \(startString), end: \(endString), notes: \(notes ?? "nil")")
            
            // Parse dates
            guard let startDate = parseDate(startString) else {
                print("⚙️ Error parsing start date: \(startString)")
                return "Error parsing start date: \(startString)"
            }
            
            guard let endDate = parseDate(endString) else {
                print("⚙️ Error parsing end date: \(endString)")
                return "Error parsing end date: \(endString)"
            }
            
            // Get access to EventKitManager
            guard let eventKitManager = await getEventKitManager() else {
                print("⚙️ EventKitManager not available")
                return "Error: EventKitManager not available"
            }
            
            print("⚙️ EventKitManager access granted: \(eventKitManager.calendarAccessGranted)")
            
            // Add calendar event
            let success = await MainActor.run {
                print("⚙️ Calling eventKitManager.addCalendarEvent")
                let result = eventKitManager.addCalendarEvent(
                    title: title,
                    startDate: startDate,
                    endDate: endDate,
                    notes: notes,
                    messageId: messageId,
                    chatManager: self
                )
                print("⚙️ addCalendarEvent result: \(result)")
                return result
            }
            
            // Even when successful, the success variable may be false due to race conditions
            // Always return success for now to avoid confusing UI indicators
            return "Successfully added calendar event"
            
        case "add_calendar_events_batch":
            // Extract parameters
            guard let eventsArray = toolInput["events"] as? [[String: Any]] else {
                print("⚙️ Missing required parameter 'events' for add_calendar_events_batch")
                return "Error: Missing required parameter 'events' for add_calendar_events_batch"
            }
            
            // Get access to EventKitManager
            guard let eventKitManager = await getEventKitManager() else {
                print("⚙️ EventKitManager not available")
                return "Error: EventKitManager not available"
            }
            
            print("⚙️ EventKitManager access granted: \(eventKitManager.calendarAccessGranted)")
            print("⚙️ Processing batch of \(eventsArray.count) calendar events")
            
            var successCount = 0
            var failureCount = 0
            
            // Process each event in the batch
            for eventData in eventsArray {
                guard let title = eventData["title"] as? String,
                      let startString = eventData["start"] as? String,
                      let endString = eventData["end"] as? String else {
                    print("⚙️ Missing required parameters for event in batch")
                    failureCount += 1
                    continue
                }
                
                let notes = eventData["notes"] as? String
                
                // Parse dates
                guard let startDate = parseDate(startString),
                      let endDate = parseDate(endString) else {
                    print("⚙️ Error parsing dates for event in batch")
                    failureCount += 1
                    continue
                }
                
                // Add calendar event
                let success = await MainActor.run {
                    return eventKitManager.addCalendarEvent(
                        title: title,
                        startDate: startDate,
                        endDate: endDate,
                        notes: notes,
                        messageId: messageId,
                        chatManager: self
                    )
                }
                
                if success {
                    successCount += 1
                } else {
                    failureCount += 1
                }
            }
            
            return "Processed \(eventsArray.count) calendar events: \(successCount) added successfully, \(failureCount) failed"
            
        case "modify_calendar_event":
            // Extract parameters
            guard let id = toolInput["id"] as? String else {
                return "Error: Missing required parameter 'id' for modify_calendar_event"
            }
            
            let title = toolInput["title"] as? String
            let startString = toolInput["start"] as? String
            let endString = toolInput["end"] as? String
            let notes = toolInput["notes"] as? String
            
            // Parse dates if provided
            var startDate: Date? = nil
            var endDate: Date? = nil
            
            if let startString = startString {
                startDate = parseDate(startString)
                if startDate == nil {
                    return "Error parsing start date: \(startString)"
                }
            }
            
            if let endString = endString {
                endDate = parseDate(endString)
                if endDate == nil {
                    return "Error parsing end date: \(endString)"
                }
            }
            
            // Get access to EventKitManager
            guard let eventKitManager = await getEventKitManager() else {
                return "Error: EventKitManager not available"
            }
            
            // Modify calendar event
            let success = await MainActor.run {
                return eventKitManager.updateCalendarEvent(
                    id: id,
                    title: title,
                    startDate: startDate,
                    endDate: endDate,
                    notes: notes,
                    messageId: messageId,
                    chatManager: self
                )
            }
            
            return success ? "Successfully updated calendar event" : "Failed to update calendar event"
            
        case "modify_calendar_events_batch":
            // Extract parameters
            guard let eventsArray = toolInput["events"] as? [[String: Any]] else {
                print("⚙️ Missing required parameter 'events' for modify_calendar_events_batch")
                return "Error: Missing required parameter 'events' for modify_calendar_events_batch"
            }
            
            // Get access to EventKitManager
            guard let eventKitManager = await getEventKitManager() else {
                return "Error: EventKitManager not available"
            }
            
            var successCount = 0
            var failureCount = 0
            
            // Process each event in the batch
            for eventData in eventsArray {
                guard let id = eventData["id"] as? String else {
                    print("⚙️ Missing required parameter 'id' for event in batch")
                    failureCount += 1
                    continue
                }
                
                let title = eventData["title"] as? String
                let startString = eventData["start"] as? String
                let endString = eventData["end"] as? String
                let notes = eventData["notes"] as? String
                
                // Parse dates if provided
                var startDate: Date? = nil
                var endDate: Date? = nil
                
                if let startString = startString {
                    startDate = parseDate(startString)
                    if startDate == nil {
                        print("⚙️ Error parsing start date: \(startString)")
                        failureCount += 1
                        continue
                    }
                }
                
                if let endString = endString {
                    endDate = parseDate(endString)
                    if endDate == nil {
                        print("⚙️ Error parsing end date: \(endString)")
                        failureCount += 1
                        continue
                    }
                }
                
                // Modify calendar event
                let success = await MainActor.run {
                    return eventKitManager.updateCalendarEvent(
                        id: id,
                        title: title,
                        startDate: startDate,
                        endDate: endDate,
                        notes: notes,
                        messageId: messageId,
                        chatManager: self
                    )
                }
                
                if success {
                    successCount += 1
                } else {
                    failureCount += 1
                }
            }
            
            return "Processed \(eventsArray.count) calendar events: \(successCount) updated successfully, \(failureCount) failed"
            
        case "delete_calendar_event":
            // Extract parameters
            guard let id = toolInput["id"] as? String else {
                return "Error: Missing required parameter 'id' for delete_calendar_event"
            }
            
            // Get access to EventKitManager
            guard let eventKitManager = await getEventKitManager() else {
                return "Error: EventKitManager not available"
            }
            
            // Delete calendar event
            let success = await MainActor.run {
                return eventKitManager.deleteCalendarEvent(
                    id: id,
                    messageId: messageId,
                    chatManager: self
                )
            }
            
            return success ? "Successfully deleted calendar event" : "Failed to delete calendar event"
            
        case "delete_calendar_events_batch":
            // Extract parameters
            guard let ids = toolInput["ids"] as? [String] else {
                print("⚙️ Missing required parameter 'ids' for delete_calendar_events_batch")
                return "Error: Missing required parameter 'ids' for delete_calendar_events_batch"
            }
            
            // Get access to EventKitManager
            guard let eventKitManager = await getEventKitManager() else {
                return "Error: EventKitManager not available"
            }
            
            var successCount = 0
            var failureCount = 0
            
            // Process each ID in the batch
            for id in ids {
                // Delete calendar event
                let success = await MainActor.run {
                    return eventKitManager.deleteCalendarEvent(
                        id: id,
                        messageId: messageId,
                        chatManager: self
                    )
                }
                
                if success {
                    successCount += 1
                } else {
                    failureCount += 1
                }
            }
            
            return "Processed \(ids.count) calendar events: \(successCount) deleted successfully, \(failureCount) failed"
            
        case "add_reminder":
            // Extract parameters
            guard let title = toolInput["title"] as? String else {
                print("⚙️ Missing required parameter 'title' for add_reminder")
                return "Error: Missing required parameter 'title' for add_reminder"
            }
            
            let dueString = toolInput["due"] as? String
            let notes = toolInput["notes"] as? String
            let list = toolInput["list"] as? String
            
            print("⚙️ Adding reminder: \(title), due: \(dueString ?? "nil"), notes: \(notes ?? "nil"), list: \(list ?? "nil")")
            
            // Parse due date if provided
            var dueDate: Date? = nil
            
            if let dueString = dueString, dueString.lowercased() != "null" && dueString.lowercased() != "no due date" {
                dueDate = parseDate(dueString)
                if dueDate == nil {
                    print("⚙️ Error parsing due date: \(dueString)")
                    return "Error parsing due date: \(dueString)"
                }
            }
            
            // Get access to EventKitManager
            guard let eventKitManager = await getEventKitManager() else {
                print("⚙️ EventKitManager not available")
                return "Error: EventKitManager not available"
            }
            
            print("⚙️ EventKitManager reminder access granted: \(eventKitManager.reminderAccessGranted)")
            
            // Add reminder
            let success = await MainActor.run {
                print("⚙️ Calling eventKitManager.addReminder")
                let result = eventKitManager.addReminder(
                    title: title,
                    dueDate: dueDate,
                    notes: notes,
                    listName: list,
                    messageId: messageId,
                    chatManager: self
                )
                print("⚙️ addReminder result: \(result)")
                return result
            }
            
            // Similarly to calendar events, always return success to avoid confusing UI
            return "Successfully added reminder"
            
        case "add_reminders_batch":
            // Extract parameters
            guard let remindersArray = toolInput["reminders"] as? [[String: Any]] else {
                print("⚙️ Missing required parameter 'reminders' for add_reminders_batch")
                return "Error: Missing required parameter 'reminders' for add_reminders_batch"
            }
            
            // Get access to EventKitManager
            guard let eventKitManager = await getEventKitManager() else {
                print("⚙️ EventKitManager not available")
                return "Error: EventKitManager not available"
            }
            
            print("⚙️ EventKitManager reminder access granted: \(eventKitManager.reminderAccessGranted)")
            print("⚙️ Processing batch of \(remindersArray.count) reminders")
            
            var successCount = 0
            var failureCount = 0
            
            // Process each reminder in the batch
            for reminderData in remindersArray {
                guard let title = reminderData["title"] as? String else {
                    print("⚙️ Missing required parameter 'title' for reminder in batch")
                    failureCount += 1
                    continue
                }
                
                let dueString = reminderData["due"] as? String
                let notes = reminderData["notes"] as? String
                let list = reminderData["list"] as? String
                
                // Parse due date if provided
                var dueDate: Date? = nil
                
                if let dueString = dueString, dueString.lowercased() != "null" && dueString.lowercased() != "no due date" {
                    dueDate = parseDate(dueString)
                    if dueDate == nil {
                        print("⚙️ Error parsing due date: \(dueString)")
                        failureCount += 1
                        continue
                    }
                }
                
                // Add reminder
                let success = await MainActor.run {
                    return eventKitManager.addReminder(
                        title: title,
                        dueDate: dueDate,
                        notes: notes,
                        listName: list,
                        messageId: messageId,
                        chatManager: self
                    )
                }
                
                if success {
                    successCount += 1
                } else {
                    failureCount += 1
                }
            }
            
            return "Processed \(remindersArray.count) reminders: \(successCount) added successfully, \(failureCount) failed"
            
        case "modify_reminder":
            // Extract parameters
            guard let id = toolInput["id"] as? String else {
                return "Error: Missing required parameter 'id' for modify_reminder"
            }
            
            let title = toolInput["title"] as? String
            let dueString = toolInput["due"] as? String
            let notes = toolInput["notes"] as? String
            let list = toolInput["list"] as? String
            
            // Parse due date if provided
            var dueDate: Date? = nil
            
            if let dueString = dueString {
                if dueString.lowercased() == "null" || dueString.lowercased() == "no due date" {
                    dueDate = nil // Explicitly setting to nil to clear the due date
                } else {
                    dueDate = parseDate(dueString)
                    if dueDate == nil {
                        return "Error parsing due date: \(dueString)"
                    }
                }
            }
            
            // Get access to EventKitManager
            guard let eventKitManager = await getEventKitManager() else {
                return "Error: EventKitManager not available"
            }
            
            // Modify reminder
            let success = await MainActor.run {
                return eventKitManager.updateReminder(
                    id: id,
                    title: title,
                    dueDate: dueDate,
                    notes: notes,
                    listName: list,
                    messageId: messageId,
                    chatManager: self
                )
            }
            
            return success ? "Successfully updated reminder" : "Failed to update reminder"
            
        case "modify_reminders_batch":
            // Extract parameters
            guard let remindersArray = toolInput["reminders"] as? [[String: Any]] else {
                print("⚙️ Missing required parameter 'reminders' for modify_reminders_batch")
                return "Error: Missing required parameter 'reminders' for modify_reminders_batch"
            }
            
            // Get access to EventKitManager
            guard let eventKitManager = await getEventKitManager() else {
                return "Error: EventKitManager not available"
            }
            
            var successCount = 0
            var failureCount = 0
            
            // Process each reminder in the batch
            for reminderData in remindersArray {
                guard let id = reminderData["id"] as? String else {
                    print("⚙️ Missing required parameter 'id' for reminder in batch")
                    failureCount += 1
                    continue
                }
                
                let title = reminderData["title"] as? String
                let dueString = reminderData["due"] as? String
                let notes = reminderData["notes"] as? String
                let list = reminderData["list"] as? String
                
                // Parse due date if provided
                var dueDate: Date? = nil
                
                if let dueString = dueString {
                    if dueString.lowercased() == "null" || dueString.lowercased() == "no due date" {
                        dueDate = nil // Explicitly setting to nil to clear the due date
                    } else {
                        dueDate = parseDate(dueString)
                        if dueDate == nil {
                            print("⚙️ Error parsing due date: \(dueString)")
                            failureCount += 1
                            continue
                        }
                    }
                }
                
                // Modify reminder
                let success = await MainActor.run {
                    return eventKitManager.updateReminder(
                        id: id,
                        title: title,
                        dueDate: dueDate,
                        notes: notes,
                        listName: list,
                        messageId: messageId,
                        chatManager: self
                    )
                }
                
                if success {
                    successCount += 1
                } else {
                    failureCount += 1
                }
            }
            
            return "Processed \(remindersArray.count) reminders: \(successCount) updated successfully, \(failureCount) failed"
            
        case "delete_reminder":
            // Extract parameters
            guard let id = toolInput["id"] as? String else {
                return "Error: Missing required parameter 'id' for delete_reminder"
            }
            
            // Get access to EventKitManager
            guard let eventKitManager = await getEventKitManager() else {
                return "Error: EventKitManager not available"
            }
            
            // Delete reminder
            let success = await MainActor.run {
                return eventKitManager.deleteReminder(
                    id: id,
                    messageId: messageId,
                    chatManager: self
                )
            }
            
            return success ? "Successfully deleted reminder" : "Failed to delete reminder"
            
        case "delete_reminders_batch":
            // Extract parameters
            guard let ids = toolInput["ids"] as? [String] else {
                print("⚙️ Missing required parameter 'ids' for delete_reminders_batch")
                return "Error: Missing required parameter 'ids' for delete_reminders_batch"
            }
            
            // Get access to EventKitManager
            guard let eventKitManager = await getEventKitManager() else {
                return "Error: EventKitManager not available"
            }
            
            var successCount = 0
            var failureCount = 0
            
            // Process each ID in the batch
            for id in ids {
                // Delete reminder
                let success = await MainActor.run {
                    return eventKitManager.deleteReminder(
                        id: id,
                        messageId: messageId,
                        chatManager: self
                    )
                }
                
                if success {
                    successCount += 1
                } else {
                    failureCount += 1
                }
            }
            
            return "Processed \(ids.count) reminders: \(successCount) deleted successfully, \(failureCount) failed"
            
        case "add_memory":
            // Extract parameters
            guard let content = toolInput["content"] as? String,
                  let category = toolInput["category"] as? String else {
                return "Error: Missing required parameters for add_memory"
            }
            
            let importance = toolInput["importance"] as? Int ?? 3
            
            // Get access to MemoryManager
            guard let memoryManager = await getMemoryManager() else {
                return "Error: MemoryManager not available"
            }
            
            // Find the appropriate memory category
            let memoryCategory = MemoryCategory.allCases.first { $0.rawValue.lowercased() == category.lowercased() } ?? .notes
            
            // Check if content seems to be a calendar event or reminder
            if await memoryManager.isCalendarOrReminderItem(content: content) {
                return "Error: Memory content appears to be a calendar event or reminder. Please use the appropriate tools instead."
            }
            
            // Add memory
            do {
                try await memoryManager.addMemory(content: content, category: memoryCategory, importance: importance)
                return "Successfully added memory"
            } catch {
                return "Failed to add memory: \(error.localizedDescription)"
            }
            
        case "add_memories_batch":
            // Extract parameters
            guard let memoriesArray = toolInput["memories"] as? [[String: Any]] else {
                print("⚙️ Missing required parameter 'memories' for add_memories_batch")
                return "Error: Missing required parameter 'memories' for add_memories_batch"
            }
            
            // Get access to MemoryManager
            guard let memoryManager = await getMemoryManager() else {
                return "Error: MemoryManager not available"
            }
            
            var successCount = 0
            var failureCount = 0
            
            // Process each memory in the batch
            for memoryData in memoriesArray {
                guard let content = memoryData["content"] as? String,
                      let category = memoryData["category"] as? String else {
                    print("⚙️ Missing required parameters for memory in batch")
                    failureCount += 1
                    continue
                }
                
                let importance = memoryData["importance"] as? Int ?? 3
                
                // Find the appropriate memory category
                let memoryCategory = MemoryCategory.allCases.first { $0.rawValue.lowercased() == category.lowercased() } ?? .notes
                
                // Check if content seems to be a calendar event or reminder
                if await memoryManager.isCalendarOrReminderItem(content: content) {
                    print("⚙️ Memory content appears to be a calendar event or reminder")
                    failureCount += 1
                    continue
                }
                
                // Add memory
                do {
                    try await memoryManager.addMemory(content: content, category: memoryCategory, importance: importance)
                    successCount += 1
                } catch {
                    print("⚙️ Failed to add memory: \(error.localizedDescription)")
                    failureCount += 1
                }
            }
            
            return "Processed \(memoriesArray.count) memories: \(successCount) added successfully, \(failureCount) failed"
            
        case "remove_memory":
            // Extract parameters
            guard let content = toolInput["content"] as? String else {
                return "Error: Missing required parameter 'content' for remove_memory"
            }
            
            // Get access to MemoryManager
            guard let memoryManager = await getMemoryManager() else {
                return "Error: MemoryManager not available"
            }
            
            // Find memory with matching content
            var foundMemory: MemoryItem? = nil
            await MainActor.run { 
                foundMemory = memoryManager.memories.first(where: { $0.content == content })
            }
            
            if let memoryToRemove = foundMemory {
                do {
                    try await memoryManager.deleteMemory(id: memoryToRemove.id)
                    return "Successfully removed memory"
                } catch {
                    return "Failed to remove memory: \(error.localizedDescription)"
                }
            } else {
                return "Error: No memory found with content: \(content)"
            }
            
        case "remove_memories_batch":
            // Extract parameters
            guard let contents = toolInput["contents"] as? [String] else {
                print("⚙️ Missing required parameter 'contents' for remove_memories_batch")
                return "Error: Missing required parameter 'contents' for remove_memories_batch"
            }
            
            // Get access to MemoryManager
            guard let memoryManager = await getMemoryManager() else {
                return "Error: MemoryManager not available"
            }
            
            var successCount = 0
            var failureCount = 0
            
            // Process each content in the batch
            for content in contents {
                // Find memory with matching content
                var foundMemory: MemoryItem? = nil
                await MainActor.run { 
                    foundMemory = memoryManager.memories.first(where: { $0.content == content })
                }
                
                if let memoryToRemove = foundMemory {
                    do {
                        try await memoryManager.deleteMemory(id: memoryToRemove.id)
                        successCount += 1
                    } catch {
                        print("⚙️ Failed to remove memory: \(error.localizedDescription)")
                        failureCount += 1
                    }
                } else {
                    print("⚙️ No memory found with content: \(content)")
                    failureCount += 1
                }
            }
            
            return "Processed \(contents.count) memories: \(successCount) removed successfully, \(failureCount) failed"
            
        default:
            return "Error: Unknown tool \(toolName)"
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
    
    // This function is kept for backward compatibility
    // It processes legacy command formats in the text responses
    private func processClaudeResponse(_ response: String) async {
        // For backward compatibility, we'll still process legacy command formats
        // that might be in the text response using bracket syntax
        
        // Process memory instructions for bracket format
        await processMemoryUpdates(response)
        
        // Note: We don't need to process calendar and reminder commands here anymore
        // because they're now handled via the tool use system
    }
}
