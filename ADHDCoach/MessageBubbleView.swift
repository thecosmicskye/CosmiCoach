import SwiftUI
import AVFoundation

struct TypingDotsView: View {
    @State private var firstDotOffset: CGFloat = 0
    @State private var secondDotOffset: CGFloat = 0
    @State private var thirdDotOffset: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme
    
    let dotSize: CGFloat = 8
    let animationDuration: Double = 0.6
    
    var dotColor: Color {
        colorScheme == .dark ? .white : .gray
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(dotColor)
                .frame(width: dotSize, height: dotSize)
                .offset(y: firstDotOffset)
            
            Circle()
                .fill(dotColor)
                .frame(width: dotSize, height: dotSize)
                .offset(y: secondDotOffset)
            
            Circle()
                .fill(dotColor)
                .frame(width: dotSize, height: dotSize)
                .offset(y: thirdDotOffset)
        }
        .padding(.bottom, 8)
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        let baseAnimation = Animation.easeInOut(duration: animationDuration).repeatForever(autoreverses: true)
        
        withAnimation(baseAnimation) {
            firstDotOffset = -5
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(baseAnimation) {
                secondDotOffset = -5
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(baseAnimation) {
                thirdDotOffset = -5
            }
        }
    }
}

struct MessageBubbleView: View {
    let message: ChatMessage
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var chatManager: ChatManager
    @EnvironmentObject private var speechManager: SpeechManager
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                // Use regular Text for user messages, MarkdownText for Claude messages
                if message.isUser {
                    Text(message.content)
                        .font(.body)
                        .lineSpacing(1.2)
                        .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                        .background(themeManager.accentColor(for: colorScheme))
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .textSelection(.enabled)  // Enable text selection for copying
                        .contextMenu {
                            Button(action: {
                                UIPasteboard.general.string = message.content
                            }) {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            
                            Button(action: {
                                speechManager.speak(text: message.content)
                            }) {
                                Label("Speak", systemImage: "speaker.wave.2.fill")
                            }
                        }
                } else {
                    // Claude message with markdown support
                    if !message.isComplete && message.content.isEmpty {
                        // Empty Claude message - show typing indicator dots
                        HStack {
                            TypingDotsView()
                                .padding(.horizontal, 4)
                        }
                    } else {
                        Group {
                            // Our custom renderer handles both markdown and line breaks
                            MarkdownTextView(
                                markdown: message.content,
                                isComplete: message.isComplete
                            )
                            .lineSpacing(1.2) // Increase line spacing to improve readability and line break visibility
                            .padding(EdgeInsets(top: 12, leading: 2, bottom: 12, trailing: 2))
                            .background(Color.clear)
                            .cornerRadius(16)
                            .textSelection(.enabled)
                            // Ensure view updates when content changes or completes
                            .id(message.isComplete ? "complete-\(message.id)" : "streaming-\(message.id)-\(message.content.count)")
                            // Ensure stable layout after completion
                            .fixedSize(horizontal: false, vertical: true)
                            // Wait for changes to complete before finalizing layout
                            .transaction { transaction in
                                if !message.isComplete {
                                    transaction.animation = nil
                                }
                            }
                            .onAppear {
                                // Safety check: if message is complete but chatManager still shows processing
                                if message.isComplete && chatManager.isProcessing {
                                    print("⚠️ Found complete message while ChatManager still processing - resetting state")
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        chatManager.isProcessing = false
                                    }
                                }
                            }
                        }
                        .contextMenu {
                            Button(action: {
                                UIPasteboard.general.string = message.content
                            }) {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            
                            Button(action: {
                                speechManager.speak(text: message.content)
                            }) {
                                Label("Speak", systemImage: "speaker.wave.2.fill")
                            }
                        }
                        
                        // Show loader while content is streaming
                        if (!message.isComplete) {
                            HStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                }
            }
            
            if !message.isUser {
                Spacer()
            }
        }
    }
}

#Preview {
    VStack {
        MessageBubbleView(message: ChatMessage(content: "Hello, how can I help you today?\n\n**Bold text** and *italic text*\n\n- List item 1\n- List item 2", isUser: false))
        MessageBubbleView(message: ChatMessage(content: "I'm feeling overwhelmed with my tasks", isUser: true))
        MessageBubbleView(message: ChatMessage(content: "", isUser: false, isComplete: false))
    }
    .padding()
    .environmentObject(ThemeManager())
    .environmentObject(ChatManager())
    .environmentObject(SpeechManager())
}