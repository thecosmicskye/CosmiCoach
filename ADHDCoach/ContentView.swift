import SwiftUI
import Combine
import UIKit
import AVFoundation

// These components are defined within the project, so no need to import them

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
    @StateObject private var keyboardManager = KeyboardManager()
    @State private var scrollViewProxy: ScrollViewProxy? = nil
    @State private var hasPreparedInitialLayout: Bool = false
    @State private var showScrollToBottom: Bool = false
    
    // MARK: - Debug State
    @State private var debugOutlineMode: DebugOutlineMode = .none
    @State private var showDebugTools: Bool = false
    
    init() {
        print("ContentView initialized at \(Date())")
    }

    // MARK: - Methods
    
    /// Ensures the navigation bar is visible - made static to avoid capturing self
    static func ensureNavigationBarIsVisible() {
        DispatchQueue.main.async {
            // Get the key window and try to find a UINavigationController
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first(where: { $0.isKeyWindow }),
               let rootViewController = window.rootViewController {
                
                // Find navigation controller in view hierarchy
                func findNavigationController(in viewController: UIViewController) -> UINavigationController? {
                    if let nav = viewController as? UINavigationController {
                        return nav
                    }
                    
                    if let tabController = viewController as? UITabBarController,
                       let selectedVC = tabController.selectedViewController {
                        return findNavigationController(in: selectedVC)
                    }
                    
                    for child in viewController.children {
                        if let navController = findNavigationController(in: child) {
                            return navController
                        }
                    }
                    
                    return nil
                }
                
                // Find and ensure navigation bar is visible
                if let navigationController = findNavigationController(in: rootViewController) {
                    if navigationController.isNavigationBarHidden {
                        navigationController.setNavigationBarHidden(false, animated: false)
                        print("📱 Navigation bar was hidden - making it visible")
                    }
                }
            }
        }
    }
    
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
        
        // Set up observer for scroll position restoration (after the keyboard manager has restored position)
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ScrollPositionRestored"),
            object: nil,
            queue: .main
        ) { [self] _ in
            // Check if we need the scroll-to-bottom button after position is restored
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                checkIfScrollViewAtBottom()
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
            keyboardManager: keyboardManager,
            text: $inputText,
            onSend: sendMessage,
            colorScheme: colorScheme,
            themeColor: themeManager.accentColor(for: colorScheme),
            isDisabled: chatManager.isProcessing,
            debugOutlineMode: debugOutlineMode
        )
        .frame(height: max(
            keyboardManager.inputViewHeight, // Already includes button row height
            keyboardManager.getInputViewPadding(
                baseHeight: inputBaseHeight,
                safeAreaPadding: safeAreaBottomPadding
            )
        ))
        .border(debugOutlineMode == .keyboardAttachedView ? Color.purple : Color.clear, width: debugOutlineMode == .keyboardAttachedView ? 2 : 0)
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
            // When layout is ready and we're not already restoring position
            if isPrepared && !keyboardManager.isRestoringScrollPosition {
                // Trigger position restoration via the keyboard manager
                keyboardManager.restoreScrollPosition {
                    // Check if we need to show the scroll-to-bottom button after restoration
                    checkIfScrollViewAtBottom()
                }
            }
        }
        .onChange(of: chatManager.messages.count) { oldCount, newCount in
            // Only auto-scroll when adding messages (not when scrolling up through history)
            // Skip if we're restoring scroll position
            if newCount > oldCount && !keyboardManager.isRestoringScrollPosition {
                DispatchQueue.main.async {
                    scrollView.scrollTo("messageBottom", anchor: .bottom)
                    showScrollToBottom = false // Hide button when we scroll to bottom
                }
            } else {
                // Check if we need to show the scroll-to-bottom button
                checkIfScrollViewAtBottom()
            }
        }
        .onChange(of: chatManager.messages.last?.content) { _, _ in
            // Auto-scroll for new content, but skip if restoring position
            if !keyboardManager.isRestoringScrollPosition {
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollView.scrollTo("messageBottom", anchor: .bottom)
                        showScrollToBottom = false // Hide button when we scroll to bottom
                    }
                }
            }
        }
        .onChange(of: chatManager.streamingUpdateCount) { _, _ in
            // Ensure scrolling happens on each streaming update, but skip if restoring position
            if !keyboardManager.isRestoringScrollPosition {
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollView.scrollTo("messageBottom", anchor: .bottom)
                        showScrollToBottom = false // Hide button when we scroll to bottom
                    }
                }
            }
        }
        .onChange(of: chatManager.operationStatusUpdateCount) { _, _ in
            // Scroll when new operation status messages are added, but skip if restoring position
            if !keyboardManager.isRestoringScrollPosition {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollView.scrollTo("messageBottom", anchor: .bottom)
                        showScrollToBottom = false // Hide button when we scroll to bottom
                    }
                }
            }
        }
        .onAppear {
            // Store the ScrollViewProxy for later use
            scrollViewProxy = scrollView
            
            // Only auto-scroll on initial appearance, not when reforegrounding
            let isInitialAppearance = !hasAppearedBefore
            
            // If it's the initial appearance, scroll to bottom
            if isInitialAppearance {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollView.scrollTo("messageBottom", anchor: .bottom)
                    }
                }
            } else {
                // Otherwise, prepare for position restoration
                hasPreparedInitialLayout = true
            }
        }
        .simultaneousGesture(
            // Use DragGesture with onEnded to reliably detect when the user finishes scrolling
            DragGesture(minimumDistance: 10)
                .onChanged { _ in
                    // Check during the drag for immediate feedback
                    checkIfScrollViewAtBottom()
                }
                .onEnded { _ in
                    // Important: recheck after the scroll momentum ends
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        checkIfScrollViewAtBottom()
                    }
                }
        )
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
                    // Constants for layout management - based on system font metrics
                    let inputBaseHeight: CGFloat = keyboardManager.defaultInputHeight
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
                        
                        // Dynamic spacer that adjusts based on keyboard presence and text input height
                        Spacer()
                            .frame(height: keyboardManager.getInputViewPadding(
                                baseHeight: inputBaseHeight,
                                safeAreaPadding: safeAreaBottomPadding
                            )) // Button row height already included in padding calculation
                            .border(debugOutlineMode == .spacer ? Color.yellow : Color.clear, width: debugOutlineMode == .spacer ? 2 : 0)
                    }
                    .frame(height: geometry.size.height)
                    .border(debugOutlineMode == .vStack ? Color.orange : Color.clear, width: 2)
                    
                    // Scroll to bottom button
                    if showScrollToBottom {
                        Button(action: scrollToBottom) {
                            ZStack {
                                Circle()
                                    .fill(Color(.secondarySystemBackground))
                                    .frame(width: 40, height: 40)
                                    .shadow(color: Color.black.opacity(0.2), radius: 3, x: 0, y: 1)
                                
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(themeManager.accentColor(for: colorScheme))
                            }
                        }
                        .padding(.bottom, 114) // Position higher above the input view (+24px total)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom) // Center horizontally
                    }
                    
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
            .navigationTitle("CosmiCoach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(colorScheme)
            .toolbarBackground(.visible, for: .navigationBar) // Force navigation bar background to be visible
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
                
                // Ensure navigation bar is visible initially and after a short delay
                Self.ensureNavigationBarIsVisible()
                
                // Important: Schedule additional checks for navigation bar visibility
                // Initial appearance may not have navigation controller ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    Self.ensureNavigationBarIsVisible()
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    Self.ensureNavigationBarIsVisible()
                }
                
                
                // Check for automatic messages
                let automaticMessagesEnabled = UserDefaults.standard.bool(forKey: "enable_automatic_responses")
                
                if hasAppearedBefore {
                    // This is a reappearance, load memory
                    Task {
                        let _ = await memoryManager.readMemory()
                        // Memory loaded - automatic messages handled by ADHDCoachApp
                        
                        // Check if we need the scroll-to-bottom button after content is loaded
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            checkIfScrollViewAtBottom()
                        }
                    }
                } else {
                    // This is the first appearance
                    Task {
                        let _ = await memoryManager.readMemory()
                        
                        // Check if we need the scroll-to-bottom button after content is loaded
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            checkIfScrollViewAtBottom()
                        }
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
                // Let the keyboard manager handle scene phase transitions
                keyboardManager.handleScenePhaseChange(from: oldPhase, to: newPhase)
                
                // Check for transition to active state (from any state)
                if newPhase == .active {
                    // Ensure navigation bar is visible when app becomes active
                    Self.ensureNavigationBarIsVisible()
                    
                    if hasAppearedBefore {
                        // Reset preparation state for next appearance
                        hasPreparedInitialLayout = false
                        
                        // Only run necessary updates if we've seen the app before
                        if let lastSessionTime = UserDefaults.standard.object(forKey: "last_app_session_time") as? TimeInterval {
                            // Load memory - automatic messages handled by ADHDCoachApp
                            Task {
                                let _ = await memoryManager.readMemory()
                            }
                        }
                    }
                }
            }
        }
    }
    // MARK: - Keyboard & Message Handling
    
    /// Dismisses the keyboard
    private func hideKeyboard() {
        keyboardManager.hideKeyboard()
    }
    
    /// Checks if the scroll view is at the bottom
    private func checkIfScrollViewAtBottom() {
        // Skip if we're programmatically scrolling to bottom
        if keyboardManager.isRestoringScrollPosition {
            return
        }
        
        DispatchQueue.main.async {
            let isAtBottom = self.keyboardManager.isScrollViewAtBottom()
            
            // Determine if button should be shown - invert the at-bottom check
            let shouldShowButton = !isAtBottom
            
            // Only animate if there's an actual change to avoid unnecessary animations
            if self.showScrollToBottom != shouldShowButton {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.showScrollToBottom = shouldShowButton
                }
            }
        }
    }
    
    /// Scrolls to the bottom of the chat
    private func scrollToBottom() {
        // Hide the button immediately to prevent it from showing during scroll animation
        withAnimation(.easeInOut(duration: 0.2)) {
            showScrollToBottom = false
        }
        
        // Use ScrollViewProxy if available for smooth SwiftUI scrolling
        if let scrollView = scrollViewProxy {
            withAnimation(.easeOut(duration: 0.3)) {
                scrollView.scrollTo("messageBottom", anchor: .bottom)
            }
        } else {
            // Fall back to UIKit approach via the keyboard manager
            keyboardManager.scrollToBottom {
                // Ensure button stays hidden after scroll completes
                if self.showScrollToBottom {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.showScrollToBottom = false
                    }
                }
            }
        }
    }
    
    
    /// Processes and sends user message
    private func sendMessage() {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        // Store message before clearing input
        let messageToSend = trimmedText
        
        // Add user message to chat immediately
        chatManager.addUserMessage(content: messageToSend)
        
        // Clear input text AFTER adding the message
        inputText = ""
        
        // Reset text input height immediately using the keyboard manager
        DispatchQueue.main.async {
            keyboardManager.resetInputViewHeight()
        }
        
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








