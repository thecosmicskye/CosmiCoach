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
        .frame(height: max(
            keyboardState.inputViewHeight, // Already includes button row height
            keyboardState.getInputViewPadding(
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
                                
                                // Check if we need to show the scroll-to-bottom button
                                checkIfScrollViewAtBottom()
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
                            
                            // Check if we need to show the scroll-to-bottom button
                            checkIfScrollViewAtBottom()
                        }
                    }
                } else {
                    print("⚠️ No valid scroll position to restore")
                    isRestoringScrollPosition = false
                    
                    // Check if we need to show the scroll-to-bottom button
                    checkIfScrollViewAtBottom()
                }
            }
        }
        .onChange(of: chatManager.messages.count) { oldCount, newCount in
            // Only auto-scroll when adding messages (not when scrolling up through history)
            // Skip if we're restoring scroll position
            if newCount > oldCount && !isRestoringScrollPosition {
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
            if !isRestoringScrollPosition {
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
            if !isRestoringScrollPosition {
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
            if !isRestoringScrollPosition {
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
                    let inputBaseHeight: CGFloat = keyboardState.defaultInputHeight
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
                            .frame(height: keyboardState.getInputViewPadding(
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
            .navigationTitle("Cosmic Coach")
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
    
    // Add a dedicated property to track if we're in the process of scrolling to bottom
    // This fixes the flickering issues by preventing position checks from changing the button state
    // during programmatic scrolling
    @State private var isScrollingToBottomProgrammatically = false
    
    /// Checks if the scroll view is at the bottom
    private func checkIfScrollViewAtBottom() {
        // Skip check if we're programmatically scrolling to bottom
        if isScrollingToBottomProgrammatically {
            return
        }
        
        DispatchQueue.main.async {
            guard let scrollView = self.findScrollView() else { return }
            
            // Calculate the threshold for considering the view at the bottom (within 15 points)
            let threshold: CGFloat = 15
            let contentHeight = scrollView.contentSize.height
            let scrollViewHeight = scrollView.bounds.height
            let currentPosition = scrollView.contentOffset.y
            let maximumScrollPosition = max(0, contentHeight - scrollViewHeight)
            
            // Only calculate when we have enough scrollable content
            let hasScrollableContent = contentHeight > scrollViewHeight + 50 // Lower to 50pt for better sensitivity
            
            // Strict check: only consider at bottom if very close to max position
            let isAtBottom = currentPosition >= (maximumScrollPosition - threshold)
            
            // Determine if button should be shown
            let shouldShowButton = hasScrollableContent && !isAtBottom
            
            // Debug logging to troubleshoot
            print("Scroll position: \(Int(currentPosition))/\(Int(maximumScrollPosition)), at bottom: \(isAtBottom), show button: \(shouldShowButton)")
            
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
        guard let scrollView = scrollViewProxy else { return }
        
        // Set flag to prevent any position checks from running during the scroll operation
        isScrollingToBottomProgrammatically = true
        
        // Hide the button immediately to prevent it from showing during scroll animation
        withAnimation(.easeInOut(duration: 0.2)) {
            showScrollToBottom = false
        }
        
        // Then scroll to bottom
        withAnimation(.easeOut(duration: 0.3)) {
            scrollView.scrollTo("messageBottom", anchor: .bottom)
        }
        
        // Bypass all the intermediate checks and only do a final check
        // after the animation is completely done
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            // Use direct UIKit scrolling to ensure we're at the bottom
            if let uiScrollView = findScrollView() {
                let contentHeight = uiScrollView.contentSize.height
                let scrollViewHeight = uiScrollView.bounds.height
                let maximumScrollPosition = max(0, contentHeight - scrollViewHeight)
                
                // Ensure we're at the bottom
                UIView.performWithoutAnimation {
                    uiScrollView.contentOffset = CGPoint(x: 0, y: maximumScrollPosition)
                    uiScrollView.layoutIfNeeded()
                }
                
                // Force button to be hidden
                if showScrollToBottom {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showScrollToBottom = false
                    }
                }
                
                // Re-enable position checks but only after all animations have completed
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    isScrollingToBottomProgrammatically = false
                }
            } else {
                // Re-enable position checks if we couldn't find the scroll view
                isScrollingToBottomProgrammatically = false
            }
        }
    }
    
    
    /// Processes and sends user message
    private func sendMessage() {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        // Store message and clear input
        let messageToSend = trimmedText
        inputText = ""
        
        // Reset text input height immediately
        DispatchQueue.main.async {
            // Explicitly reset the KeyboardState inputViewHeight to default
            keyboardState.inputViewHeight = keyboardState.defaultInputHeight
            
            // Notify about height change
            NotificationCenter.default.post(
                name: NSNotification.Name("InputViewHeightChanged"),
                object: nil,
                userInfo: ["height": keyboardState.defaultInputHeight]
            )
        }
        
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

// Extension to get keyboard modifier flags
extension UIWindow {
    var eventModifierFlags: UIKeyModifierFlags? {
        // For when a hardware keyboard is attached to the device
        if let event = UIApplication.shared.windows.first?.undocumentedCurrentEvent {
            return event.modifierFlags
        }
        return nil
    }
    
    private var undocumentedCurrentEvent: UIEvent? {
        // Private API access to get current event - necessary for detecting modifier keys
        let selector = NSSelectorFromString("_currentEvent")
        if responds(to: selector) {
            return perform(selector).takeUnretainedValue() as? UIEvent
        }
        return nil
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
    // Default font and sizing for consistency - accessible to other components
    var defaultFont: UIFont { UIFont.systemFont(ofSize: UIFont.systemFontSize * 1.25) }
    var singleLineHeight: CGFloat { defaultFont.lineHeight + 16 } // Line height + padding
    var buttonRowHeight: CGFloat = 54 // Height for the send button row
    var defaultInputHeight: CGFloat { singleLineHeight + 16 + buttonRowHeight } // Add container padding + button row
    
    /// Current keyboard height when visible, or 0 when hidden
    @Published var keyboardOffset: CGFloat = 0
    
    /// Whether the keyboard is currently visible
    @Published var isKeyboardVisible: Bool = false
    
    /// Height of the input view component
    @Published var inputViewHeight: CGFloat = 0
    
    init() {
        // Initialize with calculated default height
        self.inputViewHeight = defaultInputHeight
    }
    
    /// Updates keyboard state if there's an actual change to prevent unnecessary view updates
    /// - Parameters:
    ///   - visible: Whether keyboard is visible
    ///   - height: Height of keyboard in points
    func setKeyboardVisible(_ visible: Bool, height: CGFloat) {
        // Always update if visible state changes
        let visibilityChanged = isKeyboardVisible != visible
        // For height changes, only check when keyboard is/remains visible
        let heightChanged = visible && keyboardOffset != height
        
        if visibilityChanged {
            withAnimation(.easeInOut(duration: 0.25)) {
                isKeyboardVisible = visible
                keyboardOffset = visible ? height : 0
            }
        } else if heightChanged {
            withAnimation(.easeInOut(duration: 0.25)) {
                keyboardOffset = height
            }
        }
    }
    
    /// Returns the appropriate padding for the input view based on current keyboard state
    /// - Parameters:
    ///   - baseHeight: Default height to use when keyboard is hidden
    ///   - safeAreaPadding: Additional padding to account for safe area
    /// - Returns: The calculated padding value
    func getInputViewPadding(baseHeight: CGFloat, safeAreaPadding: CGFloat) -> CGFloat {
        // Get the correct height based on the text input size
        let actualBaseHeight = inputViewHeight != defaultInputHeight ? inputViewHeight : baseHeight
        
        // When keyboard is visible, we need to account for both keyboard height AND the text input height difference
        if isKeyboardVisible {
            // Calculate height difference from default
            let heightDifference = inputViewHeight - defaultInputHeight
            
            // With keyboard open, we need to ensure we have enough space for the text input AND button row
            // The inputViewHeight includes text input + padding + button row
            // When the keyboard is open, add the button row height to ensure proper space for both elements
            return keyboardOffset + safeAreaPadding + buttonRowHeight + (heightDifference > 0 ? heightDifference : 0)
        } else {
            // When keyboard is hidden, just use the actual base height
            return actualBaseHeight
        }
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
    @State private var textEditorHeight: CGFloat = 0 // Will be set to minHeight in onAppear
    
    // Constants 
    private var defaultFont: UIFont { UIFont.systemFont(ofSize: UIFont.systemFontSize * 1.25) }
    private var defaultFontSize: CGFloat { defaultFont.pointSize }
    private var lineHeight: CGFloat { defaultFont.lineHeight }
    private let maxLines: Int = 4
    private var minHeight: CGFloat { lineHeight + 16 } // Single line + padding
    
    // Computed properties
    private var isButtonDisabled: Bool {
        isDisabled || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending
    }
    
    private var buttonColor: Color {
        isButtonDisabled ? .gray : themeColor
    }
    
    // Calculate max height based on max lines
    private var maxHeight: CGFloat {
        let padding: CGFloat = 16 // vertical padding
        return (CGFloat(maxLines) * lineHeight) + padding
    }
    
    // MARK: Body
    var body: some View {
        VStack(spacing: 8) {
            // Text input field - using a multi-line editor, now full width
            ZStack(alignment: .leading) {
                // Placeholder text that shows when the text editor is empty
                if text.isEmpty {
                    Text("Message CosmiCoach")
                        .foregroundColor(Color(.placeholderText))
                        .padding(.horizontal, 6)
                        .font(.system(size: defaultFontSize))
                }
                
                // Actual text editor
                MultilineTextField(text: $text, onSubmit: {
                    // Submit on shift+return or command+return
                    if !text.isEmpty {
                        onSend()
                    }
                })
                .frame(height: min(textEditorHeight, maxHeight))
                .onAppear {
                    // Initialize height with calculated minHeight
                    textEditorHeight = minHeight
                }
                .onChange(of: text) { _, newText in
                    // Calculate height based on text content
                    let size = getTextSize(for: newText)
                    let newHeight = min(max(size.height + 16, minHeight), maxHeight)
                    
                    // Only update if height actually changed
                    if newHeight != textEditorHeight {
                        textEditorHeight = newHeight
                        
                        // Calculate total height including padding, container, and button row
                        let buttonRowHeight: CGFloat = 54 // Match the height in KeyboardState
                        let totalHeight = newHeight + 16 + buttonRowHeight // Add padding for container + button row
                        
                        // Logging for debugging
                        if inputViewLayoutDebug {
                            print("Text height changed: \(textEditorHeight) → total: \(totalHeight)")
                        }
                        
                        // Notify parent view controller of height change
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("InputViewHeightChanged"),
                                object: nil,
                                userInfo: ["height": totalHeight]
                            )
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .border(debugOutlineMode == .textInput ? Color.pink : Color.clear, width: debugOutlineMode == .textInput ? 1 : 0)
            .animation(nil, value: text) // Prevent animation during transitions
            
            // Send button row
            HStack {
                Spacer()
                
                Button {
                    guard !isSending else { return }
                    isSending = true
                    
                    // Reset text editor height before sending
                    textEditorHeight = minHeight
                    
                    // Explicitly notify about height change to default
                    if inputViewLayoutDebug {
                        print("Resetting text height to default: \(minHeight)")
                    }
                    
                    // Calculate total input view height (text + container padding + button row)
                    let buttonRowHeight: CGFloat = 54 // Match the height in KeyboardState
                    let totalHeight = minHeight + 16 + buttonRowHeight // Add padding for container + button row
                    
                    // Notify parent about height change
                    NotificationCenter.default.post(
                        name: NSNotification.Name("InputViewHeightChanged"),
                        object: nil,
                        userInfo: ["height": totalHeight]
                    )
                    
                    // Call send after height is reset
                    onSend()
                    
                    // Reset button state after a brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isSending = false
                    }
                } label: {
                    ZStack {
                        Circle()
                            .foregroundColor(buttonColor)
                            .frame(width: 34, height: 34)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(isButtonDisabled ? Color(.systemBackground) : .white)
                    }
                }
                .padding(.bottom, 4)
                .padding(.horizontal, 2)
                .disabled(isButtonDisabled)
                .animation(.easeInOut(duration: 0.1), value: isButtonDisabled)
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .border(debugOutlineMode == .textInput ? Color.mint : Color.clear, width: 2)
        .transaction { transaction in
            transaction.animation = nil // Prevent position animations
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(25, corners: [.topLeft, .topRight])
    }
    
    // Helper to calculate text size
    private func getTextSize(for text: String) -> CGSize {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: defaultFont
        ]
        
        let width = UIScreen.main.bounds.width - 70 // Wider width since button is now in a separate row
        let constraintRect = CGSize(width: width, height: .greatestFiniteMagnitude)
        let boundingBox = text.boundingRect(
            with: constraintRect,
            options: .usesLineFragmentOrigin,
            attributes: attributes,
            context: nil
        )
        
        return boundingBox.size
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

// MARK: - MultilineTextField
struct MultilineTextField: UIViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.systemFont(ofSize: UIFont.systemFontSize * 1.25) // Use system font size with slight increase
        textView.backgroundColor = .clear
        textView.isScrollEnabled = true
        textView.isEditable = true
        textView.isUserInteractionEnabled = true
        textView.autocapitalizationType = .sentences
        textView.returnKeyType = .default // Use default return key
        textView.keyboardType = .default
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textView.text = text
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        // Only update if text changed externally
        if uiView.text != text {
            uiView.text = text
            
            // When text is cleared, notify about height change
            if text.isEmpty {
                // Access defaultInputHeight via UIKit extension since we're in a UIViewRepresentable
                let font = UIFont.systemFont(ofSize: UIFont.systemFontSize * 1.25)
                let lineHeight = font.lineHeight
                let buttonRowHeight: CGFloat = 54 // Match the height in KeyboardState
                let defaultHeight = lineHeight + 16 + 16 + buttonRowHeight // Line height + inner padding + container padding + button row
                
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("InputViewHeightChanged"),
                        object: nil,
                        userInfo: ["height": defaultHeight]
                    )
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: MultilineTextField
        
        init(_ parent: MultilineTextField) {
            self.parent = parent
        }
        
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
        
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Check for special key combinations
            let currentText = textView.text ?? ""
            
            // Current selection
            let selectedRange = textView.selectedRange
            
            // Handle key combinations
            if text == "\n" {
                // Check if shift or command key is pressed
                let modifierFlags = UIApplication.shared.windows.first?.windowScene?.keyWindow?.eventModifierFlags
                
                if modifierFlags?.contains(.shift) == true || modifierFlags?.contains(.command) == true {
                    // Shift+Return or Command+Return: submit message
                    parent.onSubmit()
                    return false
                } else {
                    // Normal Return: insert line break (default behavior)
                    return true
                }
            }
            
            return true
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
    private var defaultFont: UIFont { UIFont.systemFont(ofSize: UIFont.systemFontSize * 1.25) }
    private var singleLineInputHeight: CGFloat { defaultFont.lineHeight + 16 } // Line height + padding
    private var buttonRowHeight: CGFloat = 54 // Height for the send button row
    private var inputViewHeight: CGFloat { singleLineInputHeight + 16 + buttonRowHeight } // Add container padding + button row
    private let keyboardVisibilityThreshold: CGFloat = 100
    
    // MARK: Properties
    internal var keyboardState: KeyboardState // Changed from private to internal
    private var bottomConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    private var _lastInputViewHeight: CGFloat = 0
    private var currentInputViewHeight: CGFloat {
        get { inputViewHeight }
        set { _lastInputViewHeight = newValue } 
    }
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
        keyboardTrackingView.backgroundColor = UIColor.secondarySystemBackground
        
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
        ])
        
        // Create height constraint that we can update later
        heightConstraint = inputHostView.view.heightAnchor.constraint(equalToConstant: inputViewHeight)
        heightConstraint?.isActive = true
        
        // Attach to keyboard
        bottomConstraint = inputHostView.view.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        bottomConstraint?.isActive = true
        
        // Setup notification observer for input view height changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInputViewHeightChange),
            name: NSNotification.Name("InputViewHeightChanged"),
            object: nil
        )
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
        
        // Update state without SwiftUI animation (since we'll do UIKit animation)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        keyboardState.setKeyboardVisible(isVisible, height: keyboardFrame.height)
        CATransaction.commit()
        
        // Match keyboard animation exactly using UIKit
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
        
        // Update state without SwiftUI animation (since we'll do UIKit animation)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        keyboardState.setKeyboardVisible(false, height: 0)
        CATransaction.commit()
        
        // Match keyboard animation exactly
        let curveValue = curve.uintValue
        let animationOptions = UIView.AnimationOptions(rawValue: curveValue << 16)
        
        // Animate with matching curve
        UIView.animate(withDuration: duration, delay: 0, options: [animationOptions, .beginFromCurrentState]) {
            self.view.layoutIfNeeded()
            self.updateSwiftUIViewPosition()
        }
    }
    
    // MARK: Input View Height Handling
    @objc func handleInputViewHeightChange(_ notification: Notification) {
        guard let height = notification.userInfo?["height"] as? CGFloat else { return }
        
        print("📝 Height change notification received: \(height) (current: \(_lastInputViewHeight))")
        
        // Store the height in our backing variable
        _lastInputViewHeight = height
        
        // Update the height constraint
        heightConstraint?.constant = height
        
        // Update keyboardState with new input view height
        keyboardState.inputViewHeight = height
        
        // Notify parent view to update layout for the new height
        NotificationCenter.default.post(
            name: NSNotification.Name("KeyboardStateChanged"),
            object: nil,
            userInfo: ["height": height]
        )
        
        // Update layout with animation
        UIView.animate(withDuration: 0.2) {
            self.view.layoutIfNeeded()
        }
        
        // Make sure we update the parent ContentView's layout as well
        DispatchQueue.main.async {
            self.updateSwiftUIViewPosition()
        }
        
        // Ensure the parent views are updated as well
        // This is especially important after sending a message
        if text.wrappedValue.isEmpty || height == inputViewHeight {
            print("📝 Text is empty or height is default, forcing reset to defaults")
            
            // Force another update after a slight delay to ensure it takes effect
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.heightConstraint?.constant = self.inputViewHeight
                self.keyboardState.inputViewHeight = self.keyboardState.defaultInputHeight
                
                UIView.animate(withDuration: 0.2) {
                    self.view.layoutIfNeeded()
                }
            }
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
            // Update state without animation during interactive gesture
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            keyboardState.setKeyboardVisible(isVisible, height: isVisible ? keyboardHeight : 0)
            CATransaction.commit()
            
            // Update layout immediately
            view.layoutIfNeeded()
            updateSwiftUIViewPosition()
        }
    }
}

