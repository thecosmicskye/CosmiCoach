import SwiftUI
import Combine
import UIKit

public struct TextInputView: View {
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
    @State private var textEditorHeight: CGFloat = 0 // Will be set to minHeight in onAppear
    
    // Constants 
    private var defaultFont: UIFont { UIFont.systemFont(ofSize: UIFont.systemFontSize * 1.25) }
    private var defaultFontSize: CGFloat { defaultFont.pointSize }
    private var lineHeight: CGFloat { defaultFont.lineHeight }
    private let maxLines: Int = 4
    private var minHeight: CGFloat { lineHeight + 16 } // Single line + padding
    
    // Computed properties
    private var isButtonDisabled: Bool {
        isDisabled || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending
    }
    
    private var buttonColor: Color {
        isButtonDisabled ? .gray : themeColor
    }
    
    // Calculate max height based on max lines
    private var maxHeight: CGFloat {
        let padding: CGFloat = 16 // vertical padding
        return (CGFloat(maxLines) * lineHeight) + padding
    }
    
    // MARK: Body
    public var body: some View {
        VStack(spacing: 8) {
            // Text input field - using a multi-line editor, now full width
            ZStack(alignment: .leading) {
                // Placeholder text that shows when the text editor is empty
                if text.isEmpty {
                    Text("Message CosmiCoach")
                        .foregroundColor(Color(.placeholderText))
                        .padding(.horizontal, 6)
                        .font(.system(size: defaultFontSize))
                }
                
                // Actual text editor
                MultilineTextField(text: $text, onSubmit: {
                    // Submit on shift+return or command+return
                    if !text.isEmpty {
                        onSend()
                    }
                })
                .frame(height: min(textEditorHeight, maxHeight))
                .onAppear {
                    // Initialize height with calculated minHeight
                    textEditorHeight = minHeight
                }
                .onChange(of: text) { _, newText in
                    // Calculate height based on text content
                    let size = getTextSize(for: newText)
                    let newHeight = min(max(size.height + 16, minHeight), maxHeight)
                    
                    // Only update if height actually changed
                    if newHeight != textEditorHeight {
                        textEditorHeight = newHeight
                        
                        // Calculate total height including padding, container, and button row
                        let buttonRowHeight: CGFloat = 54 // Match the height in KeyboardState
                        let totalHeight = newHeight + 16 + buttonRowHeight // Add padding for container + button row
                        
                        // Logging for debugging
                        if inputViewLayoutDebug {
                            print("Text height changed: \(textEditorHeight) → total: \(totalHeight)")
                        }
                        
                        // Notify parent view controller of height change
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("InputViewHeightChanged"),
                                object: nil,
                                userInfo: ["height": totalHeight]
                            )
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .border(debugOutlineMode == .textInput ? Color.pink : Color.clear, width: debugOutlineMode == .textInput ? 1 : 0)
            .animation(nil, value: text) // Prevent animation during transitions
            
            // Send button row
            HStack {
                Spacer()
                
                Button {
                    guard !isSending else { return }
                    isSending = true
                    
                    // Reset text editor height before sending
                    textEditorHeight = minHeight
                    
                    // Explicitly notify about height change to default
                    if inputViewLayoutDebug {
                        print("Resetting text height to default: \(minHeight)")
                    }
                    
                    // Calculate total input view height (text + container padding + button row)
                    let buttonRowHeight: CGFloat = 54 // Match the height in KeyboardState
                    let totalHeight = minHeight + 16 + buttonRowHeight // Add padding for container + button row
                    
                    // Notify parent about height change
                    NotificationCenter.default.post(
                        name: NSNotification.Name("InputViewHeightChanged"),
                        object: nil,
                        userInfo: ["height": totalHeight]
                    )
                    
                    // Call send after height is reset
                    onSend()
                    
                    // Reset button state after a brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isSending = false
                    }
                } label: {
                    ZStack {
                        Circle()
                            .foregroundColor(buttonColor)
                            .frame(width: 34, height: 34)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(isButtonDisabled ? Color(.systemBackground) : .white)
                    }
                }
                .padding(.bottom, 4)
                .padding(.horizontal, 2)
                .disabled(isButtonDisabled)
                .animation(.easeInOut(duration: 0.1), value: isButtonDisabled)
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .border(debugOutlineMode == .textInput ? Color.mint : Color.clear, width: 2)
        .transaction { transaction in
            transaction.animation = nil // Prevent position animations
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(25, corners: [.topLeft, .topRight])
    }
    
    // Helper to calculate text size
    private func getTextSize(for text: String) -> CGSize {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: defaultFont
        ]
        
        let width = UIScreen.main.bounds.width - 70 // Wider width since button is now in a separate row
        let constraintRect = CGSize(width: width, height: .greatestFiniteMagnitude)
        let boundingBox = text.boundingRect(
            with: constraintRect,
            options: .usesLineFragmentOrigin,
            attributes: attributes,
            context: nil
        )
        
        return boundingBox.size
    }
}