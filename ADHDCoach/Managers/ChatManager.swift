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
@MainActor
class ChatManager: ObservableObject, @unchecked Sendable {
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
    
    /// Static reference to shared instance (for @Sendable closures)
    private static weak var sharedInstance: ChatManager?
    
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
    
    /// Processes tool use requests
    private let processToolUseService = ProcessToolUseService()
    
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
    /// Static method to update processing state (for @Sendable closures)
    nonisolated
    private static func updateProcessingState(_ isProcessing: Bool) {
        Task { @MainActor in
            sharedInstance?.isProcessing = isProcessing
        }
    }
    
    @MainActor
    init() {
        print("⏱️ ChatManager initializing")
        // Store reference to self for use in static methods
        ChatManager.sharedInstance = self
        
        // Set up tool handler callback
        toolHandler.processToolUseCallback = { [weak self] toolName, toolId, toolInput, messageId, chatManager in
            guard let self = self else { return "Error: Tool processing failed - self is nil" }
            return await self.processToolUseService.processToolUse(toolName: toolName, toolId: toolId, toolInput: toolInput, chatManager: self)
        }
        
        // Set up API service callback
        apiService.processToolUseCallback = { [weak self] toolName, toolId, toolInput in
            guard let self = self else { return "Error: Tool processing failed - self is nil" }
            return await self.processToolUseService.processToolUse(toolName: toolName, toolId: toolId, toolInput: toolInput, chatManager: self)
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
        self.processToolUseService.setMemoryManager(manager)
    }
    
    /**
     * Sets the event kit manager for calendar and reminder operations.
     *
     * @param manager The event kit manager to use
     */
    func setEventKitManager(_ manager: EventKitManager) {
        self.eventKitManager = manager
        self.processToolUseService.setEventKitManager(manager)
    }
    
    /**
     * Sets the location manager for location awareness.
     *
     * @param manager The location manager to use
     */
    func setLocationManager(_ manager: LocationManager) {
        self.locationManager = manager
        self.processToolUseService.setLocationManager(manager)
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
     * Clears all chat messages.
     */
    @MainActor
    func clearAllMessages() {
        // Clear messages from UserDefaults
        persistenceManager.clearAllMessages()
        
        // Clear messages from memory
        messages = []
        currentStreamingMessageId = nil
        isProcessing = false
        
        // Post notification to refresh chat view
        NotificationCenter.default.post(name: NSNotification.Name("ChatHistoryDeleted"), object: nil)
    }
    
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
            
            let existingContent = messages[index].content
            
            // Simply append the content directly without any special formatting logic
            // The Claude API should handle proper spacing and line breaks
            let updatedContent = existingContent + newContent
            
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
     * Returns combined operation status messages for a specific chat message.
     * Similar operations (same action and item type) will be combined with count.
     *
     * @param message The chat message
     * @return An array of combined operation status messages
     */
    func combinedStatusMessagesForMessage(_ message: ChatMessage) -> [OperationStatusMessage] {
        return statusManager.combinedStatusMessagesForMessage(message.id)
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
    func addOperationStatusMessage(
        forMessageId messageId: UUID, 
        operationType: OperationType, 
        status: OperationStatus = .inProgress, 
        details: String? = nil,
        count: Int = 1
    ) -> OperationStatusMessage {
        let statusMessage = statusManager.addOperationStatusMessage(
            forMessageId: messageId,
            operationType: operationType,
            status: status,
            details: details,
            count: count
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
     * @param count Optional count of items affected (maintains original count if not provided)
     */
    @MainActor
    func updateOperationStatusMessage(forMessageId messageId: UUID, statusMessageId: UUID, status: OperationStatus, details: String? = nil, count: Int? = nil) {
        statusManager.updateOperationStatusMessage(
            forMessageId: messageId,
            statusMessageId: statusMessageId,
            status: status,
            details: details,
            count: count
        )
        
        // Update the local copy
        if var statusMessages = operationStatusMessages[messageId],
           let index = statusMessages.firstIndex(where: { $0.id == statusMessageId }) {
            statusMessages[index].status = status
            if let details = details {
                statusMessages[index].details = details
            }
            if let count = count {
                statusMessages[index].count = count
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
    // MARK: - First API method
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
        
        // Log the message we're sending
        print("📨 Sending user message to Claude: \"\(userMessage.prefix(30))...\"")
        
        // First, check the calendar data hash BEFORE fetching new data
        let previousCalendarEvents = eventKitManager?.fetchUpcomingEvents(days: 7) ?? []
        let previousCalendarHash = previousCalendarEvents.hashValue
        print("🔍 HASH CHECK (Before): Calendar events hash = \(previousCalendarHash), count = \(previousCalendarEvents.count)")
        
        // Now force fetching fresh data for comparison
        print("🔄 Forcing a fresh fetch of event data to compare hash values")
        await refreshContextData()
        print("🕒 Pre-loaded fresh context data before sending message to Claude")
        
        // Fetch calendar data AGAIN to see if the hash changed after refresh
        let freshCalendarEvents = eventKitManager?.fetchUpcomingEvents(days: 7) ?? []
        let freshCalendarHash = freshCalendarEvents.hashValue
        print("🔍 HASH CHECK (After): Calendar events hash = \(freshCalendarHash), count = \(freshCalendarEvents.count)")
        
        // Check if the hash changed during this operation
        if previousCalendarHash != freshCalendarHash {
            print("⚠️ HASH DIFF DETECTED during message send! Hash changed from \(previousCalendarHash) to \(freshCalendarHash)")
            
            // Show what changed in calendar data
            let onlyInPrevious = previousCalendarEvents.filter { prev in
                !freshCalendarEvents.contains { fresh in
                    fresh.id == prev.id
                }
            }
            
            let onlyInFresh = freshCalendarEvents.filter { fresh in
                !previousCalendarEvents.contains { prev in
                    prev.id == fresh.id
                }
            }
            
            let modifiedInFresh = freshCalendarEvents.filter { fresh in
                previousCalendarEvents.contains { prev in
                    prev.id == fresh.id && prev.hashValue != fresh.hashValue
                }
            }
            
            print("⚠️ Calendar Changes:")
            print("⚠️ - Removed events: \(onlyInPrevious.count)")
            print("⚠️ - Added events: \(onlyInFresh.count)")
            print("⚠️ - Modified events: \(modifiedInFresh.count)")
            
            // Hash difference was detected - the new data will be used automatically
            // No need to force cache reset as we've already detected the change
            print("⚠️ Using freshly fetched calendar data - hash difference detected")
        } else {
            print("✅ HASH CHECK: Calendar hash unchanged during message send operation")
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
        let calendarContext = formatCalendarEvents(freshCalendarEvents)  // Use the fresh events
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
                // Use DispatchQueue.main to run on the main thread instead of Task
                let semaphore = DispatchSemaphore(value: 0)
                var result = ""
                
                if let weakSelf = self {
                    // Use MainActor.run to safely call the MainActor-isolated method
                    Task {
                        result = await MainActor.run {
                            return weakSelf.appendToStreamingMessage(newContent: newContent)
                        }
                        semaphore.signal()
                    }
                } else {
                    // If self is nil, signal the semaphore to avoid deadlock
                    semaphore.signal()
                }
                
                // Wait outside the if block to ensure we always wait
                semaphore.wait()
                return result
            },
            finalizeStreamingMessage: { [weak self] in
                Task { @MainActor in
                    self?.finalizeStreamingMessage()
                }
            },
            isProcessingCallback: { [weak self] isProcessing in
                // Use DispatchQueue.main.async instead of Task with MainActor.run
                DispatchQueue.main.async {
                    self?.isProcessing = isProcessing
                }
            }
        )
        
        // Process any memory updates from the response
        if let lastMessage = await MainActor.run(body: { messages.last }), let manager = memoryManager {
            let memoryUpdated = await toolHandler.processMemoryUpdates(response: lastMessage.content, memoryManager: manager, chatManager: self)
            
            // If memory wasn't updated through the text response, 
            // but tool calls might have modified memories, calendar events, or reminders
            if !memoryUpdated {
                // Make sure context window stays up-to-date
                await refreshContextData()
                print("🔄 Manually refreshing context after regular message to ensure API has latest data")
            }
        }
    }
    
    /**
     * Formats calendar events for Claude context.
     *
     * @param events Array of calendar events
     * @return Formatted string of calendar events
     */
    private func formatCalendarEvents(_ events: [CalendarEvent]) -> String {
        print("📆 Formatting \(events.count) calendar events for Claude context")
        
        if events.isEmpty {
            print("📆 No events to format, returning default message")
            return "No upcoming events."
        }
        
        // Sort events by start date to present them in a more logical order
        let sortedEvents = events.sorted { $0.startDate < $1.startDate }
        print("📆 Sorted events by start date")
        
        // Format each event into a string
        let formattedEvents = sortedEvents.map { event in
            let eventString = """
            ID: \(event.id)
            Title: \(event.title)
            Start: \(formatDate(event.startDate))
            End: \(formatDate(event.endDate))
            Notes: \(event.notes ?? "None")
            """
            return eventString
        }
        
        // Log a preview of the formatted content
        if !formattedEvents.isEmpty {
            print("📆 Calendar formatting preview (first event):")
            print(formattedEvents[0])
            print("📆 ... and \(formattedEvents.count - 1) more events")
        }
        
        // Join all formatted events with double newlines
        let result = formattedEvents.joined(separator: "\n\n")
        print("📆 Formatted calendar context length: \(result.count) characters")
        
        return result
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
    // MARK: - Second API method
    private func sendAutomaticMessage(isAfterHistoryDeletion: Bool = false) async {
        print("⏱️ SENDING AUTOMATIC MESSAGE - \(isAfterHistoryDeletion ? "After history deletion" : "After app open")")
        
        // First, ensure we have the latest data from external sources
        // This fixes the issue where external changes aren't reflected in Claude's context
        await refreshContextData()
        print("🕒 Pre-loaded fresh context data before sending automatic message")
        
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
                // Use DispatchQueue.main to run on the main thread instead of Task
                let semaphore = DispatchSemaphore(value: 0)
                var result = ""
                
                if let weakSelf = self {
                    // Use MainActor.run to safely call the MainActor-isolated method
                    Task {
                        result = await MainActor.run {
                            return weakSelf.appendToStreamingMessage(newContent: newContent)
                        }
                        semaphore.signal()
                    }
                } else {
                    // If self is nil, signal the semaphore to avoid deadlock
                    semaphore.signal()
                }
                
                // Wait outside the if block to ensure we always wait
                semaphore.wait()
                return result
            },
            finalizeStreamingMessage: { [weak self] in
                Task { @MainActor in
                    self?.finalizeStreamingMessage()
                }
            },
            isProcessingCallback: { [weak self] isProcessing in
                // Use DispatchQueue.main.async instead of Task with MainActor.run
                DispatchQueue.main.async {
                    self?.isProcessing = isProcessing
                }
            }
        )
        
        // Process any memory updates from the response
        if let lastMessage = await MainActor.run(body: { messages.last }), let manager = memoryManager {
            let memoryUpdated = await toolHandler.processMemoryUpdates(response: lastMessage.content, memoryManager: manager, chatManager: self)
            
            // If memory wasn't updated through the text response, 
            // but tool calls might have modified memories, calendar events, or reminders
            if !memoryUpdated {
                // Make sure context window stays up-to-date
                await refreshContextData()
                print("🔄 Manually refreshing context after automatic message to ensure API has latest data")
            }
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
    
    /**
     * Gets a performance report for the prompt caching system.
     *
     * @return A string containing cache performance metrics
     */
    func getCachePerformanceReport() -> String {
        return CachePerformanceTracker.shared.getPerformanceReport()
    }
    
    /**
     * Resets all cache performance metrics to zero.
     */
    func resetCachePerformanceMetrics() {
        CachePerformanceTracker.shared.reset()
    }
    
    // MARK: - Tool Processing
    
    /**
     * Delegate function that forwards tool use requests to the ProcessToolUseService.
     * This is kept for backward compatibility with existing code that might call this directly.
     *
     * @param toolName The name of the tool to use
     * @param toolId The unique ID of the tool use request
     * @param toolInput The input parameters for the tool
     * @return The result of the tool use as a string
     */
    func processToolUse(toolName: String, toolId: String, toolInput: [String: Any]) async -> String {
        return await processToolUseService.processToolUse(toolName: toolName, toolId: toolId, toolInput: toolInput, chatManager: self)
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
                let memoryUpdated = await toolHandler.processMemoryUpdates(response: response, memoryManager: memManager, chatManager: self)
                
                // If memory wasn't updated through bracket format,
                // we still need to manually refresh context to ensure it's up-to-date
                if !memoryUpdated {
                    await refreshContextData()
                    print("🔄 Manually refreshing context after processing response")
                }
            }
        
        // Note: We don't need to process calendar and reminder commands here anymore
        // because they're now handled via the tool use system
    }
    
    // MARK: - Context Management
    
    /**
     * Updates the API service with the latest context data
     * This should be called after any calendar events, reminders, or memories change
     * to ensure the API has access to the latest context information
     * 
     * IMPORTANT: This method is now called before each API request to ensure
     * the date/time and all context data is always up-to-date.
     */
    func refreshContextData() async {
        print("🔄 Refreshing context data for up-to-date information")
        print("🕒 Current time: \(DateFormatter.formatCurrentDateTimeWithTimezone())")
        
        // Keep track of refresh start time for performance monitoring
        let refreshStartTime = Date()
        
        // Refresh memory content
        if let manager = memoryManager {
            // Force a fresh read from the memory manager
            let memoryContent = await manager.readMemory()
            
            // Print some sample memories for debugging
            let memories = manager.memories
            print("🔄 MEMORY CONTENT PREVIEW (First 3 items):")
            if memories.count > 0 {
                for i in 0..<min(3, memories.count) {
                    print("🔄 Memory \(i+1): \(memories[i].content) (Category: \(memories[i].category.rawValue), Importance: \(memories[i].importance))")
                }
            } else {
                print("🔄 No memories available")
            }
            
            // Update memory context in API service
            await apiService.updateMemoryContext(memoryContent)
            print("🔄 Memory context refreshed with \(memories.count) total items")
        }
        
        // Force a fresh fetch of calendar events
        print("🔄 CALENDAR REFRESH: Beginning calendar events fetch...")
        let calendarEvents = eventKitManager?.fetchUpcomingEvents(days: 7) ?? []
        let calendarContext = formatCalendarEvents(calendarEvents)
        await apiService.updateCalendarContext(calendarContext)
        print("🔄 CALENDAR REFRESH: Completed and updated API service with \(calendarEvents.count) events")
        print("🔄 CALENDAR REFRESH: Context length: \(calendarContext.count) characters")
        if !calendarEvents.isEmpty {
            print("🔄 CALENDAR REFRESH: Sample of formatted context:")
            let contextSample = String(calendarContext.prefix(300))
            print("🔄 CALENDAR REFRESH: \(contextSample)...[truncated]")
        }
        
        // Force a fresh fetch of reminders
        print("🔄 REMINDERS REFRESH: Beginning reminders fetch...")
        let reminders = await eventKitManager?.fetchReminders() ?? []
        let remindersContext = formatReminders(reminders)
        await apiService.updateRemindersContext(remindersContext)
        print("🔄 REMINDERS REFRESH: Completed and updated API service with \(reminders.count) reminders")
        print("🔄 REMINDERS REFRESH: Context length: \(remindersContext.count) characters")
        
        // Get fresh location data if needed
        let locationContext = await getLocationContext()
        await apiService.updateLocationContext(locationContext)
        print("🔄 Location context refreshed")
        
        // Log total refresh time
        let refreshTime = Date().timeIntervalSince(refreshStartTime)
        print("🔄 Context refresh completed in \(String(format: "%.2f", refreshTime)) seconds")
    }
}
