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
    @FocusState private var isInputFocused: Bool
    @State private var showingSettings = false
    @State private var scrollToBottom = false
    @AppStorage("hasAppearedBefore") private var hasAppearedBefore = false
    @Environment(\.scenePhase) private var scenePhase
    
    // Add observer for chat history deletion
    init() {
        // This is needed because @EnvironmentObject isn't available in init
        print("⏱️ ContentView initializing")
    }
    
    // Setup keyboard appearance notification
    private func setupKeyboardObserver() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidShowNotification,
            object: nil,
            queue: .main
        ) { [self] _ in
            // Trigger scroll to bottom when keyboard appears
            scrollToBottom = true
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
                        statusMessagesProvider: chatManager.statusMessagesForMessage,
                        streamingUpdateCount: chatManager.streamingUpdateCount,
                        shouldScrollToBottom: $scrollToBottom,
                        isEmpty: chatManager.messages.isEmpty
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Dismiss keyboard when tapping on the scroll view area
                        isInputFocused = false
                    }
                
                    // Using our keyboard-attached input
                    KeyboardInputAccessory(
                        text: .constant(""),
                        onSend: sendMessage,
                        textFieldFocused: $isInputFocused,
                        colorScheme: colorScheme,
                        themeColor: themeManager.accentColor(for: colorScheme),
                        isDisabled: chatManager.isProcessing
                    )
                    .frame(height: 0) // No visible height - it's part of the keyboard now
                    .onTapGesture {
                        // Ensure the text field gets activated when we tap the SwiftUI component
                        isInputFocused = true
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
                        await memoryManager.loadMemory()
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
                        await memoryManager.loadMemory()
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
                                await memoryManager.loadMemory()
                                
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
        
        // Dismiss keyboard after sending
        isInputFocused = false
        
        // Add user message to chat
        chatManager.addUserMessage(content: text)
        
        // Trigger scroll to bottom after adding user message
        scrollToBottom = true
        
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
                    scrollToBottom(proxy: proxy)
                    shouldScrollToBottom = false
                    // Re-enable auto-scrolling when manually scrolled to bottom
                    autoScrollEnabled = true
                }
            }
            .onAppear {
                // Scroll to bottom on first appear
                scrollToBottom(proxy: proxy)
            }
        }
    }
    
    // Helper function to scroll to bottom
    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
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
        
        init(_ parent: ScrollDetector) {
            self.parent = parent
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let contentHeight = scrollView.contentSize.height
            let scrollViewHeight = scrollView.frame.size.height
            let scrollOffset = scrollView.contentOffset.y
            let bottomPosition = contentHeight - scrollViewHeight
            
            // If we're within 44 points of the bottom, consider it "at bottom"
            let isAtBottom = (bottomPosition - scrollOffset) <= 44
            
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
    var textFieldFocused: FocusState<Bool>.Binding
    var colorScheme: ColorScheme
    var themeColor: Color
    var isDisabled: Bool
    
    func makeUIViewController(context: Context) -> KeyboardAccessoryController {
        let controller = KeyboardAccessoryController()
        controller.delegate = context.coordinator
        controller.themeColor = UIColor(themeColor)
        controller.isDarkMode = colorScheme == .dark
        controller.isDisabled = isDisabled
        controller.textFieldText = text
        
        if textFieldFocused.wrappedValue {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                controller.activateTextField()
            }
        }
        
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
        
        // Update appearance when theme or color scheme changes
        if context.coordinator.parent.themeColor != themeColor || 
           context.coordinator.parent.colorScheme != colorScheme ||
           context.coordinator.parent.isDisabled != isDisabled {
            uiViewController.updateAppearance()
        }
        
        // Focus the text field if needed
        if textFieldFocused.wrappedValue && !uiViewController.textField.isFirstResponder {
            uiViewController.activateTextField()
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
            parent.textFieldFocused.wrappedValue = true
        }
        
        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.textFieldFocused.wrappedValue = false
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
    
    lazy var containerView: UIView = {
        let view = UIView()
        updateContainerAppearance(view)
        view.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 60)
        return view
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        textField.inputAccessoryView = nil
        
        // Observe keyboard frame change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame),
            name: UIResponder.keyboardWillChangeFrameNotification,
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
    
    func updateAppearance() {
        updateContainerAppearance(containerView)
        updateTextFieldAppearance()
        updateSendButtonAppearance()
    }
    
    private func updateContainerAppearance(_ view: UIView) {
        // Match system background colors for consistency
        view.backgroundColor = isDarkMode ? .systemBackground : .systemBackground
    }
    
    private func updateTextFieldAppearance() {
        textField.backgroundColor = isDarkMode ? .secondarySystemBackground : .secondarySystemBackground
        textField.textColor = isDarkMode ? .white : .black
        textField.borderStyle = .none
        textField.layer.cornerRadius = 18
        textField.clipsToBounds = true
        textField.attributedPlaceholder = NSAttributedString(
            string: "Message",
            attributes: [NSAttributedString.Key.foregroundColor: UIColor.placeholderText]
        )
    }
    
    private func updateSendButtonAppearance() {
        let textIsEmpty = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        sendButton.tintColor = (isDisabled || textIsEmpty) ? .gray : themeColor
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
              let curve = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt,
              endFrame.origin.y >= UIScreen.main.bounds.height,
              textField.isFirstResponder else { return }
        
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: UIView.AnimationOptions(rawValue: curve),
            animations: {
                self.textField.resignFirstResponder()
            }
        )
    }
    
    private func setupViews() {
        // Configure text field
        updateTextFieldAppearance()
        textField.delegate = delegate
        textField.returnKeyType = .send
        textField.autocorrectionType = .yes
        textField.text = textFieldText
        
        // Update the static property when text changes
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        
        // Configure send button
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        sendButton.setImage(UIImage(systemName: "arrow.up.circle.fill", withConfiguration: config), for: .normal)
        updateSendButtonAppearance()
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        
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
        
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            textField.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
            textField.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10),
            
            sendButton.leadingAnchor.constraint(equalTo: textField.trailingAnchor, constant: 8),
            sendButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            sendButton.centerYAnchor.constraint(equalTo: textField.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 44),
            sendButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    
    @objc func containerTapped() {
        activateTextField()
    }
    
    @objc func sendTapped() {
        if let delegate = delegate {
            _ = delegate.textFieldShouldReturn?(textField)
            textField.resignFirstResponder()
        }
    }
    
    func activateTextField() {
        if !isFirstResponder {
            becomeFirstResponder()
        }
        textField.becomeFirstResponder()
    }
    
    // These methods enable the keyboard input accessory view
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    override var inputAccessoryView: UIView? {
        return containerView
    }
    
    // Handle text field changes and update static property
    @objc func textFieldDidChange(_ textField: UITextField) {
        KeyboardAccessoryController.currentText = textField.text
        updateSendButtonAppearance()
    }
}
