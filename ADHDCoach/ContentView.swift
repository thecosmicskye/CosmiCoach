import SwiftUI
import Combine
import UIKit

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
    @EnvironmentObject private var locationManager: LocationManager
    
    // MARK: - Environment Values
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    
    // MARK: - State
    @AppStorage("hasAppearedBefore") private var hasAppearedBefore = false
    @State private var showingSettings = false
    @State private var inputText = ""
    @StateObject private var keyboardState = KeyboardState()
    
    // MARK: - Debug State
    @State private var debugOutlineMode: DebugOutlineMode = .none
    @State private var showDebugTools: Bool = false
    
    // MARK: - Methods
    /// Sets up notification observer for chat history deletion
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
    }
    
    var body: some View {
        NavigationStack {
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
                        ScrollView {
                            // Message content - either empty state or message list
                            if chatManager.messages.isEmpty {
                                EmptyStateView()
                                    .border(debugOutlineMode == .messageList ? Color.purple : Color.clear, width: 2)
                            } else {
                                MessageListView(
                                    messages: chatManager.messages,
                                    statusMessagesProvider: chatManager.combinedStatusMessagesForMessage
                                )
                                .border(debugOutlineMode == .messageList ? Color.purple : Color.clear, width: 2)
                            }
                            
                            // Debug border for ScrollView
                            if debugOutlineMode == .scrollView {
                                Color.clear
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .border(Color.green, width: 3)
                            }
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .scrollClipDisabled()
                        .border(debugOutlineMode == .scrollView ? Color.green : Color.clear, width: 2)
                        
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
            }
            .ignoresSafeArea(.keyboard)
            .navigationTitle("Cosmic Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(colorScheme)
            .tint(themeManager.accentColor(for: colorScheme))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        hideKeyboard()
                        showingSettings = true
                    }) {
                        Image(systemName: "gear")
                            .font(.system(size: 22))
                            .foregroundColor(themeManager.accentColor(for: colorScheme))
                    }
                }
                
                // Debug outline toggle (only shown when debug tools are enabled)
                if showDebugTools {
                    ToolbarItem(placement: .navigationBarTrailing) {
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
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(themeManager)
                    .environmentObject(memoryManager)
                    .environmentObject(locationManager)
                    .environmentObject(chatManager)
                    .onAppear {
                        hideKeyboard()
                    }
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
            .onChange(of: scenePhase) { oldPhase, newPhase in
                // Check for transition to active state (from any state)
                if newPhase == .active && hasAppearedBefore {
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
    // MARK: - Keyboard & Message Handling
    
    /// Dismisses the keyboard
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
            
            // Get context data
            let calendarEvents = eventKitManager.fetchUpcomingEvents(days: 7)
            let reminders = await eventKitManager.fetchReminders()
            
            // Send to API
            await chatManager.sendMessageToClaude(
                userMessage: messageToSend,
                calendarEvents: calendarEvents,
                reminders: reminders
            )
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

/// Displays the list of chat messages
struct MessageListView: View {
    let messages: [ChatMessage]
    let statusMessagesProvider: (ChatMessage) -> [OperationStatusMessage]
    
    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(messages) { message in
                VStack(spacing: 4) {
                    MessageBubbleView(message: message)
                        .padding(.horizontal)
                    
                    // Show operation status messages after AI messages
                    if !message.isUser && message.isComplete {
                        ForEach(statusMessagesProvider(message)) { statusMessage in
                            OperationStatusView(statusMessage: statusMessage)
                                .padding(.horizontal)
                        }
                    }
                }
            }
            
            // Invisible anchor for scrolling
            Color.clear
                .frame(height: 1)
                .id("bottomID")
        }
        .padding(.top, 8)
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
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(buttonColor)
            }
            .disabled(isButtonDisabled)
            .animation(.default, value: isButtonDisabled)
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
        uiViewController.updateContent(
            text: text,
            colorScheme: colorScheme,
            themeColor: themeColor,
            isDisabled: isDisabled,
            debugOutlineMode: debugOutlineMode
        )
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
    private var keyboardState: KeyboardState
    private var bottomConstraint: NSLayoutConstraint?
    private var text: Binding<String>
    private var onSend: () -> Void
    private var colorScheme: ColorScheme
    private var themeColor: Color
    private var isDisabled: Bool
    private var debugOutlineMode: DebugOutlineMode
    
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
        // Check for changes
        let textChanged = self.text.wrappedValue != text
        let themeColorChanged = self.themeColor != themeColor
        let disabledStateChanged = self.isDisabled != isDisabled
        let debugModeChanged = self.debugOutlineMode != debugOutlineMode
        let colorSchemeChanged = self.colorScheme != colorScheme
        let visualPropertiesChanged = themeColorChanged || disabledStateChanged || debugModeChanged || colorSchemeChanged
        
        // Update text (without animation if clearing)
        if textChanged && text.isEmpty {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.text.wrappedValue = text
            CATransaction.commit()
        } else {
            self.text.wrappedValue = text
        }
        
        // Update other properties
        self.colorScheme = colorScheme
        self.themeColor = themeColor
        self.isDisabled = isDisabled
        self.debugOutlineMode = debugOutlineMode
        
        // Update SwiftUI view if visual properties changed
        if visualPropertiesChanged {
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

