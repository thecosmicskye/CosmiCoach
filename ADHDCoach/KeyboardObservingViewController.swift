import SwiftUI
import UIKit

// Note: KeyboardManager is imported directly from the project, not as a module

// MARK: - KeyboardObservingViewController
public class KeyboardObservingViewController: UIViewController {
    // MARK: Views
    private var keyboardTrackingView = UIView()
    private var safeAreaView = UIView()
    private var inputHostView: UIHostingController<TextInputView>!
    
    // MARK: Constants
    private let keyboardVisibilityThreshold: CGFloat = 100
    
    // MARK: Properties
    internal var keyboardManager: KeyboardManager // For accessing keyboard properties
    private var bottomConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    private var _lastInputViewHeight: CGFloat = 0
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
        keyboardManager: KeyboardManager,
        text: Binding<String>,
        onSend: @escaping () -> Void,
        colorScheme: ColorScheme,
        themeColor: Color,
        isDisabled: Bool,
        debugOutlineMode: DebugOutlineMode
    ) {
        self.keyboardManager = keyboardManager
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
    public override func viewDidLoad() {
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
        
        // Create height constraint that we can update later - use keyboard manager's default height
        heightConstraint = inputHostView.view.heightAnchor.constraint(equalToConstant: keyboardManager.defaultInputHeight)
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
        keyboardManager.setKeyboardVisible(isVisible, height: keyboardFrame.height)
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
        keyboardManager.setKeyboardVisible(false, height: 0)
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
        if text.wrappedValue.isEmpty || height == keyboardManager.defaultInputHeight {
            print("📝 Text is empty or height is default, forcing reset to defaults")
            
            // Force another update after a slight delay to ensure it takes effect
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.heightConstraint?.constant = self.keyboardManager.defaultInputHeight
                
                UIView.animate(withDuration: 0.2) {
                    self.view.layoutIfNeeded()
                }
            }
        }
    }
    
    // MARK: Interactive Gesture Handling
    public override func viewWillLayoutSubviews() {
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
        let heightDifference = abs(keyboardManager.keyboardOffset - (isVisible ? keyboardHeight : 0))
        let shouldUpdate = heightDifference > 1.0 || keyboardManager.isKeyboardVisible != isVisible
        
        if shouldUpdate {
            // Update state without animation during interactive gesture
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            keyboardManager.setKeyboardVisible(isVisible, height: isVisible ? keyboardHeight : 0)
            CATransaction.commit()
            
            // Update layout immediately
            view.layoutIfNeeded()
            updateSwiftUIViewPosition()
        }
    }
}
