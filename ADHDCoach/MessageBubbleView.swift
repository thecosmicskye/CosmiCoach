import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeManager: ThemeManager
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    .background(message.isUser ? themeManager.accentColor(for: colorScheme) : Color(.systemGray5))
                    .foregroundColor(message.isUser ? 
                        (colorScheme == .dark ? .white : .black) : .primary)
                    .cornerRadius(16)
                    .textSelection(.enabled)  // Enable text selection for copying
                    .contextMenu {
                        Button(action: {
                            UIPasteboard.general.string = message.content
                        }) {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                
                HStack {
                    Text(message.formattedTimestamp)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if !message.isComplete && !message.isUser {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                            .scaleEffect(0.7)
                    }
                }
                .padding(.horizontal, 4)
            }
            
            if !message.isUser {
                Spacer()
            }
        }
    }
}

#Preview {
    VStack {
        MessageBubbleView(message: ChatMessage(content: "Hello, how can I help you today?", isUser: false))
        MessageBubbleView(message: ChatMessage(content: "I'm feeling overwhelmed with my tasks", isUser: true))
    }
    .padding()
    .environmentObject(ThemeManager())
}
