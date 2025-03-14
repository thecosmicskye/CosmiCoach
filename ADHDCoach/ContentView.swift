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
var inputViewLayoutDebug = true

struct ContentView: View {
    @EnvironmentObject private var chatManager: ChatManager
    @EnvironmentObject private var eventKitManager: EventKitManager
    @EnvironmentObject private var memoryManager: MemoryManager
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingSettings = false
    @AppStorage("hasAppearedBefore") private var hasAppearedBefore = false
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var keyboardState = KeyboardState()
    @State private var inputText = ""
    
    // Debug outline state
    @State private var debugOutlineMode: DebugOutlineMode = .none
    @State private var showDebugTools: Bool = true
    
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
                    // Debug border around entire ZStack
                    if debugOutlineMode == .zStack {
                        Color.clear.border(Color.blue, width: 4)
                    }
                    
                    // Constants for layout management
                    let inputBaseHeight: CGFloat = 54
                    let safeAreaBottomPadding: CGFloat = 20
                    
                    // Content VStack
                    VStack(spacing: 0) {
                        // Main scrollable content area with message list
                        ScrollView {
                            // Debug border for ScrollView
                            if debugOutlineMode == .scrollView {
                                Color.clear
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .border(Color.green, width: 3)
                            }
                            
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
        // Track both visibility changes and height changes
        let heightChanged = visible && keyboardOffset != height
        let visibilityChanged = isKeyboardVisible != visible
        
        // Only trigger updates when there's an actual change
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
    // Input properties
    @Binding var text: String
    var onSend: () -> Void
    
    // Visual properties
    var colorScheme: ColorScheme
    var themeColor: Color
    var isDisabled: Bool
    var debugOutlineMode: DebugOutlineMode
    
    // Computed properties
    private var isButtonDisabled: Bool {
        isDisabled || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var buttonColor: Color {
        isButtonDisabled ? .gray : themeColor
    }
    
    var body: some View {
        HStack {
            // Text input field
            TextField("Message", text: $text)
                .padding(.horizontal, 15)
                .padding(.vertical, 8)
                .border(debugOutlineMode == .textInput ? Color.pink : Color.clear, width: 1)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .background(
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear {
                                if inputViewLayoutDebug {
                                    print("📏 TextField size: \(geometry.size), position: \(geometry.frame(in: .global).origin)")
                                }
                            }
                            .onChange(of: geometry.frame(in: .global)) { oldFrame, newFrame in
                                if inputViewLayoutDebug {
                                    print("📏 TextField position changed: \(oldFrame.origin) -> \(newFrame.origin)")
                                    print("📏 TextField size: \(newFrame.size)")
                                }
                            }
                    }
                )
            // Send button
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(buttonColor)
            }
            .disabled(isButtonDisabled)
        }
        .padding(.horizontal)
        .border(debugOutlineMode == .textInput ? Color.mint : Color.clear, width: 2)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        if inputViewLayoutDebug {
                            print("📏 text-field-row size: \(geometry.size), position: \(geometry.frame(in: .global).origin)")
                        }
                    }
                    .onChange(of: geometry.frame(in: .global)) { oldFrame, newFrame in
                        if inputViewLayoutDebug {
                            print("📏 text-field-row position changed: \(oldFrame.origin) -> \(newFrame.origin)")
                            print("📏 text-field-row size: \(newFrame.size)")
                        }
                    }
            }
        )
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
    var debugOutlineMode: DebugOutlineMode
    
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
    // Core views
    private var keyboardTrackingView = UIView()
    private var safeAreaView = UIView()
    private var inputHostView: UIHostingController<TextInputView>!
    
    // Constants
    private let inputViewHeight: CGFloat = 54
    private let keyboardVisibilityThreshold: CGFloat = 100
    
    // State and properties
    private var keyboardState: KeyboardState
    private var bottomConstraint: NSLayoutConstraint?
    private var text: Binding<String>
    private var onSend: () -> Void
    private var colorScheme: ColorScheme
    private var themeColor: Color
    private var isDisabled: Bool
    private var debugOutlineMode: DebugOutlineMode
    
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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupKeyboardObservers()
    }
    
    private func setupViews() {
        // Setup keyboard tracking view using UIKit's keyboardLayoutGuide
        setupKeyboardTrackingView()
        
        // Setup safe area visualization
        setupSafeAreaView()
        
        // Setup text input SwiftUI view
        setupTextInputView()
        
        // Apply debug styling if enabled
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
        
        // Use proper constraints that won't resize incorrectly on keyboard dismiss
        // Pin to screen edges horizontally and to keyboard layout guide vertically
        NSLayoutConstraint.activate([
            // Pin horizontally to view edges instead of keyboard guide
            keyboardTrackingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardTrackingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // Still track keyboard vertically
            keyboardTrackingView.topAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            keyboardTrackingView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.bottomAnchor)
        ])
    }
    
    private func setupTextInputView() {
        // Create the SwiftUI view
        let textView = createTextInputView()
        inputHostView = UIHostingController(rootView: textView)
        
        // Add the hosting controller as a child
        addChild(inputHostView)
        inputHostView.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputHostView.view)
        inputHostView.didMove(toParent: self)
        
        // Set up constraints for the input view
        NSLayoutConstraint.activate([
            inputHostView.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputHostView.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputHostView.view.heightAnchor.constraint(equalToConstant: inputViewHeight)
        ])
        
        // Attach the input view to the keyboard
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
    
    func updateContent(
        text: String,
        colorScheme: ColorScheme,
        themeColor: Color,
        isDisabled: Bool,
        debugOutlineMode: DebugOutlineMode
    ) {
        // Store previous properties to check for changes
        let textChanged = self.text.wrappedValue != text
        let themeColorChanged = self.themeColor != themeColor
        let disabledStateChanged = self.isDisabled != isDisabled
        let debugModeChanged = self.debugOutlineMode != debugOutlineMode
        let colorSchemeChanged = self.colorScheme != colorScheme
        
        // Update state properties
        self.colorScheme = colorScheme
        self.themeColor = themeColor
        self.isDisabled = isDisabled
        self.debugOutlineMode = debugOutlineMode
        
        // Only update SwiftUI view if content actually changed to avoid flickering
        if textChanged || themeColorChanged || disabledStateChanged || debugModeChanged || colorSchemeChanged {
            // Update SwiftUI view with new content
            inputHostView.rootView = createTextInputView()
            
            // Force layout to update immediately
            updateSwiftUIViewPosition()
            
            if inputViewLayoutDebug && (textChanged || themeColorChanged || disabledStateChanged) {
                print("📏 Updating TextInputView content with new properties")
            }
        }
        
        // Update debug visualization if needed
        if debugModeChanged {
            updateDebugBorders()
            
            // Bring safe area view to front when in safe area debug mode
            if debugOutlineMode == .safeArea {
                view.bringSubviewToFront(safeAreaView)
            } 
            // Bring keyboard tracking view to front when in keyboard view debug mode
            else if debugOutlineMode == .keyboardAttachedView {
                view.bringSubviewToFront(keyboardTrackingView)
            }
            // Always keep input view on top
            if let hostView = inputHostView?.view {
                view.bringSubviewToFront(hostView)
            }
        }
    }
    
    private func updateDebugBorders() {
        let isKeyboardAttachedDebug = debugOutlineMode == .keyboardAttachedView
        let isSafeAreaDebug = debugOutlineMode == .safeArea
        let isTextInputDebug = debugOutlineMode == .textInput
        
        // The keyboardTrackingView is not the entire safe area - it's just a UIView that's attached
        // to the keyboard layout guide. Visualize it with a background color+border.
        if isKeyboardAttachedDebug {
            keyboardTrackingView.layer.borderWidth = 2
            keyboardTrackingView.layer.borderColor = UIColor.systemBlue.cgColor
            keyboardTrackingView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.2)
        } else {
            keyboardTrackingView.layer.borderWidth = 0
            keyboardTrackingView.backgroundColor = UIColor.systemBackground
        }
        
        // Safe area visualization - use a different color to clearly distinguish from keyboard tracking
        if isSafeAreaDebug {
            safeAreaView.layer.borderWidth = 2
            safeAreaView.layer.borderColor = UIColor.systemGreen.cgColor
            safeAreaView.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.1)
        } else {
            safeAreaView.layer.borderWidth = 0
            safeAreaView.backgroundColor = .clear
        }
        
        // Main controller view
        view.layer.borderWidth = (isKeyboardAttachedDebug || isSafeAreaDebug) ? 1 : 0
        view.layer.borderColor = UIColor.systemTeal.cgColor
        
        // Text input host view
        if let hostView = inputHostView?.view {
            hostView.layer.borderWidth = isTextInputDebug ? 2 : 0
            hostView.layer.borderColor = UIColor.systemIndigo.cgColor
        }
    }
    
    private func setupKeyboardObservers() {
        // Add observers for keyboard notifications
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
        
        // Determine if keyboard is visible based on its position
        let isVisible = keyboardFrame.minY < UIScreen.main.bounds.height
        
        // Update keyboard state
        keyboardState.setKeyboardVisible(isVisible, height: keyboardFrame.height)
        
        // Log KeyboardAttachedView position if debug enabled
        if inputViewLayoutDebug {
            print("📏 KeyboardAttachedView position: \(self.view.frame.origin), size: \(self.view.frame.size)")
            print("📏 KeyboardAttachedView bounds: \(self.view.bounds)")
            print("📏 Keyboard frame: \(keyboardFrame), visible: \(isVisible)")
        }
        
        // Extract animation curve to match keyboard precisely
        let curveValue = curve.uintValue
        let animationOptions = UIView.AnimationOptions(rawValue: curveValue << 16)
        
        // Apply more precise animation with curves matching keyboard exactly
        UIView.animate(withDuration: duration, delay: 0, options: [animationOptions, .beginFromCurrentState]) {
            // Layout UIKit views to match keyboard movement
            self.view.layoutIfNeeded()
            
            // Force SwiftUI view to update by directly setting frame
            // This helps sync the SwiftUI TextField with the container
            self.updateSwiftUIViewPosition()
        }
    }
    
    private func updateSwiftUIViewPosition() {
        // Force SwiftUI layout to update immediately
        inputHostView.view.setNeedsLayout()
        inputHostView.view.layoutIfNeeded()
        
        // Log the updated position for debugging
        if inputViewLayoutDebug {
            print("📏 InputHostView updated position: \(self.inputHostView.view.frame.origin)")
        }
    }
    
    @objc func keyboardWillHide(_ notification: Notification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let curve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber else {
            return
        }
        
        // Update keyboard state
        keyboardState.setKeyboardVisible(false, height: 0)
        
        // Log KeyboardAttachedView position if debug enabled
        if inputViewLayoutDebug {
            print("📏 KeyboardAttachedView (keyboard hiding) position: \(self.view.frame.origin), size: \(self.view.frame.size)")
        }
        
        // Extract animation curve to match keyboard precisely
        let curveValue = curve.uintValue
        let animationOptions = UIView.AnimationOptions(rawValue: curveValue << 16)
        
        // Apply more precise animation with curves matching keyboard exactly
        UIView.animate(withDuration: duration, delay: 0, options: [animationOptions, .beginFromCurrentState]) {
            // Layout UIKit views to match keyboard movement
            self.view.layoutIfNeeded()
            
            // Force SwiftUI view to update by directly setting frame
            self.updateSwiftUIViewPosition()
        }
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        // Log position changes during layout if debug enabled
        if inputViewLayoutDebug {
            print("📏 KeyboardAttachedView (layoutSubviews) position: \(self.view.frame.origin), size: \(self.view.frame.size)")
            print("📏 InputHostView position: \(self.inputHostView.view.frame.origin), size: \(self.inputHostView.view.frame.size)")
            print("📏 KeyboardTrackingView position: \(self.keyboardTrackingView.frame.origin), size: \(self.keyboardTrackingView.frame.size)")
        }
        
        // Force SwiftUI view to update layout to match UIKit container
        updateSwiftUIViewPosition()
        
        // Only handle interactive keyboard dismissal when no animation is in progress
        guard let window = view.window, UIView.inheritedAnimationDuration == 0 else { return }
        
        // Track keyboard position during interactive gestures
        updateKeyboardPositionDuringInteractiveGesture(in: window)
    }
    
    private func updateKeyboardPositionDuringInteractiveGesture(in window: UIWindow) {
        // Get keyboard position in window coordinates
        let keyboardFrame = view.keyboardLayoutGuide.layoutFrame
        let screenHeight = window.frame.height
        
        // Convert keyboard frame to window coordinates for accurate measurement
        let keyboardFrameInWindow = view.convert(keyboardFrame, to: window)
        let keyboardTop = keyboardFrameInWindow.minY
        
        // Calculate keyboard height and determine visibility
        let keyboardHeight = screenHeight - keyboardTop
        let isVisible = keyboardTop < screenHeight && keyboardHeight > keyboardVisibilityThreshold
        
        // Log interactive gesture positions if debug enabled
        if inputViewLayoutDebug {
            print("📏 KeyboardAttachedView (interactive gesture) position: \(self.view.frame.origin), size: \(self.view.frame.size)")
            print("📏 Keyboard frame in window: \(keyboardFrameInWindow), visible: \(isVisible), height: \(keyboardHeight)")
        }
        
        // Update on every frame during interactive dismissal to ensure smooth tracking
        // This helps sync the TextField with the container movement
        let heightDifference = abs(keyboardState.keyboardOffset - (isVisible ? keyboardHeight : 0))
        let shouldUpdate = heightDifference > 1.0 || keyboardState.isKeyboardVisible != isVisible
        
        if shouldUpdate {
            // Update keyboard state with new height
            keyboardState.setKeyboardVisible(isVisible, height: isVisible ? keyboardHeight : 0)
            
            // Force immediate layout update for smooth interactive tracking
            view.layoutIfNeeded()
            
            // Force SwiftUI view to update by directly setting frame 
            updateSwiftUIViewPosition()
            
            if inputViewLayoutDebug {
                print("📏 Interactive gesture keyboard height: \(keyboardHeight)")
                if keyboardState.isKeyboardVisible != isVisible {
                    print("📏 Keyboard visibility changed to: \(isVisible)")
                }
            }
        }
    }
}

