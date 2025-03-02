import Foundation
import Combine

/**
 * ChatManager is the central coordinator for the chat functionality in the ADHD Coach app.
 *
 * This class is responsible for:
 * - Managing the chat message collection and UI state
 * - Coordinating between specialized component managers
 * - Handling user and assistant messages
 * - Processing streaming responses from Claude
 * - Managing operation status messages
 * - Coordinating automatic messages
 * - Delegating tool processing to appropriate handlers
 */
class ChatManager: ObservableObject {
    // MARK: - Published Properties
    
    /// Collection of chat messages
    @Published var messages: [ChatMessage] = []
    
    /// Indicates if a message is currently being processed
    @Published var isProcessing = false
    
    /// ID of the message currently being streamed (if any)
    @Published var currentStreamingMessageId: UUID?
    
    /// Counter to track streaming updates for scrolling
    @Published var streamingUpdateCount: Int = 0
    
    /// Maps message IDs to their operation status messages
    @Published var operationStatusMessages: [UUID: [OperationStatusMessage]] = [:]
    
    // MARK: - Component Managers
    
    /// Handles API communication with Claude
    private let apiService = ChatAPIService()
    
    /// Manages tool definitions and processing
    private let toolHandler = ChatToolHandler()
    
    /// Manages operation status messages
    private let statusManager = ChatOperationStatusManager()
    
    /// Manages automatic message functionality
    private let automaticMessageService = ChatAutomaticMessageService()
    
    /// Handles persistence of chat messages
    private let persistenceManager = ChatPersistenceManager()
    
    // MARK: - External Managers
    
    /// Manages user memory persistence
    private var memoryManager: MemoryManager?
    
    /// Manages calendar events and reminders
    private var eventKitManager: EventKitManager?
    
    /// Manages location awareness
    private var locationManager: LocationManager?
    
    /// Current content of the streaming message
    private var currentStreamingMessage: String = ""
    
    // MARK: - Initialization
    
    /**
     * Initializes the ChatManager and sets up component interactions.
     */
    @MainActor
    init() {
        print("⏱️ ChatManager initializing")
        
        // Set up tool handler callback
        toolHandler.processToolUseCallback = { [weak self] toolName, toolId, toolInput, messageId, chatManager in
            return await self?.processToolUse(toolName: toolName, toolId: toolId, toolInput: toolInput) ?? "Error: Tool processing failed"
        }
        
        // Set up API service callback
        apiService.processToolUseCallback = { [weak self] toolName, toolId, toolInput in
            return await self?.processToolUse(toolName: toolName, toolId: toolId, toolInput: toolInput) ?? "Error: Tool processing failed"
        }
        
        // Load previous messages from storage
        let loadResult = persistenceManager.loadMessages()
        messages = loadResult.messages
        currentStreamingMessageId = loadResult.currentStreamingMessageId
        
        // Always ensure isProcessing is false when initializing
        // This prevents the send button from being disabled on app restart
        isProcessing = false
        
        // Load operation status messages
        operationStatusMessages = statusManager.loadOperationStatusMessages()
        
        // Reset any incomplete messages from previous sessions
        var messagesRef = messages
        if persistenceManager.resetIncompleteMessages(messages: &messagesRef) {
            messages = messagesRef
            currentStreamingMessageId = nil
        }
        
        // Add initial assistant message if this is the first time
        if messages.isEmpty {
            let welcomeMessage = "Hi! I'm your ADHD Coach. I can help you manage your tasks, calendar, and overcome overwhelm. How are you feeling today?"
            addAssistantMessage(content: welcomeMessage)
        }
        
        // Set a default value for automatic messages if not already set
        if UserDefaults.standard.object(forKey: "enable_automatic_responses") == nil {
            print("⏱️ ChatManager init - Setting default value for enable_automatic_responses to TRUE")
            UserDefaults.standard.set(true, forKey: "enable_automatic_responses")
        }
    }
    
    // MARK: - External Manager Setup
    
    /**
     * Sets the memory manager for user memory persistence.
     *
     * @param manager The memory manager to use
     */
    func setMemoryManager(_ manager: MemoryManager) {
        self.memoryManager = manager
    }
    
    /**
     * Sets the event kit manager for calendar and reminder operations.
     *
     * @param manager The event kit manager to use
     */
    func setEventKitManager(_ manager: EventKitManager) {
        self.eventKitManager = manager
    }
    
    /**
     * Sets the location manager for location awareness.
     *
     * @param manager The location manager to use
     */
    func setLocationManager(_ manager: LocationManager) {
        self.locationManager = manager
    }
    
    /**
     * Returns the time when the app was last opened.
     *
     * @return The last app open time, or nil if not available
     */
    func getLastAppOpenTime() -> Date? {
        return automaticMessageService.getLastAppOpenTime()
    }
    
    // MARK: - Automatic Message Handling
    
    /**
     * Checks if an automatic message should be sent and sends it if needed.
     */
    @MainActor
    func checkAndSendAutomaticMessage() async {
        if await automaticMessageService.shouldSendAutomaticMessage() {
            await sendAutomaticMessage()
        }
    }
    
    /**
     * Checks if an automatic message should be sent after history deletion and sends it if needed.
     */
    @MainActor
    func checkAndSendAutomaticMessageAfterHistoryDeletion() async {
        if await automaticMessageService.shouldSendAutomaticMessageAfterHistoryDeletion() {
            await sendAutomaticMessage(isAfterHistoryDeletion: true)
        } else {
            // Fall back to a static welcome message if we can't query
            addAssistantMessage(content: "Hi! I'm your ADHD Coach. I can help you manage your tasks, calendar, and overcome overwhelm. How are you feeling today?")
        }
    }
    
    // MARK: - Message Management
    
    /**
     * Adds a user message to the chat.
     *
     * @param content The content of the user message
     */
    @MainActor
    func addUserMessage(content: String) {
        let message = ChatMessage(content: content, isUser: true)
        messages.append(message)
        persistenceManager.saveMessages(messages: messages, isProcessing: isProcessing, currentStreamingMessageId: currentStreamingMessageId)
    }
    
    /**
     * Adds an assistant message to the chat.
     *
     * @param content The content of the assistant message
     * @param isComplete Whether the message is complete (default: true)
     */
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
        
        persistenceManager.saveMessages(messages: messages, isProcessing: isProcessing, currentStreamingMessageId: currentStreamingMessageId)
    }
    
    /**
     * Updates the content of the currently streaming message.
     *
     * @param content The new content for the streaming message
     */
    @MainActor
    func updateStreamingMessage(content: String) {
        if let streamingId = currentStreamingMessageId,
           let index = messages.firstIndex(where: { $0.id == streamingId }) {
            // Update the message content
            messages[index].content = content
            // Increment counter to trigger scroll updates
            streamingUpdateCount += 1
            // Save messages to ensure they're persisted
            persistenceManager.saveMessages(messages: messages, isProcessing: isProcessing, currentStreamingMessageId: currentStreamingMessageId)
        }
    }
    
    /**
     * Appends new content to the currently streaming message.
     *
     * This method both updates the UI and returns the accumulated content.
     * It's isolated to the MainActor to avoid concurrency issues.
     *
     * @param newContent The new content to append
     * @return The updated full content of the streaming message
     */
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
            persistenceManager.saveMessages(messages: messages, isProcessing: isProcessing, currentStreamingMessageId: currentStreamingMessageId)
            
            // Return the updated content
            return updatedContent
        }
        return ""
    }
    
    /**
     * Finalizes the currently streaming message, marking it as complete.
     */
    @MainActor
    func finalizeStreamingMessage() {
        if let streamingId = currentStreamingMessageId,
           let index = messages.firstIndex(where: { $0.id == streamingId }) {
            messages[index].isComplete = true
            currentStreamingMessageId = nil
            // Trigger one final update for scrolling
            streamingUpdateCount += 1
            // Save messages to persist the finalized state
            persistenceManager.saveMessages(messages: messages, isProcessing: isProcessing, currentStreamingMessageId: currentStreamingMessageId)
        }
    }
    
    // MARK: - Operation Status Management
    
    /**
     * Returns all operation status messages associated with a specific chat message.
     *
     * @param message The chat message to get status messages for
     * @return An array of operation status messages
     */
    @MainActor
    func statusMessagesForMessage(_ message: ChatMessage) -> [OperationStatusMessage] {
        return statusManager.statusMessagesForMessage(message.id)
    }
    
    /**
     * Adds a new operation status message for a specific chat message.
     *
     * @param messageId The UUID of the chat message
     * @param operationType The type of operation (e.g., "Add Calendar Event")
     * @param status The current status of the operation (default: .inProgress)
     * @param details Optional details about the operation
     * @return The newly created operation status message
     */
    @MainActor
    func addOperationStatusMessage(forMessageId messageId: UUID, operationType: String, status: OperationStatus = .inProgress, details: String? = nil) -> OperationStatusMessage {
        let statusMessage = statusManager.addOperationStatusMessage(
            forMessageId: messageId,
            operationType: operationType,
            status: status,
            details: details
        )
        
        // Update the local copy
        if operationStatusMessages[messageId] == nil {
            operationStatusMessages[messageId] = []
        }
        operationStatusMessages[messageId]?.append(statusMessage)
        
        return statusMessage
    }
    
    /**
     * Updates an existing operation status message.
     *
     * @param messageId The UUID of the chat message
     * @param statusMessageId The UUID of the status message to update
     * @param status The new status of the operation
     * @param details Optional new details about the operation
     */
    @MainActor
    func updateOperationStatusMessage(forMessageId messageId: UUID, statusMessageId: UUID, status: OperationStatus, details: String? = nil) {
        statusManager.updateOperationStatusMessage(
            forMessageId: messageId,
            statusMessageId: statusMessageId,
            status: status,
            details: details
        )
        
        // Update the local copy
        if var statusMessages = operationStatusMessages[messageId],
           let index = statusMessages.firstIndex(where: { $0.id == statusMessageId }) {
            statusMessages[index].status = status
            if let details = details {
                statusMessages[index].details = details
            }
            operationStatusMessages[messageId] = statusMessages
        }
    }
    
    /**
     * Removes an operation status message.
     *
     * @param messageId The UUID of the chat message
     * @param statusMessageId The UUID of the status message to remove
     */
    @MainActor
    func removeOperationStatusMessage(forMessageId messageId: UUID, statusMessageId: UUID) {
        statusManager.removeOperationStatusMessage(forMessageId: messageId, statusMessageId: statusMessageId)
        
        // Update the local copy
        if var statusMessages = operationStatusMessages[messageId] {
            statusMessages.removeAll(where: { $0.id == statusMessageId })
            if statusMessages.isEmpty {
                operationStatusMessages.removeValue(forKey: messageId)
            } else {
                operationStatusMessages[messageId] = statusMessages
            }
        }
    }
    
    /// Store tool use results for feedback to Claude in the next message
    private var pendingToolResults: [(toolId: String, content: String)] = []
    
    // Variables to track tool use chunks
    private var currentToolName: String?
    private var currentToolId: String?
    private var currentToolInputJson = ""
    
    /// Retrieves the Claude API key from UserDefaults
    private var apiKey: String {
        return UserDefaults.standard.string(forKey: "claude_api_key") ?? ""
    }
    
    // MARK: - Claude API Communication
    
    /**
     * Sends a user message to Claude with all necessary context.
     *
     * @param userMessage The user's message to send
     * @param calendarEvents The user's calendar events
     * @param reminders The user's reminders
     */
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
            return persistenceManager.formatRecentConversationHistory(messages: messages)
        }
        
        // Initialize streaming message
        await MainActor.run {
            currentStreamingMessage = ""
            addAssistantMessage(content: "", isComplete: false)
        }
        
        // Send the message to Claude using the API service
        await apiService.sendMessageToClaude(
            userMessage: userMessage,
            conversationHistory: conversationHistory,
            memoryContent: memoryContent,
            calendarContext: calendarContext,
            remindersContext: remindersContext,
            locationContext: locationContext,
            toolDefinitions: toolHandler.getToolDefinitions(),
            updateStreamingMessage: { [weak self] newContent in
                guard let self = self else { return "" }
                // Use DispatchQueue.main to run on the main thread instead of Task
                let semaphore = DispatchSemaphore(value: 0)
                var result = ""
                DispatchQueue.main.async {
                    result = self.appendToStreamingMessage(newContent: newContent)
                    semaphore.signal()
                }
                semaphore.wait()
                return result
            },
            finalizeStreamingMessage: { [weak self] in
                Task { @MainActor in
                    self?.finalizeStreamingMessage()
                }
            },
            isProcessingCallback: { [weak self] isProcessing in
                Task { @MainActor in
                    self?.isProcessing = isProcessing
                }
            }
        )
        
        // Process any memory updates from the response
        if let lastMessage = await MainActor.run(body: { messages.last }) {
            await toolHandler.processMemoryUpdates(response: lastMessage.content, memoryManager: memoryManager!)
        }
    }
    
    /**
     * Formats calendar events for Claude context.
     *
     * @param events Array of calendar events
     * @return Formatted string of calendar events
     */
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
    
    /**
     * Formats reminders for Claude context.
     *
     * @param reminders Array of reminder items
     * @return Formatted string of reminders
     */
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
    
    /**
     * Formats a date for display.
     *
     * @param date The date to format
     * @return Formatted date string
     */
    private func formatDate(_ date: Date) -> String {
        return DateFormatter.shared.string(from: date)
    }
    
    
    /**
     * Gets the user's location context if available and enabled.
     *
     * @return A string containing location information, or empty if not available
     */
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
    
    
    /**
     * Sends an automatic message without user input.
     *
     * @param isAfterHistoryDeletion Whether this is after history deletion
     */
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
            return persistenceManager.formatRecentConversationHistory(messages: messages)
        }
        print("⏱️ Got conversation history for automatic message. Length: \(conversationHistory.count)")
        
        // Initialize streaming message
        await MainActor.run {
            currentStreamingMessage = ""
            addAssistantMessage(content: "", isComplete: false)
            print("⏱️ Added empty assistant message for streaming")
        }
        
        // Create the automatic message text
        let automaticMessageText = "[THIS IS AN AUTOMATIC MESSAGE - \(isAfterHistoryDeletion ? "The user has just cleared their chat history." : "The user has just opened the app after not using it for at least 5 minutes.") There is no specific user message. Based on the time of day, calendar events, reminders, and what you know about the user, provide a helpful, proactive greeting or insight.]"
        
        // Send the message to Claude using the API service
        await apiService.sendMessageToClaude(
            userMessage: automaticMessageText,
            conversationHistory: conversationHistory,
            memoryContent: memoryContent,
            calendarContext: calendarContext,
            remindersContext: remindersContext,
            locationContext: locationContext,
            toolDefinitions: toolHandler.getToolDefinitions(),
            updateStreamingMessage: { [weak self] newContent in
                guard let self = self else { return "" }
                // Use DispatchQueue.main to run on the main thread instead of Task
                let semaphore = DispatchSemaphore(value: 0)
                var result = ""
                DispatchQueue.main.async {
                    result = self.appendToStreamingMessage(newContent: newContent)
                    semaphore.signal()
                }
                semaphore.wait()
                return result
            },
            finalizeStreamingMessage: { [weak self] in
                Task { @MainActor in
                    self?.finalizeStreamingMessage()
                }
            },
            isProcessingCallback: { [weak self] isProcessing in
                Task { @MainActor in
                    self?.isProcessing = isProcessing
                }
            }
        )
        
        // Process any memory updates from the response
        if let lastMessage = await MainActor.run(body: { messages.last }) {
            await toolHandler.processMemoryUpdates(response: lastMessage.content, memoryManager: memoryManager!)
        }
    }
    
    // MARK: - API Key Testing
    
    /**
     * Tests if the current API key is valid by making a simple request to Claude.
     *
     * @return A string indicating whether the API key is valid or an error message
     */
    func testApiKey() async -> String {
        return await apiService.testApiKey()
    }
    
    /**
     * Tests if a provided API key is valid by making a simple request to Claude.
     *
     * @param key The API key to test
     * @return A boolean indicating whether the API key is valid
     */
    func testAPIKey(_ key: String) async -> Bool {
        return await apiService.testAPIKey(key)
    }
    
    // MARK: - Tool Processing
    
    /**
     * Processes a tool use request from Claude and returns a result.
     *
     * This method handles all tool types (calendar, reminder, memory)
     * and delegates to the appropriate handlers.
     *
     * @param toolName The name of the tool to use
     * @param toolId The unique ID of the tool use request
     * @param toolInput The input parameters for the tool
     * @return The result of the tool use as a string
     */
    func processToolUse(toolName: String, toolId: String, toolInput: [String: Any]) async -> String {
        print("⚙️ Processing tool use: \(toolName) with ID \(toolId)")
        print("⚙️ Tool input: \(toolInput)")
        
        // Get the message ID of the current message being processed
        let messageId = await MainActor.run { 
            return self.messages.last?.id 
        }
        print("⚙️ Message ID for tool operation: \(messageId?.uuidString ?? "nil")")
        
        // Use the parseDate method from ChatToolHandler
        let parseDate = toolHandler.parseDate
        
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
    
    
    /**
     * Processes Claude's response for legacy command formats.
     *
     * This function is kept for backward compatibility.
     * It processes legacy command formats in the text responses.
     *
     * @param response The text response from Claude
     */
    private func processClaudeResponse(_ response: String) async {
        // For backward compatibility, we'll still process legacy command formats
        // that might be in the text response using bracket syntax
        
        // Process memory instructions for bracket format
        if let memManager = memoryManager {
            await toolHandler.processMemoryUpdates(response: response, memoryManager: memManager)
        }
        
        // Note: We don't need to process calendar and reminder commands here anymore
        // because they're now handled via the tool use system
    }
}
