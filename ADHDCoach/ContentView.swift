import SwiftUI
import Combine
import UIKit

struct ContentView: View {
    @EnvironmentObject private var chatManager: ChatManager
    @EnvironmentObject private var eventKitManager: EventKitManager
    @EnvironmentObject private var memoryManager: MemoryManager
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingSettings = false
    @State private var scrollToBottom = false
    @AppStorage("hasAppearedBefore") private var hasAppearedBefore = false
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var keyboardState = KeyboardState()
    @State private var inputText = ""
    
    // Helper function to reset chat when notification is received
    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ChatHistoryDeleted"),
            object: nil,
            queue: .main
        ) { [self] _ in
            // This will be called when chat history is deleted
            // Use Task with MainActor to safely modify the MainActor-isolated property
            Task { @MainActor in
                chatManager.messages = []
                
                // Try sending automatic message after chat history deletion
                await chatManager.checkAndSendAutomaticMessageAfterHistoryDeletion()
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    // Calculate available scroll height by subtracting input height from total height
                    let inputHeight: CGFloat = 44
                    let availableHeight = geometry.size.height - inputHeight
                    
                    VStack(spacing: 0) {
                        ScrollView {
                            if chatManager.messages.isEmpty {
                                EmptyStateView()
                            } else {
                                MessageListView(
                                    messages: chatManager.messages,
                                    statusMessagesProvider: chatManager.combinedStatusMessagesForMessage
                                )
                            }
                            Color.clear
                                .frame(height: 1)
                                .id("bottomScrollID")
                                .onAppear {
                                    scrollToBottom = true
                                }
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .scrollClipDisabled()
                        .onChange(of: chatManager.messages.count) { _, _ in
                            scrollToBottom(animated: true)
                        }
                        .onChange(of: chatManager.streamingUpdateCount) { _, _ in
                            // Skip animation for streaming updates for better performance
                            scrollToBottom(animated: false)
                        }
                        .onChange(of: scrollToBottom) { _, newValue in
                            if newValue {
                                scrollToLastMessage()
                                scrollToBottom = false
                            }
                        }
                        .onChange(of: keyboardState.isKeyboardVisible) { _, _ in
                            // Scroll to bottom when keyboard visibility changes
                            scrollToBottom(animated: true)
                        }
                        
                        // Add bottom padding that adjusts with keyboard height
                        // This ensures the scroll area stops above the input+keyboard
                        Spacer()
                            .frame(height: keyboardState.isKeyboardVisible ? keyboardState.keyboardOffset + 10 : 44)
                    }
                    .frame(height: geometry.size.height)
                    
                    // Keyboard attached input that sits at the bottom
                    VStack {
                        Spacer()
                        KeyboardAttachedView(
                            keyboardState: keyboardState,
                            text: $inputText,
                            onSend: sendMessage,
                            colorScheme: colorScheme,
                            themeColor: themeManager.accentColor(for: colorScheme),
                            isDisabled: chatManager.isProcessing
                        )
                        .frame(height: 44)
                    }
                }
            }
            .ignoresSafeArea(.keyboard)
            .navigationTitle("Cosmic Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(colorScheme)
            .tint(themeManager.accentColor(for: colorScheme))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        // Hide keyboard before showing settings
                        hideKeyboard()
                        
                        // Then show settings
                        showingSettings = true
                    }) {
                        Image(systemName: "gear")
                            .font(.system(size: 22))
                            .foregroundColor(themeManager.accentColor(for: colorScheme))
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(themeManager)
                    .environmentObject(memoryManager)
                    .environmentObject(locationManager)
                    .environmentObject(chatManager)
                    .onAppear {
                        // Force keyboard dismiss when settings appear
                        hideKeyboard()
                    }
            }
            .applyThemeColor()
            .onAppear {
                print("⏱️ ContentView.onAppear - START")
                // Connect the memory manager to the chat manager
                chatManager.setMemoryManager(memoryManager)
                print("⏱️ ContentView.onAppear - Connected memory manager to chat manager")
                
                // Setup notification observers
                setupNotificationObserver()
                print("⏱️ ContentView.onAppear - Set up notification observers")
                
                // Check if automatic messages should be enabled in settings and log it
                let automaticMessagesEnabled = UserDefaults.standard.bool(forKey: "enable_automatic_responses")
                print("⏱️ ContentView.onAppear - Automatic messages enabled in settings: \(automaticMessagesEnabled)")
                
                // Only check for automatic messages if we have appeared before
                // This ensures we don't trigger on the initial app launch/init
                if hasAppearedBefore {
                    print("⏱️ ContentView.onAppear - This is a RE-APPEARANCE (hasAppearedBefore=true), likely from background")
                    
                    // Ensure memory is properly loaded
                    Task {
                        print("⏱️ ContentView.onAppear - Task started for memory loading")
                        let _ = await memoryManager.readMemory()
                        if let fileURL = memoryManager.getMemoryFileURL() {
                            print("⏱️ ContentView.onAppear - Memory file exists: \(FileManager.default.fileExists(atPath: fileURL.path))")
                            print("⏱️ ContentView.onAppear - Memory content length: \(memoryManager.memoryContent.count)")
                        }
                        
                        // Memory loaded - automatic messages handled by ADHDCoachApp
                    }
                } else {
                    print("⏱️ ContentView.onAppear - This is the FIRST appearance (hasAppearedBefore=false), setting to true")
                    // Just load memory but don't check for automatic messages on first appearance
                    Task {
                        let _ = await memoryManager.readMemory()
                        if let fileURL = memoryManager.getMemoryFileURL() {
                            print("⏱️ ContentView.onAppear - Memory file exists: \(FileManager.default.fileExists(atPath: fileURL.path))")
                            print("⏱️ ContentView.onAppear - Memory content length: \(memoryManager.memoryContent.count)")
                        }
                    }
                    // Mark that we've appeared before for next time
                    hasAppearedBefore = true
                    print("⏱️ ContentView.onAppear - Set hasAppearedBefore to TRUE in AppStorage")
                }
                print("⏱️ ContentView.onAppear - END (task continues asynchronously)")
            }
            .task {
                // This is a different lifecycle event than onAppear
                print("⏱️ ContentView.task - Running")
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                print("⏱️ ContentView.onChange(scenePhase) - \(oldPhase) -> \(newPhase)")
                
                // Check for transition to active state (from any state)
                if newPhase == .active {
                    print("⏱️ ContentView.onChange - App becoming active")
                    
                    // Only run necessary updates if we've seen the app before
                    if hasAppearedBefore {
                        // Log last session time for debugging
                        if let lastSessionTime = UserDefaults.standard.object(forKey: "last_app_session_time") as? TimeInterval {
                            let lastTime = Date(timeIntervalSince1970: lastSessionTime)
                            let timeSinceLastSession = Date().timeIntervalSince(lastTime)
                            print("⏱️ ContentView.onChange - Last session time: \(lastTime)")
                            print("⏱️ ContentView.onChange - Time since last session: \(timeSinceLastSession) seconds")
                            
                            // Load memory - automatic messages handled by ADHDCoachApp
                            Task {
                                print("⏱️ ContentView.onChange - Ensuring memory is loaded")
                                let _ = await memoryManager.readMemory()
                                print("⏱️ ContentView.onChange - Memory loaded")
                            }
                        }
                    } else {
                        print("⏱️ ContentView.onChange - Not checking automatic messages, hasAppearedBefore = false")
                    }
                }
            }
        }
    }
    
    private func scrollToLastMessage() {
        DispatchQueue.main.async {
            withAnimation {
                // Using proxy from ScrollViewReader to scroll to the bottom
                if let scrollView = UIScrollView.findScrollView() {
                    let bottomOffset = CGPoint(
                        x: 0,
                        y: max(0, scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom)
                    )
                    scrollView.setContentOffset(bottomOffset, animated: true)
                }
            }
        }
    }
    
    private func scrollToBottom(animated: Bool = true) {
        if animated {
            scrollToBottom = true
        } else {
            scrollToLastMessage()
        }
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    private func sendMessage() {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        // Clear input text
        inputText = ""
        
        // Dismiss keyboard
        hideKeyboard()
        
        // Add user message to chat
        chatManager.addUserMessage(content: trimmedText)
        
        // Trigger scroll to bottom after adding user message
        scrollToBottom = true
        
        // Send to Claude API
        Task {
            // Get context from EventKit
            let calendarEvents = eventKitManager.fetchUpcomingEvents(days: 7)
            let reminders = await eventKitManager.fetchReminders()
            
            await chatManager.sendMessageToClaude(
                userMessage: trimmedText,
                calendarEvents: calendarEvents,
                reminders: reminders
            )
        }
    }
}

// Dedicated view for the empty state
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

// Dedicated view for the message list
struct MessageListView: View {
    let messages: [ChatMessage]
    let statusMessagesProvider: (ChatMessage) -> [OperationStatusMessage]
    
    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(messages) { message in
                VStack(spacing: 4) {
                    MessageBubbleView(message: message)
                        .padding(.horizontal)
                    
                    // If this is the message that triggered an operation,
                    // display the operation status message right after it
                    if !message.isUser && message.isComplete {
                        ForEach(statusMessagesProvider(message)) { statusMessage in
                            OperationStatusView(statusMessage: statusMessage)
                                .padding(.horizontal)
                        }
                    }
                }
            }
            
            // Invisible spacer view at the end for scrolling
            Color.clear
                .frame(height: 1)
                .id("bottomID")
        }
        .padding(.top, 8)
    }
}

// Dedicated scroll position manager
class ScrollPositionManager: ObservableObject {
    @Published var shouldScrollToBottom = false
    
    func scrollToBottom() {
        shouldScrollToBottom = true
    }
}

// Dedicated scrolling view for chat messages
struct ChatScrollView: View {
    let messages: [ChatMessage]
    let statusMessagesProvider: (ChatMessage) -> [OperationStatusMessage]
    let streamingUpdateCount: Int
    @Binding var shouldScrollToBottom: Bool
    let isEmpty: Bool
    @State private var autoScrollEnabled = true
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if isEmpty {
                    EmptyStateView()
                } else {
                    MessageListView(
                        messages: messages,
                        statusMessagesProvider: statusMessagesProvider
                    )
                    .background(
                        // Hidden scroll position detector
                        ScrollDetector(autoScrollEnabled: $autoScrollEnabled)
                    )
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                if autoScrollEnabled {
                    scrollToBottom(proxy: proxy)
                }
            }
            .onChange(of: streamingUpdateCount) { _, _ in
                if autoScrollEnabled {
                    // Skip animation for streaming updates for better performance
                    scrollToBottom(proxy: proxy, animated: false)
                }
            }
            .onChange(of: shouldScrollToBottom) { _, newValue in
                if newValue {
                    // Only manually scroll to bottom for explicit scroll requests
                    scrollToBottom(proxy: proxy)
                    shouldScrollToBottom = false
                    // Re-enable auto-scrolling when manually scrolled to bottom
                    autoScrollEnabled = true
                }
            }
            // Disable any keyboard-related scrolling entirely
            .simultaneousGesture(
                DragGesture().onChanged { _ in
                    // During any scroll gesture, disable keyboard auto-scroll
                    // This captures user intent to scroll independently
                    NotificationCenter.default.post(
                        name: NSNotification.Name("UserScrollingNotification"),
                        object: nil
                    )
                }
            )
            .onAppear {
                // Scroll to bottom on first appear
                scrollToBottom(proxy: proxy)
            }
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        // Mark as at bottom when we explicitly scroll
        UserDefaults.standard.set(true, forKey: "ChatIsAtBottom")
        UserDefaults.standard.synchronize()
        
        DispatchQueue.main.async {
            if animated {
                withAnimation {
                    proxy.scrollTo("bottomID", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("bottomID", anchor: .bottom)
            }
        }
    }
    
}

// Detect scroll position changes
struct ScrollDetector: UIViewRepresentable {
    @Binding var autoScrollEnabled: Bool
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        
        // Setup keyboard observers in the coordinator
        context.coordinator.setupKeyboardObservers()
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Find scroll view
        DispatchQueue.main.async {
            guard let scrollView = uiView.superview?.superview?.superview as? UIScrollView else {
                return
            }
            
            if context.coordinator.scrollView == nil {
                scrollView.delegate = context.coordinator
                context.coordinator.scrollView = scrollView
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ScrollDetector
        var scrollView: UIScrollView?
        var isDragging = false
        var isKeyboardDismissing = false
        
        init(_ parent: ScrollDetector) {
            self.parent = parent
            super.init()
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        func setupKeyboardObservers() {
            // Listen for user scrolling notification
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(userStartedScrolling),
                name: NSNotification.Name("UserScrollingNotification"),
                object: nil
            )
            
            // Observe keyboard will hide to detect keyboard dismissal
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardWillHide),
                name: UIResponder.keyboardWillHideNotification,
                object: nil
            )
            
            // Reset keyboard state when showing
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardDidShow),
                name: UIResponder.keyboardDidShowNotification,
                object: nil
            )
        }
        
        @objc func userStartedScrolling() {
            // User initiated scrolling - disable auto-scroll completely
            parent.autoScrollEnabled = false
        }
        
        @objc func keyboardWillHide() {
            // Flag that keyboard is dismissing to prevent auto-scroll changes
            isKeyboardDismissing = true
            
            // When keyboard hides, we want to DISABLE auto-scroll completely
            // to prevent unwanted scrolling during dismissal
            let scrollPosition = UserDefaults.standard.bool(forKey: "ChatIsAtBottom")
            if !scrollPosition {
                // Force disable auto-scroll if we're not at bottom
                parent.autoScrollEnabled = false
                
                // Also explicitly save this state
                UserDefaults.standard.set(false, forKey: "ChatIsAtBottom")
                UserDefaults.standard.synchronize()
            }
            
            // Reset after a short delay (after dismiss animation)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.isKeyboardDismissing = false
            }
        }
        
        @objc func keyboardDidShow() {
            // Keyboard is visible, reset flag
            isKeyboardDismissing = false
        }
        
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            isDragging = true
        }
        
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            // Only update auto-scroll when user actively drags, not when keyboard dismissal causes scrolling
            isDragging = false
            // If not decelerating, check position
            if !decelerate && !isKeyboardDismissing {
                updateAutoScrollState(scrollView)
            }
        }
        
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            // When scrolling stops after user interaction, update auto-scroll state
            // Only if not in the middle of keyboard dismissal
            if !isKeyboardDismissing {
                updateAutoScrollState(scrollView)
            }
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // When scrolling while dragging, immediately disable auto-scroll
            if isDragging {
                // When user is manually scrolling, disable auto-scroll immediately
                // This prevents unwanted scrolling during keyboard dismiss
                parent.autoScrollEnabled = false
                
                // Also update position state so keyboard dismiss doesn't trigger scrolls
                let contentHeight = scrollView.contentSize.height
                let scrollViewHeight = scrollView.frame.size.height
                let scrollOffset = scrollView.contentOffset.y
                let bottomPosition = contentHeight - scrollViewHeight
                
                // If we're not at the bottom, make sure state reflects this
                if (bottomPosition - scrollOffset) > 44 {
                    UserDefaults.standard.set(false, forKey: "ChatIsAtBottom")
                    UserDefaults.standard.synchronize()
                }
            }
        }
        
        private func updateAutoScrollState(_ scrollView: UIScrollView) {
            let contentHeight = scrollView.contentSize.height
            let scrollViewHeight = scrollView.frame.size.height
            let scrollOffset = scrollView.contentOffset.y
            let bottomPosition = contentHeight - scrollViewHeight
            
            // If we're within 44 points of the bottom, consider it "at bottom"
            let isAtBottom = (bottomPosition - scrollOffset) <= 44
            
            // Save current position to UserDefaults for keyboard observer
            // Use synchronize to ensure value is immediately available
            UserDefaults.standard.set(isAtBottom, forKey: "ChatIsAtBottom")
            UserDefaults.standard.synchronize()
            
            // Only update if the value is changing to avoid unnecessary @Binding updates
            if parent.autoScrollEnabled != isAtBottom {
                parent.autoScrollEnabled = isAtBottom
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ChatManager())
        .environmentObject(EventKitManager())
        .environmentObject(MemoryManager())
        .environmentObject(ThemeManager())
        .environmentObject(LocationManager())
}

#Preview("Message Components") {
    VStack {
        MessageListView(
            messages: [
                ChatMessage(id: UUID(), content: "Hello there!", timestamp: Date(), isUser: true, isComplete: true),
                ChatMessage(id: UUID(), content: "Hi! How can I help you today?", timestamp: Date(), isUser: false, isComplete: true)
            ],
            statusMessagesProvider: { _ in [] }
        )
        .frame(height: 300)
        
        Divider()
        
        EmptyStateView()
            .frame(height: 300)
    }
    .padding(.horizontal)
}

// Find ScrollView in the view hierarchy
extension UIScrollView {
    static func findScrollView() -> UIScrollView? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        
        for window in windows {
            if let scrollView = findScrollView(in: window) {
                return scrollView
            }
        }
        return nil
    }
    
    private static func findScrollView(in view: UIView) -> UIScrollView? {
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
}

// MARK: - KeyboardState
class KeyboardState: ObservableObject {
    @Published var keyboardOffset: CGFloat = 0
    @Published var isKeyboardVisible: Bool = false
    
    // Add timestamp for state changes to help with debugging
    private var lastStateChangeTime: Date = Date()
    private var stateChangeCount: Int = 0
    
    func setKeyboardVisible(_ visible: Bool, height: CGFloat, source: String) {
        // Only log if state actually changed 
        if isKeyboardVisible != visible {
            stateChangeCount += 1
            let now = Date()
            let timeSinceLastChange = now.timeIntervalSince(lastStateChangeTime)
            
            print("⌨️ KeyboardState CHANGE #\(stateChangeCount) - \(isKeyboardVisible ? "VISIBLE" : "HIDDEN") → \(visible ? "VISIBLE" : "HIDDEN")")
            print("⌨️ KeyboardState source: \(source), height: \(height), time since last change: \(timeSinceLastChange)s")
            
            // Update state
            lastStateChangeTime = now
            isKeyboardVisible = visible
            keyboardOffset = height
        }
    }
}

// MARK: - TextInputView
struct TextInputView: View {
    @Binding var text: String
    var onSend: () -> Void
    var colorScheme: ColorScheme
    var themeColor: Color
    var isDisabled: Bool
    
    var body: some View {
        HStack {
            TextField("Message", text: $text)
                .padding(.horizontal, 15)
                .padding(.vertical, 8)
                .background(
                    colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : Color(UIColor.secondarySystemBackground)
                )
                .cornerRadius(18)
            
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(isDisabled || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : themeColor)
            }
            .disabled(isDisabled || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
    }
}

// MARK: - KeyboardAttachedView
struct KeyboardAttachedView: UIViewControllerRepresentable {
    var keyboardState: KeyboardState
    @Binding var text: String
    var onSend: () -> Void
    var colorScheme: ColorScheme
    var themeColor: Color
    var isDisabled: Bool
    
    func makeUIViewController(context: Context) -> KeyboardObservingViewController {
        return KeyboardObservingViewController(
            keyboardState: keyboardState,
            text: $text,
            onSend: onSend,
            colorScheme: colorScheme,
            themeColor: themeColor,
            isDisabled: isDisabled
        )
    }
    
    func updateUIViewController(_ uiViewController: KeyboardObservingViewController, context: Context) {
        uiViewController.updateText(text)
        uiViewController.updateAppearance(
            colorScheme: colorScheme,
            themeColor: themeColor,
            isDisabled: isDisabled
        )
    }
}

// MARK: - KeyboardObservingViewController
class KeyboardObservingViewController: UIViewController {
    private var emptyView = UIView()
    private var inputHostView: UIHostingController<TextInputView>!
    private var keyboardState: KeyboardState
    private var bottomConstraint: NSLayoutConstraint?
    private var text: Binding<String>
    private var onSend: () -> Void
    private var colorScheme: ColorScheme
    private var themeColor: Color
    private var isDisabled: Bool
    
    // Experiment: Track view controller lifecycle
    private var viewAppearanceCounter = 0
    private var debugTimer: Timer?
    
    deinit {
        // Clean up all observers and timers
        NotificationCenter.default.removeObserver(self)
        debugTimer?.invalidate()
        debugTimer = nil
        print("⌨️ KeyboardVC lifecycle: deinit")
    }
    
    init(
        keyboardState: KeyboardState,
        text: Binding<String>,
        onSend: @escaping () -> Void,
        colorScheme: ColorScheme,
        themeColor: Color,
        isDisabled: Bool
    ) {
        self.keyboardState = keyboardState
        self.text = text
        self.onSend = onSend
        self.colorScheme = colorScheme
        self.themeColor = themeColor
        self.isDisabled = isDisabled
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        print("⌨️ KeyboardVC lifecycle: viewDidLoad")
        
        // Add an empty view to track keyboard position
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyView)
        
        // Constrain empty view to keyboard layout guide edges
        NSLayoutConstraint.activate([
            emptyView.leadingAnchor.constraint(equalTo: view.keyboardLayoutGuide.leadingAnchor),
            emptyView.trailingAnchor.constraint(equalTo: view.keyboardLayoutGuide.trailingAnchor),
            emptyView.topAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            emptyView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.bottomAnchor)
        ])
        
        // Setup the text input view
        setupTextInputView()
        
        // Add direct keyboard observation in addition to layout guide
        setupKeyboardObservers()
        
        // Start debug timer to periodically check keyboard status
        startDebugTimer()
    }
    
    private func setupTextInputView() {
        // Create the SwiftUI text input view
        let textView = TextInputView(
            text: text,
            onSend: onSend,
            colorScheme: colorScheme,
            themeColor: themeColor,
            isDisabled: isDisabled
        )
        inputHostView = UIHostingController(rootView: textView)
        
        // Add it to the view hierarchy
        addChild(inputHostView)
        inputHostView.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputHostView.view)
        inputHostView.didMove(toParent: self)
        
        // Constrain the text input view
        NSLayoutConstraint.activate([
            inputHostView.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputHostView.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputHostView.view.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        // Create the bottom constraint that will be updated as the keyboard moves
        bottomConstraint = inputHostView.view.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        bottomConstraint?.isActive = true
    }
    
    func updateText(_ newText: String) {
        inputHostView.rootView = TextInputView(
            text: text,
            onSend: onSend,
            colorScheme: colorScheme,
            themeColor: themeColor,
            isDisabled: isDisabled
        )
    }
    
    func updateAppearance(colorScheme: ColorScheme, themeColor: Color, isDisabled: Bool) {
        self.colorScheme = colorScheme
        self.themeColor = themeColor
        self.isDisabled = isDisabled
        
        inputHostView.rootView = TextInputView(
            text: text,
            onSend: onSend,
            colorScheme: colorScheme,
            themeColor: themeColor,
            isDisabled: isDisabled
        )
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewAppearanceCounter += 1
        print("⌨️ KeyboardVC lifecycle: viewWillAppear (count: \(viewAppearanceCounter))")
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("⌨️ KeyboardVC lifecycle: viewDidAppear")
        
        // Experiment: Force a keyboard status check after view appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.checkKeyboardStatus()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        print("⌨️ KeyboardVC lifecycle: viewWillDisappear")
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        print("⌨️ KeyboardVC lifecycle: viewDidDisappear")
    }
    
    private func startDebugTimer() {
        // Stop any existing timer
        debugTimer?.invalidate()
        
        // Create a new timer that fires every 2 seconds
        debugTimer = Timer.scheduledTimer(
            withTimeInterval: 2.0,
            repeats: true
        ) { [weak self] _ in
            self?.checkKeyboardStatus()
        }
    }
    
    private func checkKeyboardStatus() {
        // Perform a manual check of keyboard status
        if let window = view.window {
            let keyboardFrameInWindow = emptyView.convert(emptyView.bounds, to: window)
            let screenHeight = window.frame.height
            let keyboardTop = keyboardFrameInWindow.minY
            let keyboardHeight = screenHeight - keyboardTop
            
            // Log the current status
            print("⌨️ TIMER CHECK - emptyView bounds: \(emptyView.bounds), frame: \(emptyView.frame)")
            print("⌨️ TIMER CHECK - Window frame: \(window.frame), safeArea: \(window.safeAreaInsets)")
            print("⌨️ TIMER CHECK - Keyboard top: \(keyboardTop), height: \(keyboardHeight)")
            print("⌨️ TIMER CHECK - Keyboard visible in state: \(keyboardState.isKeyboardVisible)")
            
            // Detect keyboard state from UI position
            let isVisible = keyboardTop < screenHeight && keyboardHeight > 200
            
            // If there's a mismatch between our state and reality, update it
            if isVisible != keyboardState.isKeyboardVisible {
                print("⌨️ TIMER CHECK - MISMATCH DETECTED: State says keyboard is \(keyboardState.isKeyboardVisible ? "VISIBLE" : "HIDDEN") but it appears to be \(isVisible ? "VISIBLE" : "HIDDEN")")
                
                // Update the state to match reality
                self.keyboardState.setKeyboardVisible(isVisible, height: isVisible ? keyboardHeight : 0, source: "timerCheck-correction")
            }
        }
    }
    
    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardDidShow),
            name: UIResponder.keyboardDidShowNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardDidHide),
            name: UIResponder.keyboardDidHideNotification,
            object: nil
        )
    }
    
    @objc func keyboardWillShow(_ notification: Notification) {
        print("⌨️ NOTIFICATION: keyboardWillShow received")
        if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
           let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double {
            let keyboardHeight = keyboardFrame.height
            print("⌨️ NOTIFICATION: Keyboard will show - Height: \(keyboardHeight), Duration: \(duration)")
            
            // Update keyboard state using our new method
            self.keyboardState.setKeyboardVisible(true, height: keyboardHeight, source: "keyboardWillShow")
            
            // Animate changes
            UIView.animate(withDuration: duration) {
                self.view.layoutIfNeeded()
            }
        }
    }
    
    @objc func keyboardDidShow(_ notification: Notification) {
        print("⌨️ NOTIFICATION: keyboardDidShow received")
        if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            let keyboardHeight = keyboardFrame.height
            print("⌨️ NOTIFICATION: Keyboard did show - Height: \(keyboardHeight)")
            
            // Update keyboard state using our new method
            self.keyboardState.setKeyboardVisible(true, height: keyboardHeight, source: "keyboardDidShow")
        }
    }
    
    @objc func keyboardWillHide(_ notification: Notification) {
        print("⌨️ NOTIFICATION: keyboardWillHide received")
        if let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double {
            print("⌨️ NOTIFICATION: Keyboard will hide - Duration: \(duration)")
            
            // Update keyboard state using our new method
            self.keyboardState.setKeyboardVisible(false, height: 0, source: "keyboardWillHide")
            
            // Animate changes
            UIView.animate(withDuration: duration) {
                self.view.layoutIfNeeded()
            }
        }
    }
    
    @objc func keyboardDidHide(_ notification: Notification) {
        print("⌨️ NOTIFICATION: keyboardDidHide received")
        
        // Update keyboard state using our new method
        self.keyboardState.setKeyboardVisible(false, height: 0, source: "keyboardDidHide")
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        if let window = view.window {
            // Get keyboard frame in window coordinates
            let keyboardFrameInWindow = emptyView.convert(emptyView.bounds, to: window)
            let screenHeight = window.frame.height
            let keyboardTop = keyboardFrameInWindow.minY
            
            // Get the duration of the current animation (if any)
            let duration = UIView.inheritedAnimationDuration
            
            // Calculate keyboard height
            let keyboardHeight = screenHeight - keyboardTop
            
            // Check if this is a realistic keyboard height - iOS keyboards are typically > 200pts
            // This prevents false positives during app initialization
            let isVisible = keyboardTop < screenHeight && keyboardHeight > 200
            
            // Log for debugging (separate from state changes)
            print("⌨️ Layout check - emptyView frame: \(emptyView.frame), inWindow: \(keyboardFrameInWindow)")
            print("⌨️ Keyboard metrics - Top: \(keyboardTop), Screen: \(screenHeight), Height: \(keyboardHeight)")
            print("⌨️ Duration: \(duration), SafeArea: \(String(describing: window.safeAreaInsets))")
            
            // Only update state from layout if we don't have an active notification-based update
            if duration == 0 {
                // This might be interactive keyboard dismissal which doesn't trigger notifications
                self.view.layoutIfNeeded()
            }
        }
    }
}

