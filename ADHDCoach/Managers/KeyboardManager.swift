import SwiftUI
import Combine

/// Manages keyboard-related functionality including state tracking, notifications, and height calculations
class KeyboardManager: ObservableObject {
    // MARK: - Published Properties
    
    /// Current keyboard height when visible, or 0 when hidden
    @Published var keyboardOffset: CGFloat = 0
    
    /// Whether the keyboard is currently visible
    @Published var isKeyboardVisible: Bool = false
    
    /// Height of the input view component
    @Published var inputViewHeight: CGFloat = 0
    
    /// Flag indicating if scroll position restoration is in progress
    @Published var isRestoringScrollPosition: Bool = false
    
    // MARK: - Private Properties
    
    /// Cancellables for keyboard notifications
    private var cancellables = Set<AnyCancellable>()
    
    /// Current scroll position for saving/restoration
    private var scrollPosition: CGPoint = .zero
    
    /// Flag to prevent scroll position checks during programmatic scrolling
    private var isScrollingToBottomProgrammatically = false
    
    // MARK: - Constants
    
    /// Default font for text input calculations
    var defaultFont: UIFont { UIFont.systemFont(ofSize: UIFont.systemFontSize * 1.25) }
    
    /// Height for a single line of text
    var singleLineHeight: CGFloat { defaultFont.lineHeight + 16 } // Line height + padding
    
    /// Height for the send button row
    var buttonRowHeight: CGFloat = 54
    
    /// Default height for the input view
    var defaultInputHeight: CGFloat { singleLineHeight + 16 + buttonRowHeight } // Text + padding + button row
    
    /// Key for saving scroll position in UserDefaults
    private let scrollPositionKey = "saved_scroll_position_y"
    
    // MARK: - Initialization
    
    init() {
        // Initialize with calculated default height
        self.inputViewHeight = defaultInputHeight
        
        // Load saved scroll position from UserDefaults on initialization
        if let savedY = UserDefaults.standard.object(forKey: scrollPositionKey) as? CGFloat, savedY > 0 {
            self.scrollPosition = CGPoint(x: 0, y: savedY)
        }
        
        // Set up keyboard and input view height notification observers
        setupKeyboardObservers()
        
        // Set up app lifecycle notification observers
        setupAppLifecycleObservers()
    }
    
    deinit {
        // Clean up notification observers
        cancellables.removeAll()
    }
    
    // MARK: - Notification Setup
    
    /// Sets up all keyboard-related notification observers
    private func setupKeyboardObservers() {
        // Keyboard will show notification
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { [weak self] notification in
                self?.handleKeyboardWillShow(notification)
            }
            .store(in: &cancellables)
        
        // Keyboard will hide notification
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] notification in
                self?.handleKeyboardWillHide(notification)
            }
            .store(in: &cancellables)
        
        // Keyboard frame change notification
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .sink { [weak self] notification in
                self?.handleKeyboardWillChangeFrame(notification)
            }
            .store(in: &cancellables)
        
        // Input view height change notification
        NotificationCenter.default.publisher(for: Notification.Name("InputViewHeightChanged"))
            .sink { [weak self] notification in
                self?.handleInputViewHeightChange(notification)
            }
            .store(in: &cancellables)
    }
    
    /// Sets up app lifecycle notification observers
    private func setupAppLifecycleObservers() {
        // App will resign active (going to background)
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.handleAppWillResignActive()
            }
            .store(in: &cancellables)
            
        // App did become active
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.handleAppDidBecomeActive()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Notification Handlers
    
    /// Handles the keyboard will show notification
    /// - Parameter notification: The notification containing keyboard information
    private func handleKeyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }
        
        setKeyboardVisible(true, height: keyboardFrame.height)
    }
    
    /// Handles the keyboard will hide notification
    /// - Parameter notification: The notification containing keyboard information
    private func handleKeyboardWillHide(_ notification: Notification) {
        setKeyboardVisible(false, height: 0)
    }
    
    /// Handles the keyboard will change frame notification
    /// - Parameter notification: The notification containing keyboard information
    private func handleKeyboardWillChangeFrame(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }
        
        // Determine if keyboard is visible based on position
        let screenHeight = UIScreen.main.bounds.height
        let isVisible = keyboardFrame.minY < screenHeight
        
        setKeyboardVisible(isVisible, height: isVisible ? keyboardFrame.height : 0)
    }
    
    /// Handles notifications when input view height changes
    /// - Parameter notification: The notification containing height information
    private func handleInputViewHeightChange(_ notification: Notification) {
        guard let height = notification.userInfo?["height"] as? CGFloat else { return }
        
        // Update our stored height
        inputViewHeight = height
        
        // Notify any subscribers about the change
        NotificationCenter.default.post(
            name: NSNotification.Name("KeyboardStateChanged"),
            object: nil,
            userInfo: ["height": height]
        )
    }
    
    /// Handles app will resign active notification (going to background)
    private func handleAppWillResignActive() {
        // Save scroll position before going to background
        saveScrollPosition()
    }
    
    /// Handles app did become active notification
    private func handleAppDidBecomeActive() {
        // Important: Immediately set this flag to prevent any auto-scrolling attempts
        isRestoringScrollPosition = true
        
        // Schedule restoration with a brief delay to allow views to be ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.restoreScrollPosition {
                // Check if we're at bottom after restoration is complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // You might want to notify observers that restoration is complete
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ScrollPositionRestored"),
                        object: nil
                    )
                }
            }
        }
    }
    
    // MARK: - Public Methods
    
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
        
        // When keyboard is visible, account for both keyboard height AND text input height difference
        if isKeyboardVisible {
            // Calculate height difference from default
            let heightDifference = inputViewHeight - defaultInputHeight
            
            // With keyboard open, ensure we have enough space for text input AND button row
            return keyboardOffset + safeAreaPadding + buttonRowHeight + (heightDifference > 0 ? heightDifference : 0)
        } else {
            // When keyboard is hidden, just use the actual base height
            return actualBaseHeight
        }
    }
    
    /// Resets the input view height to default
    func resetInputViewHeight() {
        inputViewHeight = defaultInputHeight
        
        // Notify about height change
        NotificationCenter.default.post(
            name: NSNotification.Name("InputViewHeightChanged"),
            object: nil,
            userInfo: ["height": defaultInputHeight]
        )
    }
    
    /// Dismisses the keyboard
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    /// Finds the main ScrollView in the view hierarchy
    func findScrollView() -> UIScrollView? {
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
    
    /// Checks if the scroll view is at the bottom
    /// - Returns: True if the scroll view is at or very close to the bottom
    func isScrollViewAtBottom(threshold: CGFloat = 15) -> Bool {
        guard let scrollView = findScrollView() else { return true }
        
        let contentHeight = scrollView.contentSize.height
        let scrollViewHeight = scrollView.bounds.height
        let currentPosition = scrollView.contentOffset.y
        let maximumScrollPosition = max(0, contentHeight - scrollViewHeight)
        
        // Only calculate when we have enough scrollable content
        let hasScrollableContent = contentHeight > scrollViewHeight + 50
        
        // Strict check: only consider at bottom if very close to max position
        return !hasScrollableContent || currentPosition >= (maximumScrollPosition - threshold)
    }
    
    /// Scrolls to the bottom of the ScrollView
    /// - Parameters:
    ///   - animated: Whether to animate the scrolling
    ///   - completion: Optional callback when scrolling completes
    func scrollToBottom(animated: Bool = true, completion: (() -> Void)? = nil) {
        // Set flag to prevent position checks during scrolling
        isScrollingToBottomProgrammatically = true
        
        guard let scrollView = findScrollView() else {
            isScrollingToBottomProgrammatically = false
            completion?()
            return
        }
        
        let contentHeight = scrollView.contentSize.height
        let scrollViewHeight = scrollView.bounds.height
        let maximumScrollPosition = max(0, contentHeight - scrollViewHeight)
        
        // Use the appropriate animation approach
        if animated {
            UIView.animate(withDuration: 0.3, animations: {
                scrollView.contentOffset = CGPoint(x: 0, y: maximumScrollPosition)
            }, completion: { _ in
                // Ensure we're at the bottom with a follow-up check
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    UIView.performWithoutAnimation {
                        scrollView.contentOffset = CGPoint(x: 0, y: maximumScrollPosition)
                    }
                    
                    // Reset flag and call completion after animations are done
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.isScrollingToBottomProgrammatically = false
                        completion?()
                    }
                }
            })
        } else {
            UIView.performWithoutAnimation {
                scrollView.contentOffset = CGPoint(x: 0, y: maximumScrollPosition)
                scrollView.layoutIfNeeded()
            }
            
            // Reset flag and call completion
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.isScrollingToBottomProgrammatically = false
                completion?()
            }
        }
    }
    
    // MARK: - Scroll Position Management
    
    /// Saves the current scroll position
    /// - Returns: True if a valid position was saved
    @discardableResult
    func saveScrollPosition() -> Bool {
        guard let scrollView = findScrollView() else { return false }
        
        let newPosition = scrollView.contentOffset
        
        // Only save valid scroll positions and protect from negative values
        if newPosition.y > 0 {
            // First save to UserDefaults
            UserDefaults.standard.set(newPosition.y, forKey: scrollPositionKey)
            
            // Then update internal state
            scrollPosition = newPosition
            print("📱 Saving scroll position: \(newPosition.y)")
            return true
        } else if scrollPosition.y > 0 {
            // If current position is invalid but we have a saved one, keep using it
            print("⚠️ Current position invalid: \(newPosition.y), keeping saved: \(scrollPosition.y)")
            return true
        } else {
            print("⚠️ No valid scroll position to save: current=\(newPosition.y)")
            return false
        }
    }
    
    /// Restores the saved scroll position
    /// - Parameter completion: Callback when restoration is complete
    func restoreScrollPosition(completion: (() -> Void)? = nil) {
        // Set flag to indicate restoration is in progress
        isRestoringScrollPosition = true
        
        // Get the most up-to-date position from UserDefaults
        let positionFromUserDefaults: CGFloat? = UserDefaults.standard.object(forKey: scrollPositionKey) as? CGFloat
        
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
                
                print("📱 Restoring scroll position: \(finalPosition.y) (content size: \(contentSize))")
                
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
                        self.isRestoringScrollPosition = false
                        completion?()
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
                    self.isRestoringScrollPosition = false
                    completion?()
                }
            }
        } else {
            print("⚠️ No valid scroll position to restore")
            isRestoringScrollPosition = false
            completion?()
        }
    }
    
    /// Clears any saved scroll position
    func clearSavedScrollPosition() {
        UserDefaults.standard.removeObject(forKey: scrollPositionKey)
        scrollPosition = .zero
    }
    
    /// Handles SwiftUI scene phase changes
    /// - Parameters:
    ///   - oldPhase: Previous scene phase
    ///   - newPhase: New scene phase
    func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        print("⏱️ Scene phase transition: \(oldPhase) -> \(newPhase)")
        
        // Only operate on scene phase changes in certain directions
        if oldPhase == .active && (newPhase == .inactive || newPhase == .background) {
            // This is a transition from active to background/inactive
            saveScrollPosition()
        } 
        else if newPhase == .inactive && oldPhase == .background {
            // Skip the background -> inactive transition, as it often gives invalid scroll positions
            print("📱 Skipping scroll position check during background -> inactive transition")
        }
        
        // Check for transition to active state (from any state)
        if newPhase == .active && (oldPhase == .inactive || oldPhase == .background) {
            // Set flag to indicate restoration is in progress
            isRestoringScrollPosition = true
            
            // Reset text input height to default when coming back from background
            resetInputViewHeight()
            
            // Schedule restoration with a brief delay to allow views to be ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.restoreScrollPosition()
            }
        }
    }
}