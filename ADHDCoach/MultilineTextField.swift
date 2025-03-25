import SwiftUI
import UIKit

// Flag to enable/disable input view layout debugging logs
public var inputViewLayoutDebug = false

// MARK: - MultilineTextField
public struct MultilineTextField: UIViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    
    public func makeUIView(context: Context) -> UITextView {
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
        
        // Set an accessibility identifier for debugging
        textView.accessibilityIdentifier = "multilineTextField"
        
        // Register for dictation text update notifications
        NotificationCenter.default.addObserver(
            forName: Notification.Name("DictationTextUpdated"),
            object: nil,
            queue: .main) { [weak textView] _ in
                // When dictation updates text, ensure we're scrolled to the bottom
                DispatchQueue.main.async {
                    // Scroll to the end of the text
                    if let tv = textView {
                        let range = NSRange(location: tv.text.count, length: 0)
                        tv.scrollRangeToVisible(range)
                    }
                }
            }
        
        return textView
    }
    
    public func updateUIView(_ uiView: UITextView, context: Context) {
        // Only update if text changed externally
        if uiView.text != text {
            let wasEmpty = uiView.text.isEmpty
            let willBeEmpty = text.isEmpty
            let wasShorter = uiView.text.count < text.count
            
            // Save current selection to restore after update if needed
            let selectedRange = uiView.selectedRange
            
            // Update text view content
            uiView.text = text
            
            // Scroll to bottom if text got longer (like during dictation)
            if wasShorter && !willBeEmpty {
                // Make sure we're at the end when dictating
                DispatchQueue.main.async {
                    // Scroll to end
                    let newPosition = uiView.endOfDocument
                    uiView.scrollRangeToVisible(NSRange(location: uiView.text.count, length: 0))
                    
                    // Also set cursor to end if editing
                    if uiView.isFirstResponder {
                        uiView.selectedRange = NSRange(location: uiView.text.count, length: 0)
                    }
                }
            } else {
                // For other cases, try to maintain selection
                uiView.selectedRange = selectedRange
            }
            
            // When text is cleared or changed to/from empty, notify about height change
            // This ensures proper height updates for all text state transitions
            if wasEmpty != willBeEmpty || willBeEmpty {
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
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public class Coordinator: NSObject, UITextViewDelegate {
        var parent: MultilineTextField
        
        init(_ parent: MultilineTextField) {
            self.parent = parent
        }
        
        public func textViewDidChange(_ textView: UITextView) {
            // Update the binding
            parent.text = textView.text
            
            // Scroll to visible caret position for a better typing experience
            let selectedRange = textView.selectedRange
            if let selectedTextRange = textView.selectedTextRange {
                // Get the end of the selection
                let selectionEndRect = textView.caretRect(for: selectedTextRange.end)
                
                // Scroll to make the caret visible with some extra padding
                let visibleRect = CGRect(
                    x: selectionEndRect.origin.x,
                    y: selectionEndRect.origin.y,
                    width: selectionEndRect.width,
                    height: selectionEndRect.height + 20 // Add some bottom padding
                )
                textView.scrollRectToVisible(visibleRect, animated: false)
            }
        }
        
        public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Check for special key combinations
            let currentText = textView.text ?? ""
            
            // Current selection
            let selectedRange = textView.selectedRange
            
            // Handle key combinations
            if text == "\n" {
                // Check if shift or command key is pressed
                let modifierFlags = UIApplication.shared.windows.first?.windowScene?.keyWindow?.eventModifierFlags
                
                if modifierFlags?.contains(.shift) == true {
                    // Shift+Return: submit message
                    parent.onSubmit()
                    return false
                } else if modifierFlags?.contains(.command) == true {
                    // Command+Return: submit message
                    parent.onSubmit()
                    return false
                } else {
                    // Normal Return: insert line break (default behavior)
                    return true
                }
            }
            
            return true
        }
        
        // When the text view is updated, make sure we're scrolled to the visible selection
        public func textViewDidChangeSelection(_ textView: UITextView) {
            // If we're at the end, ensure it's visible
            if textView.selectedRange.location == textView.text.count {
                textView.scrollRangeToVisible(NSRange(location: textView.text.count, length: 0))
            }
        }
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