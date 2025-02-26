import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var chatManager: ChatManager
    @EnvironmentObject private var eventKitManager: EventKitManager
    @EnvironmentObject private var memoryManager: MemoryManager
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool
    @State private var showingSettings = false
    @State private var isTestingKey = false
    @State private var testResult: String? = nil
    @State private var scrollViewHeight: CGFloat = 0
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Test result banner
                if let result = testResult {
                    HStack {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(result.hasPrefix("✅") ? .green : .red)
                            .padding(8)
                        
                        Spacer()
                        
                        Button(action: {
                            testResult = nil
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
                
                // Chat messages list
                GeometryReader { geometry in
                    ScrollViewReader { proxy in
                        ScrollView {
                            // This spacer pushes content to the bottom when there are few messages
                            if chatManager.messages.count < 5 {
                                Spacer(minLength: scrollViewHeight - 100)
                                    .frame(height: scrollViewHeight)
                            }
                            
                            LazyVStack(spacing: 12) {
                                ForEach(chatManager.messages) { message in
                                    MessageBubbleView(message: message)
                                        .padding(.horizontal)
                                }
                                
                                // Invisible spacer view at the end for scrolling
                                Color.clear
                                    .frame(height: 1)
                                    .id("bottomID")
                            }
                            .padding(.vertical, 8)
                        }
                        .onAppear {
                            // Save the scroll view height
                            scrollViewHeight = geometry.size.height
                            
                            // Scroll to bottom without animation when view appears
                            DispatchQueue.main.async {
                                proxy.scrollTo("bottomID", anchor: .bottom)
                            }
                        }
                        .onChange(of: chatManager.messages.count) { oldValue, newValue in
                            // Scroll to bottom with animation when messages change
                            withAnimation {
                                proxy.scrollTo("bottomID", anchor: .bottom)
                            }
                        }
                        // Also scroll when streaming updates occur
                        .onChange(of: chatManager.streamingUpdateCount) { oldValue, newValue in
                            // Scroll to bottom with animation during streaming
                            withAnimation {
                                proxy.scrollTo("bottomID", anchor: .bottom)
                            }
                        }
                    }
                }
                
                // Input area
                HStack {
                    TextField("Message", text: $messageText)
                        .padding(10)
                        .background(Color(.systemGray6))
                        .cornerRadius(20)
                        .focused($isInputFocused)
                    
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.blue)
                    }
                    .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chatManager.isProcessing)
                }
                .padding()
            }
            .navigationTitle("ADHD Coach")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button(action: {
                            Task {
                                isTestingKey = true
                                testResult = nil
                                testResult = await chatManager.testApiKey()
                                isTestingKey = false
                            }
                        }) {
                            if isTestingKey {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            } else {
                                Image(systemName: "key")
                                    .font(.system(size: 22))
                            }
                        }
                        
                        Button(action: {
                            showingSettings = true
                        }) {
                            Image(systemName: "gear")
                                .font(.system(size: 22))
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .onAppear {
                // Connect the memory manager to the chat manager
                chatManager.setMemoryManager(memoryManager)
            }
        }
    }
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        messageText = ""
        
        // Add user message to chat
        chatManager.addUserMessage(content: trimmedMessage)
        
        // Send to Claude API
        Task {
            // Get context from EventKit
            let calendarEvents = eventKitManager.fetchUpcomingEvents(days: 7)
            let reminders = await eventKitManager.fetchReminders()
            
            await chatManager.sendMessageToClaude(
                userMessage: trimmedMessage,
                calendarEvents: calendarEvents,
                reminders: reminders
            )
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ChatManager())
        .environmentObject(EventKitManager())
        .environmentObject(MemoryManager())
}
