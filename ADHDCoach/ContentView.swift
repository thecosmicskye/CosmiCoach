import SwiftUI
import Combine
import UIKit

// Keyboard state management enum
enum KeyboardState: Equatable {
    case hidden
    case showing
    case visible
    case dismissing
    
    var isVisible: Bool {
        self == .visible || self == .showing
    }
}

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
    
    // State management for keyboard accessory view
    @State private var keyboardState = KeyboardState.hidden
    
    // Add observer for chat history deletion
    init() {
        // This is needed because @EnvironmentObject isn't available in init
        print("⏱️ ContentView initializing")
    }
    
    // Setup keyboard appearance notification
    private func setupKeyboardObserver() {
        // When keyboard will show
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { [self] notification in
            // Update state to showing
            keyboardState = .showing
            
            // Check if auto-scroll is enabled or if we're at the bottom
            let isAtBottom = UserDefaults.standard.bool(forKey: "ChatIsAtBottom")
            
            // Only scroll when keyboard shows if we're explicitly at bottom
            if isAtBottom {
                // Delay the scroll slightly to allow layout to update
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    scrollToBottom = true
                }
            }
            
            // Log keyboard state transition
            print("⌨️ Keyboard state: \(KeyboardState.hidden) -> \(KeyboardState.showing)")
        }
        
        // When keyboard did show
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidShowNotification,
            object: nil,
            queue: .main
        ) { [self] _ in
            // Update state to fully visible
            keyboardState = .visible
            
            // Log keyboard state transition
            print("⌨️ Keyboard state: \(KeyboardState.showing) -> \(KeyboardState.visible)")
        }
        
        // When keyboard will hide
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { [self] _ in
            // Update state to dismissing
            keyboardState = .dismissing
            
            // Log keyboard state transition
            print("⌨️ Keyboard state: \(KeyboardState.visible) -> \(KeyboardState.dismissing)")
        }
        
        // When keyboard did hide
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidHideNotification,
            object: nil,
            queue: .main
        ) { [self] _ in
            // Update state to hidden
            keyboardState = .hidden
            
            // Log keyboard state transition
            print("⌨️ Keyboard state: \(KeyboardState.dismissing) -> \(KeyboardState.hidden)")
        }
    }
    
    // This function is now moved to the ChatScrollView component
    
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
                VStack(spacing: 0) {
                    // Chat messages list
                    ChatScrollView(
                        messages: chatManager.messages,
                        statusMessagesProvider: chatManager.combinedStatusMessagesForMessage,
                        streamingUpdateCount: chatManager.streamingUpdateCount,
                        shouldScrollToBottom: $scrollToBottom,
                        isEmpty: chatManager.messages.isEmpty
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Dismiss keyboard with state management when tapping on scroll view area
                        if let controller = KeyboardAccessoryController.sharedInstance {
                            controller.deactivateTextField()
                            keyboardState = .dismissing
                        } else {
                            // Fallback to standard method
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                    }
                
                                    // Using our keyboard-attached input
                    KeyboardInputAccessory(
                        text: .constant(""),
                        onSend: sendMessage,
                        colorScheme: colorScheme,
                        themeColor: themeManager.accentColor(for: colorScheme),
                        isDisabled: chatManager.isProcessing,
                        keyboardState: keyboardState
                    )
                    .frame(height: 0) // No visible height - it's part of the keyboard now
                    .onTapGesture {
                        // Activate the text field
                        KeyboardAccessoryController.sharedInstance?.activateTextField()
                    }
                }
            }
            .navigationTitle("Cosmic Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(colorScheme)
            .tint(themeManager.accentColor(for: colorScheme))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        // Dismiss keyboard first to prevent accessory view overlay issues
                        if let controller = KeyboardAccessoryController.sharedInstance {
                            controller.deactivateTextField()
                            keyboardState = .dismissing
                        } else {
                            // Fallback to standard method
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                        
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
                        if let controller = KeyboardAccessoryController.sharedInstance {
                            controller.deactivateTextField()
                        }
                        keyboardState = .hidden
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
                setupKeyboardObserver()
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
                        print("⏱️ ContentView.onAppear - Task started for memory loading and automatic message")
                        let _ = await memoryManager.readMemory()
                        if let fileURL = memoryManager.getMemoryFileURL() {
                            print("⏱️ ContentView.onAppear - Memory file exists: \(FileManager.default.fileExists(atPath: fileURL.path))")
                            print("⏱️ ContentView.onAppear - Memory content length: \(memoryManager.memoryContent.count)")
                        }
                        
                        // Log automatic message check
                        print("⏱️ ContentView.onAppear - About to check for automatic message")
                        
                        // Prepare to send automatic message
                        print("⏱️ ContentView.onAppear - Preparing automatic message check")
                        
                        // Check and potentially send an automatic message
                        print("⏱️ ContentView.onAppear - About to call checkAndSendAutomaticMessage() at \(Date())")
                        await chatManager.checkAndSendAutomaticMessage()
                        print("⏱️ ContentView.onAppear - Returned from checkAndSendAutomaticMessage() at \(Date())")
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
                    
                    // Only run the automatic message check if we've seen the app before
                    if hasAppearedBefore {
                        // Check for last session time
                        if let lastSessionTime = UserDefaults.standard.object(forKey: "last_app_session_time") as? TimeInterval {
                            let lastTime = Date(timeIntervalSince1970: lastSessionTime)
                            let timeSinceLastSession = Date().timeIntervalSince(lastTime)
                            print("⏱️ ContentView.onChange - Last session time: \(lastTime)")
                            print("⏱️ ContentView.onChange - Time since last session: \(timeSinceLastSession) seconds")
                            
                            // Launch a task to check for automatic messages
                            // This is critical because the normal onAppear doesn't seem to be firing consistently
                            Task {
                                print("⏱️ ContentView.onChange - Starting task for automatic message check at \(Date())")
                                let _ = await memoryManager.readMemory()
                                
                                // Check and potentially send an automatic message
                                await chatManager.checkAndSendAutomaticMessage()
                                print("⏱️ ContentView.onChange - Completed automatic message check at \(Date())")
                            }
                        }
                    } else {
                        print("⏱️ ContentView.onChange - Not checking automatic messages, hasAppearedBefore = false")
                    }
                }
            }
        }
    }
    
    private func sendMessage() {
        guard let text = KeyboardAccessoryController.currentText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        
        // Dismiss keyboard using our accessory controller for better state management
        if let controller = KeyboardAccessoryController.sharedInstance {
            // Use our state-aware method instead of generic resignFirstResponder
            controller.deactivateTextField()
        } else {
            // Fallback to standard method if controller isn't available
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        
        // Update keyboard state
        keyboardState = .dismissing
        
        // Add user message to chat
        chatManager.addUserMessage(content: text)
        
        // Trigger scroll to bottom after adding user message
        scrollToBottom = true
        
        // Ensure we mark as at bottom when sending a message
        UserDefaults.standard.set(true, forKey: "ChatIsAtBottom")
        UserDefaults.standard.synchronize()
        
        // Send to Claude API
        Task {
            // Get context from EventKit
            let calendarEvents = eventKitManager.fetchUpcomingEvents(days: 7)
            let reminders = await eventKitManager.fetchReminders()
            
            await chatManager.sendMessageToClaude(
                userMessage: text,
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
        .padding(.vertical, 8)
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

#Preview("Chat Components") {
    VStack {
        ChatScrollView(
            messages: [
                ChatMessage(id: UUID(), content: "Hello there!", timestamp: Date(), isUser: true, isComplete: true),
                ChatMessage(id: UUID(), content: "Hi! How can I help you today?", timestamp: Date(), isUser: false, isComplete: true)
            ],
            statusMessagesProvider: { _ in [] },
            streamingUpdateCount: 0,
            shouldScrollToBottom: .constant(false),
            isEmpty: false
        )
        .frame(height: 300)
        
        Divider()
        
        ChatScrollView(
            messages: [],
            statusMessagesProvider: { _ in [] },
            streamingUpdateCount: 0,
            shouldScrollToBottom: .constant(false),
            isEmpty: true
        )
        .frame(height: 300)
    }
    .padding()
}

// Implements an input bar that sticks to the keyboard during interactive dismissal
struct KeyboardInputAccessory: UIViewControllerRepresentable {
    @Binding var text: String
    var onSend: () -> Void
    var colorScheme: ColorScheme
    var themeColor: Color
    var isDisabled: Bool
    var keyboardState: KeyboardState
    
    func makeUIViewController(context: Context) -> KeyboardAccessoryController {
        let controller = KeyboardAccessoryController()
        controller.delegate = context.coordinator
        controller.themeColor = UIColor(themeColor)
        controller.isDarkMode = colorScheme == .dark
        controller.isDisabled = isDisabled
        controller.textFieldText = text
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: KeyboardAccessoryController, context: Context) {
        // Avoid text update while editing to prevent cursor jumps
        if !uiViewController.textField.isFirstResponder {
            uiViewController.textField.text = text
        }
        
        // Update controller properties
        uiViewController.textFieldText = text
        uiViewController.themeColor = UIColor(themeColor)
        uiViewController.isDarkMode = colorScheme == .dark
        uiViewController.isDisabled = isDisabled
        
        // Update container height based on keyboard state
        let isKeyboardHidden = !keyboardState.isVisible
        uiViewController.updateContainerHeight(forKeyboardHidden: isKeyboardHidden)
        
        // Update appearance when theme, color scheme, keyboard state, or disabled state changes
        if context.coordinator.parent.themeColor != themeColor || 
           context.coordinator.parent.colorScheme != colorScheme ||
           context.coordinator.parent.isDisabled != isDisabled ||
           context.coordinator.parent.keyboardState != keyboardState {
            uiViewController.updateAppearance()
        }
        
        context.coordinator.parent = self
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: KeyboardInputAccessory
        
        init(_ parent: KeyboardInputAccessory) {
            self.parent = parent
        }
        
        func textFieldDidChangeSelection(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }
        
        func textFieldDidBeginEditing(_ textField: UITextField) {
            // Update container height in controller
            if let controller = textField.getKeyboardAccessoryController() {
                controller.updateContainerHeight(forKeyboardHidden: false)
            }
        }
        
        func textFieldDidEndEditing(_ textField: UITextField) {
            // Update container height in controller
            if let controller = textField.getKeyboardAccessoryController() {
                // Ensure this happens immediately for proper safe area padding
                DispatchQueue.main.async {
                    controller.updateContainerHeight(forKeyboardHidden: true)
                }
            }
        }
        
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            if !(textField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                parent.onSend()
                textField.resignFirstResponder()
            }
            return true
        }
    }
}

class KeyboardAccessoryController: UIViewController {
    var textField = UITextField()
    var sendButton = UIButton(type: .system)
    var delegate: UITextFieldDelegate?
    var themeColor: UIColor = .systemBlue
    var isDarkMode: Bool = false
    var isDisabled: Bool = false
    var textFieldText: String = ""
    
    // Static property to access the current text from anywhere
    static var currentText: String?
    
    // Static shared instance for easier access
    static var sharedInstance: KeyboardAccessoryController?
    
    // State management
    private var accessoryViewDisplayState: String = "hidden"
    private var lastKeyboardAnimation: TimeInterval = 0
    
    lazy var containerView: UIView = {
        let view = UIView()
        updateContainerAppearance(view)
        return view
    }()
    
    // Track keyboard state - determined directly from responder status
    private var isKeyboardVisible: Bool {
        return textField.isFirstResponder
    }
    
    // Keep track of last applied height to prevent unnecessary updates
    private var lastAppliedHeight: CGFloat = 90.0
    
    // Debug mode for transitions
    private let debugStateTransitions = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set up the container view
        containerView.translatesAutoresizingMaskIntoConstraints = false
        // Initial height should be 90.0 (for safe area padding) since keyboard is not shown by default
        containerView.frame.size.height = 90.0
        lastAppliedHeight = 90.0
        
        // Set the shared instance for easier access
        KeyboardAccessoryController.sharedInstance = self
        
        setupViews()
        textField.inputAccessoryView = nil
        
        // Observe keyboard frame change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        
        // Observe keyboard will show and hide notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        
        // Observe theme changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: NSNotification.Name("ThemeDidChangeNotification"),
            object: nil
        )
        
        // Observe trait collection changes for dark/light mode
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userInterfaceStyleDidChange),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        // Add a special observer for explicit keyboard dismissal requests
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleForcedDismissal),
            name: NSNotification.Name("DismissKeyboardNotification"),
            object: nil
        )
    }
    
    @objc private func keyboardWillShow(_ notification: Notification) {
        if debugStateTransitions {
            print("⌨️ KeyboardAccessory: keyboardWillShow notification received")
        }
        
        // Get animation parameters if available
        var duration: TimeInterval = 0.25
        if let userInfo = notification.userInfo,
           let animDuration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval {
            duration = animDuration
            lastKeyboardAnimation = Date().timeIntervalSince1970 + duration
        }
        
        // Update accessory state to match keyboard
        updateTextFieldAppearance()
        updateContainerHeight(forKeyboardHidden: false)
        
        // Do a delayed update after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) {
            // Only apply if we're still in the same animation sequence
            if Date().timeIntervalSince1970 >= self.lastKeyboardAnimation {
                self.updateContainerHeight(forKeyboardHidden: false)
            }
        }
    }
    
    @objc private func keyboardWillHide(_ notification: Notification) {
        if debugStateTransitions {
            print("⌨️ KeyboardAccessory: keyboardWillHide notification received")
        }
        
        // Get animation parameters if available
        var duration: TimeInterval = 0.25
        if let userInfo = notification.userInfo,
           let animDuration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval {
            duration = animDuration
            lastKeyboardAnimation = Date().timeIntervalSince1970 + duration
        }
        
        // Update appearance immediately
        updateTextFieldAppearance()
        updateContainerHeight(forKeyboardHidden: true)
        
        // Then delayed update to match keyboard animation
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) {
            // Only apply if we're still in the same animation sequence
            if Date().timeIntervalSince1970 >= self.lastKeyboardAnimation {
                self.updateContainerHeight(forKeyboardHidden: true)
            }
        }
    }
    
    
    func updateContainerHeight(forKeyboardHidden: Bool) {
        // Set appropriate height based on keyboard state
        let newHeight: CGFloat = forKeyboardHidden ? 90.0 : 60.0
        
        // Check if we're already at the desired height to prevent flickering
        if abs(lastAppliedHeight - newHeight) < 0.1 {
            return // Skip if height is already correct
        }
        
        // Track this state change for debugging
        let oldState = accessoryViewDisplayState
        accessoryViewDisplayState = forKeyboardHidden ? "hidden" : "visible"
        
        if debugStateTransitions {
            print("⌨️ KeyboardAccessory: State transition \(oldState) → \(accessoryViewDisplayState) (height: \(lastAppliedHeight) → \(newHeight))")
        }
        
        // Update frame directly - no animation to avoid conflicts with iOS animations
        var newFrame = containerView.frame
        newFrame.size.height = newHeight
        containerView.frame = newFrame
        
        // Update parent frame if possible
        if let inputAccessoryView = self.inputAccessoryView {
            inputAccessoryView.frame.size.height = newHeight
        }
        
        // Remember this height
        lastAppliedHeight = newHeight
        
        // Ensure child views are updated properly if needed
        updateTextFieldAppearance()
    }
    
    
    // Forward the legacy method to our new implementation
    func updateContainerConstraints() {
        // Just check text field responder state for now 
        let keyboardShouldBeHidden = !textField.isFirstResponder
        updateContainerHeight(forKeyboardHidden: keyboardShouldBeHidden)
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            updateAppearance()
        }
    }
    
    @objc private func userInterfaceStyleDidChange() {
        updateAppearance()
    }
    
    @objc private func themeDidChange() {
        updateAppearance()
    }
    
    @objc private func handleForcedDismissal() {
        // Force deactivation of the text field and update container height
        if textField.isFirstResponder {
            textField.resignFirstResponder()
        }
        
        // Update the container height to hidden state
        updateContainerHeight(forKeyboardHidden: true)
        
        // Also force another update after a slight delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.updateContainerHeight(forKeyboardHidden: true)
        }
    }
    
    func updateAppearance() {
        updateContainerAppearance(containerView)
        updateTextFieldAppearance()
        updateSendButtonAppearance()
        updateContainerConstraints()
    }
    
    private func updateContainerAppearance(_ view: UIView) {
        // Match system background colors for consistency
        view.backgroundColor = isDarkMode ? .systemBackground : .systemBackground
    }
    
    func updateTextFieldAppearance() {
        // Set background color based on mode, without the blue highlight
        let backgroundColor = isDarkMode ? UIColor.secondarySystemBackground : UIColor.secondarySystemBackground
        let textColor = isDarkMode ? UIColor.white : UIColor.black
        
        // Apply consistent styling
        textField.backgroundColor = backgroundColor
        textField.textColor = textColor
        textField.borderStyle = .none
        textField.layer.cornerRadius = 18
        textField.clipsToBounds = true
        textField.attributedPlaceholder = NSAttributedString(
            string: "Message",
            attributes: [NSAttributedString.Key.foregroundColor: UIColor.placeholderText]
        )
        
        // Update container height based on keyboard state
        updateContainerHeight(forKeyboardHidden: !textField.isFirstResponder)
    }
    
    // Method to maintain compatibility with older code
    func setDebugBackground(active: Bool) {
        updateTextFieldAppearance()
    }
    
    private func updateSendButtonAppearance() {
        let textIsEmpty = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        sendButton.tintColor = (isDisabled || textIsEmpty) ? .gray : themeColor
        
        // Remove any existing targets to avoid multiple attachments
        sendButton.removeTarget(nil, action: nil, for: .touchUpInside)
        
        // Only add the action target if text is not empty and not disabled
        if !textIsEmpty && !isDisabled {
            sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func keyboardWillChangeFrame(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let curve = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt else { return }
        
        // Detect swipe to dismiss keyboard
        if endFrame.origin.y >= UIScreen.main.bounds.height && textField.isFirstResponder {
            print("Keyboard being dismissed by swipe gesture")
            
            // Update the container height BEFORE resigning first responder
            updateContainerHeight(forKeyboardHidden: true)
            
            // Then resign first responder
            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: UIView.AnimationOptions(rawValue: curve),
                animations: {
                    self.textField.resignFirstResponder()
                },
                completion: { _ in
                    // One final update after animation completes
                    self.updateContainerHeight(forKeyboardHidden: true)
                }
            )
        }
    }
    
    private func setupViews() {
        // Set initial container view size - use 90.0 as default safe area padding height
        containerView.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 90.0)
        
        // Configure text field
        updateTextFieldAppearance()
        textField.delegate = delegate
        textField.returnKeyType = .default
        textField.autocorrectionType = .yes
        textField.text = textFieldText
        
        // Update the static property when text changes
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        
        // Configure send button
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        sendButton.setImage(UIImage(systemName: "arrow.up.circle.fill", withConfiguration: config), for: .normal)
        updateSendButtonAppearance()
        
        // Add container tap handler
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(containerTapped))
        containerView.addGestureRecognizer(tapGesture)
        
        // Add subviews and configure layout
        containerView.addSubview(textField)
        containerView.addSubview(sendButton)
        
        textField.translatesAutoresizingMaskIntoConstraints = false
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        
        // Add padding to text field
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 15, height: textField.frame.height))
        textField.leftViewMode = .always
        textField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 15, height: textField.frame.height))
        textField.rightViewMode = .always
        
        // Set fixed constraints that won't change
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16.0),
            // Fixed height and centerY alignment ensures consistent sizing regardless of container height
            textField.heightAnchor.constraint(equalToConstant: 36.0),
            textField.centerYAnchor.constraint(equalTo: containerView.topAnchor, constant: 30.0),
            
            sendButton.leadingAnchor.constraint(equalTo: textField.trailingAnchor, constant: 8.0),
            sendButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16.0),
            sendButton.centerYAnchor.constraint(equalTo: textField.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 44.0),
            sendButton.heightAnchor.constraint(equalToConstant: 44.0)
        ])
    }
    
    @objc func containerTapped() {
        activateTextField()
    }
    
    @objc func sendTapped() {
        // Prevent any action if text field is empty
        guard let text = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return
        }
        
        if let delegate = delegate {
            _ = delegate.textFieldShouldReturn?(textField)
            textField.resignFirstResponder()
        }
    }
    
    func activateTextField() {
        if debugStateTransitions {
            print("⌨️ KeyboardAccessory: activateTextField() called, current state: \(accessoryViewDisplayState)")
        }
        
        // Ensure controller is first responder
        if !isFirstResponder {
            becomeFirstResponder()
        }
        
        // If the text field isn't currently focused, focus it
        if !textField.isFirstResponder {
            textField.becomeFirstResponder()
            
            // Update container height proactively
            updateContainerHeight(forKeyboardHidden: false)
            
            // Also schedule a delayed update to handle any transition issues
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.updateContainerHeight(forKeyboardHidden: false)
            }
        }
    }
    
    // Helper method for deactivating text field 
    func deactivateTextField() {
        if debugStateTransitions {
            print("⌨️ KeyboardAccessory: deactivateTextField() called, current state: \(accessoryViewDisplayState)")
        }
        
        // Only resign if we're actually first responder
        if textField.isFirstResponder {
            // Update height first
            updateContainerHeight(forKeyboardHidden: true)
            
            // Then resign
            textField.resignFirstResponder()
            
            // Also schedule a delayed update to handle any transition issues
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.updateContainerHeight(forKeyboardHidden: true)
            }
        }
    }
    
    // These methods enable the keyboard input accessory view
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    override var inputAccessoryView: UIView? {
        // Set the height based on focus state before returning
        let height = textField.isFirstResponder ? 60.0 : 90.0
        containerView.frame.size.height = height
        return containerView
    }
    
    // Handle text field changes and update static property
    @objc func textFieldDidChange(_ textField: UITextField) {
        KeyboardAccessoryController.currentText = textField.text
        updateSendButtonAppearance()
    }
}

// Extension to help find the KeyboardAccessoryController
extension UITextField {
    func getKeyboardAccessoryController() -> KeyboardAccessoryController? {
        // Find controller in responder chain
        var responder: UIResponder? = self
        while let nextResponder = responder?.next {
            if let controller = nextResponder as? KeyboardAccessoryController {
                return controller
            }
            responder = nextResponder
        }
        
        // Fallback to shared instance
        return KeyboardAccessoryController.sharedInstance
    }
}

