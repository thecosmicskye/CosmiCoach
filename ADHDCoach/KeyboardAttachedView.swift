import SwiftUI
import UIKit

// Note: KeyboardManager is imported directly from the project, not as a module

// MARK: - KeyboardAttachedView
public struct KeyboardAttachedView: UIViewControllerRepresentable {
    // MARK: Properties
    var keyboardManager: KeyboardManager
    @Binding var text: String
    var onSend: () -> Void
    var colorScheme: ColorScheme
    var themeColor: Color
    var isDisabled: Bool
    var debugOutlineMode: DebugOutlineMode
    
    // MARK: UIViewControllerRepresentable
    public func makeUIViewController(context: Context) -> KeyboardObservingViewController {
        print("KeyboardAttachedView.makeUIViewController")
        return KeyboardObservingViewController(
            keyboardManager: keyboardManager,
            text: $text,
            onSend: onSend,
            colorScheme: colorScheme,
            themeColor: themeColor,
            isDisabled: isDisabled,
            debugOutlineMode: debugOutlineMode
        )
    }
    
    public func updateUIViewController(_ uiViewController: KeyboardObservingViewController, context: Context) {
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
