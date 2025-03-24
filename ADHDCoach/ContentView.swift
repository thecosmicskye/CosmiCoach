import SwiftUI
import Combine
import UIKit
import AVFoundation

// Debug outline mode enum for visual debugging
enum DebugOutlineMode: String, CaseIterable {
    case none = "None"
    case scrollView = "ScrollView"
    case keyboardAttachedView = "Keyboard View"
    case messageList = "Message List"
    case spacer = "Spacer"
    case vStack = "VStack"
    case zStack = "ZStack"
    case textInput = "Text Input"
    case safeArea = "Safe Area"
}

// Flag to enable/disable input view layout debugging logs
var inputViewLayoutDebug = false

struct ContentView: View {
    // MARK: - Environment Objects
    @EnvironmentObject private var chatManager: ChatManager
    @EnvironmentObject private var eventKitManager: EventKitManager
    @EnvironmentObject private var memoryManager: MemoryManager
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var speechManager: SpeechManager
    @EnvironmentObject private var multipeerService: MultipeerService
    // Use ObservedObject instead of EnvironmentObject for locationManager to prevent cascading rebuilds
    @ObservedObject private var locationManager = LocationManager()
    
    // MARK: - Environment Values
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    
    // MARK: - State
    @AppStorage("hasAppearedBefore") private var hasAppearedBefore = false
    @State private var showingSettings = false
    @State private var inputText = ""
    @StateObject private var keyboardState = KeyboardState()
    @State private var scrollPosition: CGPoint = {
        // Load saved position from UserDefaults on initialization
        if let savedY = UserDefaults.standard.object(forKey: "saved_scroll_position_y") as? CGFloat, savedY > 0 {
            return CGPoint(x: 0, y: savedY)
        }
        return .zero
    }()
    @State private var lastKnownValidScenePhase: ScenePhase = .active
    @State private var isRestoringScrollPosition: Bool = false
    @State private var scrollViewProxy: ScrollViewProxy? = nil
    @State private var hasPreparedInitialLayout: Bool = false
    
    // MARK: - Debug State
    @State private var debugOutlineMode: DebugOutlineMode = .none
    @State private var showDebugTools: Bool = false
    
    init() {
        print("ContentView initialized at \(Date())")
    }

    // MARK: - Methods
    /// Sets up notification observer for chat history deletion and scroll position restoration
    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ChatHistoryDeleted"),
            object: nil,
            queue: .main
        ) { [self] _ in
            Task { @MainActor in
                chatManager.messages = []
                await chatManager.checkAndSendAutomaticMessageAfterHistoryDeletion()
            }
        }
        
        // Set up observers for saving/restoring scroll position
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [self] _ in
            // Save scroll position before going to background
            if let scrollView = findScrollView() {
                let newPosition = scrollView.contentOffset
                
                // Store current scroll position from UI before app transitions
                if newPosition.y > 0 {
                    // Save the position directly to UserDefaults without updating state
                    print("📱 Saving scroll position from notification: \(newPosition.y)")
                    UserDefaults.standard.set(newPosition.y, forKey: "saved_scroll_position_y")
                    
                    // Also update in-memory value
                    scrollPosition = newPosition
                } else if scrollPosition.y <= 0 {
                    print("⚠️ Not saving scroll position from notification: current=\(newPosition.y), saved=\(scrollPosition.y)")
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [self] _ in
            // Important: Do NOT try to restore scroll position by directly modifying scroll view
            // Instead, set flags so that our layout-driven restoration can work properly
            // This prevents the flash to top before restoration
            
            // CRITICAL: Immediately set this flag to prevent any auto-scrolling attempts
            isRestoringScrollPosition = true
            
            // Reset layout preparation state to false first
            hasPreparedInitialLayout = false
            
            // ALWAYS use the UserDefaults value when restoring from background
            if let savedY = UserDefaults.standard.object(forKey: "saved_scroll_position_y") as? CGFloat, savedY > 0 {
                scrollPosition = CGPoint(x: 0, y: savedY)
                print("📱 Retrieved saved position from UserDefaults: \(savedY)")
                
                // Schedule layout preparation flag to be set after a brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    hasPreparedInitialLayout = true
                }
            } else if scrollPosition.y > 0 {
                print("📱 Using existing scroll position: \(scrollPosition.y)")
                
                // Schedule layout preparation flag to be set after a brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    hasPreparedInitialLayout = true
                }
            } else {
                print("⚠️ No valid scroll position to restore, will default to top")
                isRestoringScrollPosition = false
            }
        }
    }
    
    // MARK: - View Building Methods
    
    /// Creates the debug border for the message list
    @ViewBuilder
    private func messageListBorder() -> some View {
        if debugOutlineMode == .messageList {
            Color.purple.frame(width: 2)
        } else {
            Color.clear.frame(width: 0)
        }
    }
    
    /// Creates the debug border for the scroll view
    @ViewBuilder
    private func scrollViewBorder() -> some View {
        if debugOutlineMode == .scrollView {
            Color.green.frame(width: 2)
        } else {
            Color.clear.frame(width: 0)
        }
    }
    
    /// Creates the debug border for the spacer
    @ViewBuilder
    private func spacerBorder() -> some View {
        if debugOutlineMode == .spacer {
            Color.yellow.frame(width: 2)
        } else {
            Color.clear.frame(width: 0)
        }
    }
    
    /// Creates the keyboard attached view
    private func createKeyboardAttachedView(inputBaseHeight: CGFloat, safeAreaBottomPadding: CGFloat) -> some View {
        KeyboardAttachedView(
            keyboardState: keyboardState,
            text: $inputText,
            onSend: sendMessage,
            colorScheme: colorScheme,
            themeColor: themeManager.accentColor(for: colorScheme),
            isDisabled: chatManager.isProcessing,
            debugOutlineMode: debugOutlineMode
        )
        .frame(height: keyboardState.getInputViewPadding(
            baseHeight: inputBaseHeight,
            safeAreaPadding: safeAreaBottomPadding
        ))
        .border(debugOutlineMode == .keyboardAttachedView ? Color.purple : Color.clear, width: 2)
    }
    
    /// Creates the message content view
    @ViewBuilder
    private func messageContentView() -> some View {
        if !chatManager.initialLoadComplete {
            // Display loading indicator during initial load
            VStack {
                Spacer()
                ProgressView("Loading...")
                    .progressViewStyle(CircularProgressViewStyle())
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .border(debugOutlineMode == .messageList ? Color.purple : Color.clear, width: 2)
        } else if chatManager.messages.isEmpty {
            EmptyStateView()
                .border(debugOutlineMode == .messageList ? Color.purple : Color.clear, width: 2)
        } else {
            // Direct implementation instead of using MessageListView
            VStack(spacing: 12) {
                ForEach(chatManager.messages) { message in
                    VStack(spacing: 4) {
                        MessageBubbleView(message: message)
                            .padding(.horizontal)
                        
                        // Show operation status messages after AI messages
                        if !message.isUser && message.isComplete {
                            ForEach(chatManager.combinedStatusMessagesForMessage(message)) { statusMessage in
                                OperationStatusView(statusMessage: statusMessage)
                                    .padding(.horizontal)
                                    .id("status-\(statusMessage.id)")
                            }
                        }
                    }
                    .id("message-\(message.id)")
                }
            }
            .padding(.top, 8)
            .border(debugOutlineMode == .messageList ? Color.purple : Color.clear, width: 2)
        }
    }
    
    /// Creates the debug scroll view decoration
    @ViewBuilder
    private func scrollViewDebugDecoration() -> some View {
        if debugOutlineMode == .scrollView {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .border(Color.green, width: 3)
        }
    }
    
    /// Creates the settings button
    private func settingsButton() -> some View {
        Button(action: {
            hideKeyboard()
            showingSettings = true
        }) {
            Image(systemName: "gear")
                .font(.system(size: 22))
                .foregroundColor(themeManager.accentColor(for: colorScheme))
        }
    }
    
    /// Creates the debug outline menu
    @ViewBuilder
    private func debugOutlineMenu() -> some View {
        if showDebugTools {
            Menu {
                ForEach(DebugOutlineMode.allCases, id: \.self) { mode in
                    Button(mode.rawValue) {
                        debugOutlineMode = mode
                    }
                }
            } label: {
                Image(systemName: "square.dashed")
                    .font(.system(size: 18))
                    .foregroundColor(debugOutlineMode != .none ? .red : .gray)
            }
        }
    }

    /// Creates the scrollable message area
    private func createScrollView(scrollView: ScrollViewProxy) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            // Add spacer for navigation bar to prevent content from pushing under it
            Spacer()
                .frame(height: 1)
                .id("navigationBarSpacer")
                
            // Message content - either empty state or message list
            messageContentView()
                .id("message-content") // Stable identifier for content
            
            // Debug border for ScrollView
            scrollViewDebugDecoration()
            
            // Bottom anchor for scrolling
            Color.clear
                .frame(height: 1)
                .id("messageBottom")
        }
        .scrollDisabled(false) // Ensure scrolling is enabled
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: hasPreparedInitialLayout) { oldValue, isPrepared in
            // When layout is ready and we have a saved position to restore
            if isPrepared && isRestoringScrollPosition {
                // Get the most up-to-date position from UserDefaults
                let positionFromUserDefaults: CGFloat? = UserDefaults.standard.object(forKey: "saved_scroll_position_y") as? CGFloat
                
                // Determine the best position to use
                var finalPosition: CGPoint = .zero
                var hasValidPosition = false
                
                // Check UserDefaults first as it's more reliable across app state transitions
                if let savedY = positionFromUserDefaults, savedY > 0 {
                    finalPosition = CGPoint(x: 0, y: savedY)
                    hasValidPosition = true
                    print("📱 Using position from UserDefaults: \(savedY)")
                }
                // Fall back to in-memory position if UserDefaults doesn't have a value
                else if scrollPosition.y > 0 {
                    finalPosition = scrollPosition
                    hasValidPosition = true
                    print("📱 Using in-memory position: \(scrollPosition.y)")
                }
                
                if hasValidPosition, let scrollView = findScrollView() {
                    // Verify scroll view is ready with a valid content size
                    let contentSize = scrollView.contentSize.height
                    let boundsHeight = scrollView.bounds.height
                    
                    // Only proceed if content has actual size
                    if contentSize > 0 {
                        let maxValidY = max(0, contentSize - boundsHeight)
                        
                        // Ensure position is valid for current content
                        let safeY = min(finalPosition.y, maxValidY)
                        finalPosition.y = safeY
                        
                        print("📱 Restoring scroll position after layout ready: \(finalPosition.y) (content size: \(contentSize))")
                        
                        // Store finalized position for future reference
                        scrollPosition = finalPosition
                        
                        // Apply saved position with guaranteed no animation
                        UIView.performWithoutAnimation {
                            scrollView.contentOffset = finalPosition
                            scrollView.layoutIfNeeded()
                        }
                        
                        // Ensure it stuck by setting it again after a very brief delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            UIView.performWithoutAnimation {
                                scrollView.contentOffset = finalPosition
                            }
                            
                            // Reset the restoration flag
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                isRestoringScrollPosition = false
                            }
                        }
                    } else {
                        // Content not yet fully laid out
                        print("⚠️ Content size not ready yet: \(contentSize), will try setting position directly")
                        
                        // Try setting position directly anyway
                        UIView.performWithoutAnimation {
                            scrollView.contentOffset = finalPosition
                        }
                        
                        // Reset after delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isRestoringScrollPosition = false
                        }
                    }
                } else {
                    print("⚠️ No valid scroll position to restore")
                    isRestoringScrollPosition = false
                }
            }
        }
        .onChange(of: chatManager.messages.count) { oldCount, newCount in
            // Only auto-scroll when adding messages (not when scrolling up through history)
            // Skip if we're restoring scroll position
            if newCount > oldCount && !isRestoringScrollPosition {
                DispatchQueue.main.async {
                    scrollView.scrollTo("messageBottom", anchor: .bottom)
                }
            }
        }
        .onChange(of: chatManager.messages.last?.content) { _, _ in
            // Auto-scroll for new content, but skip if restoring position
            if !isRestoringScrollPosition {
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollView.scrollTo("messageBottom", anchor: .bottom)
                    }
                }
            }
        }
        .onChange(of: chatManager.streamingUpdateCount) { _, _ in
            // Ensure scrolling happens on each streaming update, but skip if restoring position
            if !isRestoringScrollPosition {
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollView.scrollTo("messageBottom", anchor: .bottom)
                    }
                }
            }
        }
        .onChange(of: chatManager.operationStatusUpdateCount) { _, _ in
            // Scroll when new operation status messages are added, but skip if restoring position
            if !isRestoringScrollPosition {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollView.scrollTo("messageBottom", anchor: .bottom)
                    }
                }
            }
        }
        .onAppear {
            // Store the ScrollViewProxy for later use
            scrollViewProxy = scrollView
            
            // Only auto-scroll on initial appearance, not when reforegrounding
            let isInitialAppearance = !hasAppearedBefore
            
            // Immediately set flag to prevent auto-scrolling if we have a saved position
            if scrollPosition.y > 0 {
                isRestoringScrollPosition = true
                
                // We need to wait for layout to complete before we can restore position
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    hasPreparedInitialLayout = true
                }
            } 
            // Scroll to bottom when view appears with a slight delay to ensure layout is complete
            // Skip if we're restoring scroll position or if this is a reforegrounding
            else if !isRestoringScrollPosition && isInitialAppearance {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollView.scrollTo("messageBottom", anchor: .bottom)
                    }
                }
            }
        }
        .border(debugOutlineMode == .scrollView ? Color.green : Color.clear, width: 2)
    }
    
    /// Creates the settings sheet
    private func settingsSheet() -> some View {
        SettingsView()
            .environmentObject(themeManager)
            .environmentObject(memoryManager)
            .environmentObject(locationManager)
            .environmentObject(chatManager)
            .environmentObject(speechManager)
            .onAppear {
                hideKeyboard()
            }
    }
    
    // MARK: - Main View Body
    var body: some View {
        let _ = Self._printChanges() // Add view body change tracking for debugging
        
        return NavigationStack {
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    // Constants for layout management
                    let inputBaseHeight: CGFloat = 54
                    let safeAreaBottomPadding: CGFloat = 20
                    
                    // Debug border around entire ZStack
                    if debugOutlineMode == .zStack {
                        Color.clear.border(Color.blue, width: 4)
                    }
                    
                    // Content VStack
                    VStack(spacing: 0) {
                        // Main scrollable content area with message list
                        ScrollViewReader { scrollView in
                            createScrollView(scrollView: scrollView)
                        }
                        
                        // Dynamic spacer that adjusts based on keyboard presence
                        Spacer()
                            .frame(height: keyboardState.getInputViewPadding(
                                baseHeight: inputBaseHeight,
                                safeAreaPadding: safeAreaBottomPadding
                            ))
                            .border(debugOutlineMode == .spacer ? Color.yellow : Color.clear, width: 2)
                    }
                    .frame(height: geometry.size.height)
                    .border(debugOutlineMode == .vStack ? Color.orange : Color.clear, width: 2)
                    
                    // Keyboard attached input view
                    createKeyboardAttachedView(
                        inputBaseHeight: inputBaseHeight,
                        safeAreaBottomPadding: safeAreaBottomPadding
                    )
                }
            }
            .safeAreaInset(edge: .top) {
                // Preserve consistent space for the navigation bar
                Color.clear
                    .frame(height: 1)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea(.keyboard)
            .navigationTitle("Cosmic Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(colorScheme)
            .tint(themeManager.accentColor(for: colorScheme))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    settingsButton()
                }
                
                // Debug outline toggle (only shown when debug tools are enabled)
                ToolbarItem(placement: .navigationBarTrailing) {
                    debugOutlineMenu()
                }
            }
            .sheet(isPresented: $showingSettings) {
                settingsSheet()
            }
            .applyThemeColor()
            .onAppear {
                // Connect memory manager to chat manager
                chatManager.setMemoryManager(memoryManager)
                
                // Setup notification observers
                setupNotificationObserver()
                
                // Check for automatic messages
                let automaticMessagesEnabled = UserDefaults.standard.bool(forKey: "enable_automatic_responses")
                
                if hasAppearedBefore {
                    // This is a reappearance, load memory
                    Task {
                        let _ = await memoryManager.readMemory()
                        // Memory loaded - automatic messages handled by ADHDCoachApp
                    }
                } else {
                    // This is the first appearance
                    Task {
                        let _ = await memoryManager.readMemory()
                    }
                    // Mark that we've appeared before for next time
                    hasAppearedBefore = true
                }
            }
            // Add multipeer conflict resolution alert
            .alert("Message History Conflict", isPresented: .init(
                get: { 
                    // Use EnvironmentObject directly
                    return multipeerService.hasPendingSyncDecision
                },
                set: { _ in }
            )) {
                Button("Use Remote History", role: .destructive) {
                    multipeerService.resolveMessageSyncConflict(useRemote: true)
                }
                
                Button("Keep Local History", role: .cancel) {
                    multipeerService.resolveMessageSyncConflict(useRemote: false)
                }
            } message: {
                if let peerID = multipeerService.pendingSyncPeer {
                    Text("There is a conflict between your message history and \(peerID.displayName)'s history. Which one would you like to keep?")
                } else {
                    Text("There is a conflict between message histories. Which one would you like to keep?")
                }
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                print("⏱️ Scene phase transition: \(oldPhase) -> \(newPhase)")
                
                // Only operate on scene phase changes in certain directions
                if oldPhase == .active && (newPhase == .inactive || newPhase == .background) {
                    // This is a transition from active to background/inactive
                    lastKnownValidScenePhase = oldPhase
                    
                    if let scrollView = findScrollView() {
                        let newPosition = scrollView.contentOffset
                        
                        // Only save valid scroll positions and protect from negative values
                        if newPosition.y > 0 {
                            // First save to UserDefaults
                            UserDefaults.standard.set(newPosition.y, forKey: "saved_scroll_position_y")
                            
                            // Then update state
                            scrollPosition = newPosition
                            print("📱 Saving scroll position from scene phase: \(newPosition.y)")
                        } else if let savedY = UserDefaults.standard.object(forKey: "saved_scroll_position_y") as? CGFloat, savedY > 0 {
                            // If current position is invalid but we have a saved one, keep using it
                            print("⚠️ Current position invalid: \(newPosition.y), keeping saved: \(savedY)")
                        } else {
                            print("⚠️ No valid scroll position to save: current=\(newPosition.y)")
                        }
                    }
                } 
                else if newPhase == .inactive && oldPhase == .background {
                    // Skip the background -> inactive transition, as it often gives invalid scroll positions
                    print("📱 Skipping scroll position check during background -> inactive transition")
                    lastKnownValidScenePhase = newPhase
                }
                
                // Check for transition to active state (from any state)
                if newPhase == .active && hasAppearedBefore {
                    // Reset preparation state for next appearance
                    hasPreparedInitialLayout = false
                    
                    // Only run necessary updates if we've seen the app before
                    if let lastSessionTime = UserDefaults.standard.object(forKey: "last_app_session_time") as? TimeInterval {
                        // Load memory - automatic messages handled by ADHDCoachApp
                        Task {
                            let _ = await memoryManager.readMemory()
                        }
                    }
                    
                    // Don't try to restore scroll here - we'll let the onAppear and onChange do it
                }
            }
        }
    }
    // MARK: - Keyboard & Message Handling
    
    /// Dismisses the keyboard
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    /// Finds the main ScrollView in the view hierarchy
    private func findScrollView() -> UIScrollView? {
        // Find the UIScrollView in the view hierarchy
        let allWindows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        
        guard let window = allWindows.first(where: { $0.isKeyWindow }) else {
            return nil
        }
        
        return findScrollView(in: window)
    }
    
    /// Recursive helper to find a ScrollView in a view hierarchy
    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView {
            return scrollView
        }
        
        for subview in view.subviews {
            if let scrollView = findScrollView(in: subview) {
                return scrollView
            }
        }
        
        return nil
    }
    
    
    /// Processes and sends user message
    private func sendMessage() {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        // Store message and clear input
        let messageToSend = trimmedText
        inputText = ""
        
        // Add user message to chat immediately
        chatManager.addUserMessage(content: messageToSend)
        
        // Dismiss keyboard with animation
        withAnimation(.easeOut(duration: 0.25)) {
            hideKeyboard()
        }
        
        // Process message asynchronously
        Task {
            // Small delay for animation
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            // Safety timeout to prevent permanent UI locking
            let timeoutTask = Task {
                // Wait for 30 seconds maximum
                try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                
                // If we're still processing after 30 seconds, reset the state
                await MainActor.run {
                    if chatManager.isProcessing {
                        print("⚠️ Message processing timed out after 30 seconds - resetting isProcessing state")
                        chatManager.isProcessing = false
                    }
                }
            }
            
            // Get context data
            let calendarEvents = eventKitManager.fetchUpcomingEvents(days: 7)
            let reminders = await eventKitManager.fetchReminders()
            
            // Send to API
            await chatManager.sendMessageToClaude(
                userMessage: messageToSend,
                calendarEvents: calendarEvents,
                reminders: reminders
            )
            
            // Cancel the timeout task if we finish normally
            timeoutTask.cancel()
        }
    }
}

// MARK: - Supporting Views

/// Displays welcome message when no chat messages exist
struct EmptyStateView: View {
    var body: some View {
        VStack {
            Spacer()
            Text("Welcome to Cosmic Coach")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Type a message to get started")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }
}

// Removed MessageHeightCache class as it's no longer needed

// Preference key to capture message heights
struct MessageHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}


// MARK: - Previews

#Preview("Main View") {
    ContentView()
        .environmentObject(ChatManager())
        .environmentObject(EventKitManager())
        .environmentObject(MemoryManager())
        .environmentObject(ThemeManager())
        .environmentObject(LocationManager())
        .environmentObject(SpeechManager())
        .environmentObject(MultipeerService())
}

#Preview("Message Components") {
    VStack {
        VStack(spacing: 12) {
            MessageBubbleView(message: ChatMessage(id: UUID(), content: "Hello there!", timestamp: Date(), isUser: true, isComplete: true))
                .padding(.horizontal)
            
            MessageBubbleView(message: ChatMessage(id: UUID(), content: "Hi! How can I help you today?", timestamp: Date(), isUser: false, isComplete: true))
                .padding(.horizontal)
        }
        .frame(height: 300)
        
        Divider()
        
        EmptyStateView()
            .frame(height: 300)
    }
    .padding(.horizontal)
    .environmentObject(ThemeManager())
    .environmentObject(ChatManager())
    .environmentObject(SpeechManager())
    .environmentObject(MultipeerService())
}



// MARK: - KeyboardState
class KeyboardState: ObservableObject {
    /// Current keyboard height when visible, or 0 when hidden
    @Published var keyboardOffset: CGFloat = 0
    
    /// Whether the keyboard is currently visible
    @Published var isKeyboardVisible: Bool = false
    
    /// Updates keyboard state if there's an actual change to prevent unnecessary view updates
    /// - Parameters:
    ///   - visible: Whether keyboard is visible
    ///   - height: Height of keyboard in points
    func setKeyboardVisible(_ visible: Bool, height: CGFloat) {
        // Only trigger updates when there's an actual change
        let heightChanged = visible && keyboardOffset != height
        let visibilityChanged = isKeyboardVisible != visible
        
        if visibilityChanged || heightChanged {
            isKeyboardVisible = visible
            keyboardOffset = visible ? height : 0
        }
    }
    
    /// Returns the appropriate padding for the input view based on current keyboard state
    /// - Parameters:
    ///   - baseHeight: Default height to use when keyboard is hidden
    ///   - safeAreaPadding: Additional padding to account for safe area
    /// - Returns: The calculated padding value
    func getInputViewPadding(baseHeight: CGFloat, safeAreaPadding: CGFloat) -> CGFloat {
        return isKeyboardVisible ? keyboardOffset + safeAreaPadding : baseHeight
    }
}

// MARK: - TextInputView
struct TextInputView: View {
    // MARK: Properties
    
    // Input properties
    @Binding var text: String
    var onSend: () -> Void
    
    // Visual properties
    var colorScheme: ColorScheme
    var themeColor: Color
    var isDisabled: Bool
    var debugOutlineMode: DebugOutlineMode
    
    // Local state
    @State private var isSending = false
    
    // Computed properties
    private var isButtonDisabled: Bool {
        isDisabled || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending
    }
    
    private var buttonColor: Color {
        isButtonDisabled ? .gray : themeColor
    }
    
    // MARK: Body
    var body: some View {
        HStack {
            // Text input field
            TextField("Message", text: $text)
                .padding(.horizontal, 15)
                .padding(.vertical, 8)
                .border(debugOutlineMode == .textInput ? Color.pink : Color.clear, width: 1)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .animation(nil, value: text) // Prevent animation during transitions
            
            // Send button
            Button {
                guard !isSending else { return }
                isSending = true
                onSend()
                
                // Reset button state after a brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isSending = false
                }
            } label: {
                ZStack {
                    Circle()
                        .foregroundColor(buttonColor)
                        .frame(width: 30, height: 30)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundColor(isButtonDisabled ? Color(.systemBackground) : .white)
                }
            }
            .disabled(isButtonDisabled)
            .animation(.easeInOut(duration: 0.1), value: isButtonDisabled)
        }
        .padding(.horizontal)
        .border(debugOutlineMode == .textInput ? Color.mint : Color.clear, width: 2)
        .transaction { transaction in
            transaction.animation = nil // Prevent position animations
        }
    }
}

// MARK: - KeyboardAttachedView
struct KeyboardAttachedView: UIViewControllerRepresentable {
    // MARK: Properties
    var keyboardState: KeyboardState
    @Binding var text: String
    var onSend: () -> Void
    var colorScheme: ColorScheme
    var themeColor: Color
    var isDisabled: Bool
    var debugOutlineMode: DebugOutlineMode
    
    // MARK: UIViewControllerRepresentable
    func makeUIViewController(context: Context) -> KeyboardObservingViewController {
        print("KeyboardAttachedView.makeUIViewController")
        return KeyboardObservingViewController(
            keyboardState: keyboardState,
            text: $text,
            onSend: onSend,
            colorScheme: colorScheme,
            themeColor: themeColor,
            isDisabled: isDisabled,
            debugOutlineMode: debugOutlineMode
        )
    }
    
    func updateUIViewController(_ uiViewController: KeyboardObservingViewController, context: Context) {
        // Only update content if there are actual changes to avoid unnecessary view rebuilds
        let textChanged = uiViewController.text.wrappedValue != text
        let colorSchemeChanged = uiViewController.colorScheme != colorScheme
        let themeColorChanged = uiViewController.themeColor != themeColor
        let disabledStateChanged = uiViewController.isDisabled != isDisabled
        let debugModeChanged = uiViewController.debugOutlineMode != debugOutlineMode
        
        if textChanged || colorSchemeChanged || themeColorChanged || disabledStateChanged || debugModeChanged {
            uiViewController.updateContent(
                text: text,
                colorScheme: colorScheme,
                themeColor: themeColor,
                isDisabled: isDisabled,
                debugOutlineMode: debugOutlineMode
            )
        }
    }
}

// MARK: - KeyboardObservingViewController
class KeyboardObservingViewController: UIViewController {
    // MARK: Views
    private var keyboardTrackingView = UIView()
    private var safeAreaView = UIView()
    private var inputHostView: UIHostingController<TextInputView>!
    
    // MARK: Constants
    private let inputViewHeight: CGFloat = 54
    private let keyboardVisibilityThreshold: CGFloat = 100
    
    // MARK: Properties
    internal var keyboardState: KeyboardState // Changed from private to internal
    private var bottomConstraint: NSLayoutConstraint?
    internal var text: Binding<String> // Changed from private to internal
    internal var onSend: () -> Void // Changed from private to internal
    internal var colorScheme: ColorScheme // Changed from private to internal
    internal var themeColor: Color // Changed from private to internal
    internal var isDisabled: Bool // Changed from private to internal
    internal var debugOutlineMode: DebugOutlineMode // Changed from private to internal
    
    // MARK: Lifecycle
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    init(
        keyboardState: KeyboardState,
        text: Binding<String>,
        onSend: @escaping () -> Void,
        colorScheme: ColorScheme,
        themeColor: Color,
        isDisabled: Bool,
        debugOutlineMode: DebugOutlineMode
    ) {
        self.keyboardState = keyboardState
        self.text = text
        self.onSend = onSend
        self.colorScheme = colorScheme
        self.themeColor = themeColor
        self.isDisabled = isDisabled
        self.debugOutlineMode = debugOutlineMode
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: View Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupKeyboardObservers()
    }
    
    // MARK: View Setup
    private func setupViews() {
        setupKeyboardTrackingView()
        setupSafeAreaView()
        setupTextInputView()
        updateDebugBorders()
    }
    
    private func setupSafeAreaView() {
        safeAreaView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(safeAreaView)
        
        NSLayoutConstraint.activate([
            safeAreaView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            safeAreaView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            safeAreaView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            safeAreaView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    private func setupKeyboardTrackingView() {
        keyboardTrackingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardTrackingView)
        
        NSLayoutConstraint.activate([
            // Pin horizontally to view edges
            keyboardTrackingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardTrackingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // Track keyboard vertically
            keyboardTrackingView.topAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            keyboardTrackingView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.bottomAnchor)
        ])
    }
    
    private func setupTextInputView() {
        // Create SwiftUI view
        let textView = createTextInputView()
        inputHostView = UIHostingController(rootView: textView)
        
        // Add hosting controller as child
        addChild(inputHostView)
        inputHostView.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputHostView.view)
        inputHostView.didMove(toParent: self)
        
        // Set up constraints
        NSLayoutConstraint.activate([
            inputHostView.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputHostView.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputHostView.view.heightAnchor.constraint(equalToConstant: inputViewHeight)
        ])
        
        // Attach to keyboard
        bottomConstraint = inputHostView.view.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        bottomConstraint?.isActive = true
    }
    
    private func createTextInputView() -> TextInputView {
        return TextInputView(
            text: text,
            onSend: onSend,
            colorScheme: colorScheme,
            themeColor: themeColor,
            isDisabled: isDisabled,
            debugOutlineMode: debugOutlineMode
        )
    }
    
    // MARK: Content Updates
    func updateContent(
        text: String,
        colorScheme: ColorScheme,
        themeColor: Color,
        isDisabled: Bool,
        debugOutlineMode: DebugOutlineMode
    ) {
        // Check for changes that would require us to update the view
        let textChanged = self.text.wrappedValue != text
        let themeColorChanged = self.themeColor != themeColor
        let disabledStateChanged = self.isDisabled != isDisabled
        let debugModeChanged = self.debugOutlineMode != debugOutlineMode
        let colorSchemeChanged = self.colorScheme != colorScheme
        let visualPropertiesChanged = themeColorChanged || disabledStateChanged || debugModeChanged || colorSchemeChanged
        
        // Skip full update if nothing has changed
        if !textChanged && !visualPropertiesChanged {
            return
        }
        
        print("KeyboardObservingViewController.updateContent - updating \(textChanged ? "text" : "") \(visualPropertiesChanged ? "visuals" : "")")
        
        // Update text (without animation if clearing)
        if textChanged && text.isEmpty {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.text.wrappedValue = text
            CATransaction.commit()
        } else if textChanged {
            self.text.wrappedValue = text
        }
        
        // Update other properties
        if visualPropertiesChanged {
            self.colorScheme = colorScheme
            self.themeColor = themeColor
            self.isDisabled = isDisabled
            self.debugOutlineMode = debugOutlineMode
            
            // Update SwiftUI view only if visual properties changed
            inputHostView.rootView = createTextInputView()
            updateSwiftUIViewPosition()
        }
        
        // Update debug visualization
        if debugModeChanged {
            updateDebugBorders()
            
            // Update view order based on debug mode
            if debugOutlineMode == .safeArea {
                view.bringSubviewToFront(safeAreaView)
            } else if debugOutlineMode == .keyboardAttachedView {
                view.bringSubviewToFront(keyboardTrackingView)
            }
            
            // Always keep input view on top
            if let hostView = inputHostView?.view {
                view.bringSubviewToFront(hostView)
            }
        }
    }
    
    // MARK: Debug Visualization
    private func updateDebugBorders() {
        let isKeyboardAttachedDebug = debugOutlineMode == .keyboardAttachedView
        let isSafeAreaDebug = debugOutlineMode == .safeArea
        let isTextInputDebug = debugOutlineMode == .textInput
        
        // Keyboard tracking view
        keyboardTrackingView.layer.borderWidth = isKeyboardAttachedDebug ? 2 : 0
        keyboardTrackingView.layer.borderColor = UIColor.systemBlue.cgColor
        keyboardTrackingView.backgroundColor = isKeyboardAttachedDebug ? 
            UIColor.systemBlue.withAlphaComponent(0.2) : UIColor.systemBackground
        
        // Safe area visualization
        safeAreaView.layer.borderWidth = isSafeAreaDebug ? 2 : 0
        safeAreaView.layer.borderColor = UIColor.systemGreen.cgColor
        safeAreaView.backgroundColor = isSafeAreaDebug ? 
            UIColor.systemGreen.withAlphaComponent(0.1) : .clear
        
        // Main controller view
        view.layer.borderWidth = (isKeyboardAttachedDebug || isSafeAreaDebug) ? 1 : 0
        view.layer.borderColor = UIColor.systemTeal.cgColor
        
        // Text input host view
        if let hostView = inputHostView?.view {
            hostView.layer.borderWidth = isTextInputDebug ? 2 : 0
            hostView.layer.borderColor = UIColor.systemIndigo.cgColor
        }
    }
    
    // MARK: Keyboard Observation
    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }
    
    @objc func keyboardWillChangeFrame(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let curve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber else {
            return
        }
        
        // Check keyboard visibility
        let isVisible = keyboardFrame.minY < UIScreen.main.bounds.height
        
        // Update state
        keyboardState.setKeyboardVisible(isVisible, height: keyboardFrame.height)
        
        // Match keyboard animation exactly
        let curveValue = curve.uintValue
        let animationOptions = UIView.AnimationOptions(rawValue: curveValue << 16)
        
        // Animate with matching curve
        UIView.animate(withDuration: duration, delay: 0, options: [animationOptions, .beginFromCurrentState]) {
            self.view.layoutIfNeeded()
            self.updateSwiftUIViewPosition()
        }
    }
    
    private func updateSwiftUIViewPosition() {
        // Force layout update
        inputHostView.view.setNeedsLayout()
        inputHostView.view.layoutIfNeeded()
    }
    
    @objc func keyboardWillHide(_ notification: Notification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let curve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber else {
            return
        }
        
        // Update state
        keyboardState.setKeyboardVisible(false, height: 0)
        
        // Match keyboard animation exactly
        let curveValue = curve.uintValue
        let animationOptions = UIView.AnimationOptions(rawValue: curveValue << 16)
        
        // Animate with matching curve
        UIView.animate(withDuration: duration, delay: 0, options: [animationOptions, .beginFromCurrentState]) {
            self.view.layoutIfNeeded()
            self.updateSwiftUIViewPosition()
        }
    }
    
    // MARK: Interactive Gesture Handling
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        // Update SwiftUI view layout
        updateSwiftUIViewPosition()
        
        // Handle interactive keyboard dismissal when no animation is in progress
        guard let window = view.window, UIView.inheritedAnimationDuration == 0 else { return }
        updateKeyboardPositionDuringInteractiveGesture(in: window)
    }
    
    private func updateKeyboardPositionDuringInteractiveGesture(in window: UIWindow) {
        // Get keyboard position
        let keyboardFrame = view.keyboardLayoutGuide.layoutFrame
        let screenHeight = window.frame.height
        
        // Convert to window coordinates
        let keyboardFrameInWindow = view.convert(keyboardFrame, to: window)
        let keyboardTop = keyboardFrameInWindow.minY
        
        // Calculate visibility
        let keyboardHeight = screenHeight - keyboardTop
        let isVisible = keyboardTop < screenHeight && keyboardHeight > keyboardVisibilityThreshold
        
        // Check if update needed
        let heightDifference = abs(keyboardState.keyboardOffset - (isVisible ? keyboardHeight : 0))
        let shouldUpdate = heightDifference > 1.0 || keyboardState.isKeyboardVisible != isVisible
        
        if shouldUpdate {
            // Update state and layout
            keyboardState.setKeyboardVisible(isVisible, height: isVisible ? keyboardHeight : 0)
            view.layoutIfNeeded()
            updateSwiftUIViewPosition()
        }
    }
}

