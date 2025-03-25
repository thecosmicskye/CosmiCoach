import SwiftUI
import Combine
import UIKit
import Speech
import AVFoundation

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
    @State private var isDictating = false
    @State private var textEditorHeight: CGFloat = 0 // Will be set to minHeight in onAppear
    
    // Speech Recognition
    @State private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: Locale.current.language.languageCode?.identifier ?? "en-US"))
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var audioEngine = AVAudioEngine()
    @State private var recognizedText = ""
    @State private var textBeforeDictation = ""
    
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
                // When not dictating, show simple layout with mic button
                if !isDictating {
                    Spacer()
                    
                    // Dictation button
                    Button {
                        // Store current text before starting dictation
                        textBeforeDictation = text
                        
                        // Request permission first
                        requestSpeechRecognitionPermission { isAuthorized in
                            if isAuthorized {
                                // Start speech recognition if authorized
                                self.startSpeechRecognition()
                            } else {
                                // Could display an alert here in a real app
                                print("Speech recognition not authorized")
                            }
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .foregroundColor(themeColor)
                                .frame(width: 34, height: 34)
                            Image(systemName: "mic")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.bottom, 4)
                    .padding(.horizontal, 2)
                    
                    // Send button - only shown when text is valid
                    if !isButtonDisabled {
                        Button {
                            guard !isSending else { return }
                            isSending = true
                            
                            // Store text to be sent before any potential clearing
                            let currentText = text
                            
                            // Immediately clear text field to prevent any race conditions
                            DispatchQueue.main.async {
                                self.text = ""
                            }
                            
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
                            
                            // Call send function
                            onSend()
                            
                            // Force clear text again after a short delay to ensure it's cleared
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                self.text = ""
                            }
                            
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
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.bottom, 4)
                        .padding(.horizontal, 2)
                        .transition(.opacity)
                    }
                }
                // When dictating, show stop-waveform-send layout
                else {
                    // Stop button on left
                    Button {
                        // Just stop recording without deleting text
                        stopDictationWithoutClearing()
                    } label: {
                        ZStack {
                            Circle()
                                .foregroundColor(Color(.systemBackground))
                                .frame(width: 34, height: 34)
                                .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                    }
                    .padding(.bottom, 4)
                    .padding(.horizontal, 2)
                    
                    Spacer()
                    
                    // Simple audio waveform with 4 bars
                    HStack(spacing: 3) {
                        ForEach(0..<4) { index in
                            AudioWaveBar(
                                animationDelay: Double(3 - index) * 0.2, // Reversed index for right-to-left wave
                                themeColor: .white
                            )
                        }
                    }
                    .frame(height: 20)
                    
                    Spacer()
                    
                    // Send button on right - always shown when recording but may be disabled
                    let textIsValid = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    
                    Button {
                        guard !isSending && textIsValid else { return }
                        isSending = true
                        
                        // Store text to be sent
                        let currentText = text
                        
                        // Immediately clear text field to prevent any race conditions
                        // This is important because stopSpeechRecognition might interfere
                        DispatchQueue.main.async {
                            self.text = ""
                        }
                        
                        // When sending dictated text, we want to clear the text
                        // so use the regular stop method that cooperates with sending
                        stopSpeechRecognition()
                        
                        // Reset text editor height
                        textEditorHeight = minHeight
                        
                        // Calculate total input view height
                        let buttonRowHeight: CGFloat = 54
                        let totalHeight = minHeight + 16 + buttonRowHeight
                        
                        // Notify parent about height change
                        NotificationCenter.default.post(
                            name: NSNotification.Name("InputViewHeightChanged"),
                            object: nil,
                            userInfo: ["height": totalHeight]
                        )
                        
                        // Call send function with the stored text
                        onSend()
                        
                        // Force clear text again after a short delay to ensure it's cleared
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            self.text = ""
                            self.textBeforeDictation = ""
                            self.recognizedText = ""
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isSending = false
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .foregroundColor(textIsValid ? themeColor : Color.gray)
                                .frame(width: 34, height: 34)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.bottom, 4)
                    .padding(.horizontal, 2)
                    .disabled(!textIsValid)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isDictating)
            .animation(.easeInOut(duration: 0.2), value: isButtonDisabled)
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
        .onDisappear {
            // Clean up speech recognition when view disappears
            if isDictating {
                stopSpeechRecognition()
            }
        }
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
    
    // Start our own speech recognition session
    private func startSpeechRecognition() {
        // Set dictating state
        isDictating = true
        
        // Cancel any existing recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Configure the audio session for the app
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session setup failed: \(error.localizedDescription)")
            isDictating = false
            return
        }
        
        // Create and configure the speech recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        // Get audio input node (it's not optional in newer iOS versions)
        let inputNode = audioEngine.inputNode
        
        guard let recognitionRequest = recognitionRequest else {
            print("Unable to create recognition request")
            isDictating = false
            return
        }
        
        // Configure request
        recognitionRequest.shouldReportPartialResults = true
        
        // Initialize recognized text
        recognizedText = ""
        
        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            var isFinal = false
            
            if let result = result {
                // Get recognized text
                self.recognizedText = result.bestTranscription.formattedString
                
                // Only update text if we're still dictating (check before updating text)
                // This prevents race conditions with the X button
                if self.isDictating {
                    // Update text field with the stored text plus newly recognized text
                    self.text = self.textBeforeDictation + self.recognizedText
                }
                
                isFinal = result.isFinal
            }
            
            // Handle errors or completion, but be careful about text updates
            if error != nil || isFinal {
                // Save current text state before any changes
                let currentText = self.text
                
                // Clean up audio resources
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                
                // Clear resources but don't modify text
                self.recognitionRequest = nil
                self.recognitionTask = nil
                
                // If this is final but not from manual cancellation, keep the text
                // This is the path when speech recognition naturally completes
                if isFinal && self.isDictating {
                    // Ensure text is preserved
                    DispatchQueue.main.async {
                        if self.text != currentText {
                            self.text = currentText
                        }
                    }
                }
                
                // Now update dictating state
                self.isDictating = false
            }
        }
        
        // Configure the microphone input
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        // Start the audio engine
        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            print("Audio engine couldn't start: \(error.localizedDescription)")
            isDictating = false
        }
    }
    
    // Stop dictation and preserve the current text
    private func stopDictationWithoutClearing() {
        // IMPORTANT: Save the current text before any operations
        let textToPreserve = self.text
        print("🎤 X button tapped - saving text: \(textToPreserve)")
        
        // Stop all dictation services in a way that won't trigger text changes
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        
        // Reset audio session
        try? AVAudioSession.sharedInstance().setActive(false)
        
        // CRITICAL: ensure our text stays preserved 
        // Run multiple async updates with increasing delays for reliability
        DispatchQueue.main.async {
            if self.text != textToPreserve {
                print("🎤 Immediate text recovery needed")
                self.text = textToPreserve
            }
        }
        
        // Secondary safeguard with delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if self.text != textToPreserve {
                print("🎤 Delayed text recovery needed")
                self.text = textToPreserve
            }
        }
        
        // Final safeguard with longer delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if self.text != textToPreserve {
                print("🎤 Final text recovery needed")
                self.text = textToPreserve
            }
            
            // Log final state
            print("🎤 Final text after stopping dictation: \(self.text)")
        }
        
        // Update state to indicate we're no longer dictating
        isDictating = false
    }
    
    // Stop speech recognition
    private func stopSpeechRecognition() {
        // Save the current text content before stopping, if needed
        let finalText = text
        let wasSendingMessage = isSending
        
        // Stop audio processing
        audioEngine.stop()
        
        // End audio and cancel task - this might trigger callbacks
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        // Clean up request and task
        recognitionRequest = nil
        recognitionTask = nil
        
        // Reset audio session
        try? AVAudioSession.sharedInstance().setActive(false)
        
        // Only preserve text if we're not in the middle of sending
        // This prevents conflicts when sending is clearing the text
        if !wasSendingMessage {
            DispatchQueue.main.async {
                // Only update if necessary and not sending
                if self.text != finalText && !self.isSending {
                    self.text = finalText
                }
            }
        }
        
        // Update state to indicate we're no longer dictating
        isDictating = false
        
        // Print debug info
        print("Dictation stopped, wasSending: \(wasSendingMessage), final text: \(finalText)")
    }
    
    // MARK: - Speech Recognition Permission
    private func requestSpeechRecognitionPermission(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                let isAuthorized = authStatus == .authorized
                completion(isAuthorized)
            }
        }
    }
}

// MARK: - UIResponder Extension to get first responder and access dictation
extension UIResponder {
    private static weak var _currentFirstResponder: UIResponder?
    
    static var currentFirstResponder: UIResponder? {
        _currentFirstResponder = nil
        UIApplication.shared.sendAction(#selector(UIResponder.findFirstResponder(_:)), to: nil, from: nil, for: nil)
        return _currentFirstResponder
    }
    
    @objc private func findFirstResponder(_ sender: Any) {
        UIResponder._currentFirstResponder = self
    }
}

// MARK: - UIView Extension for traversing view hierarchy
extension UIView {
    func findView<T: UIView>(ofType type: T.Type) -> T? {
        if let view = self as? T {
            return view
        }
        
        for subview in subviews {
            if let found = subview.findView(ofType: type) {
                return found
            }
        }
        
        return nil
    }
    
    func findView(withAccessibilityIdentifier identifier: String) -> UIView? {
        if self.accessibilityIdentifier == identifier {
            return self
        }
        
        for subview in subviews {
            if let found = subview.findView(withAccessibilityIdentifier: identifier) {
                return found
            }
        }
        
        return nil
    }
    
    func simulate(event: UIControl.Event) {
        if let control = self as? UIControl {
            control.sendActions(for: event)
        }
    }
}

// MARK: - Audio Waveform Animation
private struct AudioWaveBar: View {
    // States
    @State private var isAnimating = false
    
    // Props
    var animationDelay: Double = 0.0
    var themeColor: Color = .red
    
    // Constants
    private let minHeight: CGFloat = 5
    private let maxHeight: CGFloat = 16
    
    var body: some View {
        Capsule()
            .fill(themeColor)
            .frame(width: 2.5, height: isAnimating ? maxHeight : minHeight)
            // Very simple animation
            .animation(
                Animation.easeInOut(duration: 0.6)
                    .repeatForever(autoreverses: true)
                    .delay(animationDelay),
                value: isAnimating
            )
            .onAppear {
                // Start animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isAnimating = true
                }
            }
    }
}