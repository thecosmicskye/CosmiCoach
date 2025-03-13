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
}

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
                    // Debug border around entire ZStack (only shown when in debug mode)
                    if debugOutlineMode == .zStack {
                        Color.clear.border(Color.blue, width: 4)
                    }
                    // Calculate available scroll height by subtracting input height from total height
                    let inputHeight: CGFloat = 54
                    let availableHeight = geometry.size.height - inputHeight
                    
                    VStack(spacing: 0) {
                        ScrollView {
                            // Debug border to visualize ScrollView content area
                            if debugOutlineMode == .scrollView {
                                Color.clear
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .border(Color.green, width: 3)
                            }
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
                        
                        // Add bottom padding that adjusts with keyboard height
                        // This ensures the scroll area stops above the input+keyboard
                        Spacer()
                            .frame(height: keyboardState.isKeyboardVisible ? keyboardState.keyboardOffset + 10 : 54)
                            .border(debugOutlineMode == .spacer ? Color.yellow : Color.clear, width: 2)
                    }
                    .frame(height: geometry.size.height)
                    .border(debugOutlineMode == .vStack ? Color.orange : Color.clear, width: 2)
                    
                    // Keyboard attached input that sits at the bottom
                    VStack {
                        Spacer()
                        KeyboardAttachedView(
                            keyboardState: keyboardState,
                            text: $inputText,
                            onSend: sendMessage,
                            colorScheme: colorScheme,
                            themeColor: themeManager.accentColor(for: colorScheme),
                            isDisabled: chatManager.isProcessing,
                            debugOutlineMode: debugOutlineMode
                        )
                        .frame(height: keyboardState.isKeyboardVisible ? keyboardState.keyboardOffset + 22 : 54)
                        .border(debugOutlineMode == .keyboardAttachedView ? Color.purple : Color.clear, width: 2)
                    }
                    .border(debugOutlineMode == .keyboardAttachedView ? Color.cyan : Color.clear, width: 2)
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
    var debugOutlineMode: DebugOutlineMode
    
    var body: some View {
        HStack {
            TextField("Message", text: $text)
                .padding(.horizontal, 15)
                .padding(.vertical, 8)
                .background(
                    colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : Color(UIColor.secondarySystemBackground)
                )
                .cornerRadius(18)
                .border(debugOutlineMode == .textInput ? Color.pink : Color.clear, width: 1)
            
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(isDisabled || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : themeColor)
            }
            .disabled(isDisabled || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
        .border(debugOutlineMode == .textInput ? Color.mint : Color.clear, width: 2)
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
        uiViewController.updateText(text)
        uiViewController.updateAppearance(
            colorScheme: colorScheme,
            themeColor: themeColor,
            isDisabled: isDisabled,
            debugOutlineMode: debugOutlineMode
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
    private var debugOutlineMode: DebugOutlineMode
    
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
        print("⌨️ KeyboardVC lifecycle: viewDidLoad")
        
        // Add an empty view to track keyboard position
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        emptyView.backgroundColor = UIColor.systemBackground
        updateDebugBorders()
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
            isDisabled: isDisabled,
            debugOutlineMode: debugOutlineMode
        )
        inputHostView = UIHostingController(rootView: textView)
        
        // Add it to the view hierarchy
        addChild(inputHostView)
        inputHostView.view.translatesAutoresizingMaskIntoConstraints = false
        // Debug borders set in updateDebugBorders()
        view.addSubview(inputHostView.view)
        inputHostView.didMove(toParent: self)
        
        // Debug borders are set in updateDebugBorders()
        
        // Constrain the text input view
        NSLayoutConstraint.activate([
            inputHostView.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputHostView.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputHostView.view.heightAnchor.constraint(equalToConstant: 54)
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
            isDisabled: isDisabled,
            debugOutlineMode: debugOutlineMode
        )
    }
    
    // Helper method to update all debug borders based on current debug mode
    private func updateDebugBorders() {
        // Only apply borders if in appropriate debug mode
        emptyView.layer.borderWidth = debugOutlineMode == .keyboardAttachedView ? 4 : 0
        emptyView.layer.borderColor = UIColor.magenta.cgColor
        
        view.layer.borderWidth = debugOutlineMode == .keyboardAttachedView ? 2 : 0
        view.layer.borderColor = UIColor.systemTeal.cgColor
        
        if let hostView = inputHostView?.view {
            hostView.layer.borderWidth = debugOutlineMode == .textInput ? 3 : 0
            hostView.layer.borderColor = UIColor.systemIndigo.cgColor
        }
    }
    
    func updateAppearance(colorScheme: ColorScheme, themeColor: Color, isDisabled: Bool, debugOutlineMode: DebugOutlineMode) {
        self.colorScheme = colorScheme
        self.themeColor = themeColor
        self.isDisabled = isDisabled
        self.debugOutlineMode = debugOutlineMode
        
        // Update the debug borders
        updateDebugBorders()
        
        inputHostView.rootView = TextInputView(
            text: text,
            onSend: onSend,
            colorScheme: colorScheme,
            themeColor: themeColor,
            isDisabled: isDisabled,
            debugOutlineMode: debugOutlineMode
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

