import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var chatManager: ChatManager
    
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
                        }
                } else {
                    // Claude message with markdown support
                    if !message.isComplete && message.content.isEmpty {
                        // Empty Claude message - show only loader
                        HStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                                .padding(4)
                        }
                    } else {
                        Group {
                            // Our custom renderer handles both markdown and line breaks
                            MarkdownTextView(
                                markdown: message.content,
                                isComplete: message.isComplete
                            )
                            .lineSpacing(1.2) // Increase line spacing to improve readability and line break visibility
                            .padding(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
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
    }
    .padding()
    .environmentObject(ThemeManager())
}
