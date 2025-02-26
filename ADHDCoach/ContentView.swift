import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var chatManager: ChatManager
    @EnvironmentObject private var eventKitManager: EventKitManager
    @EnvironmentObject private var memoryManager: MemoryManager
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool
    @State private var showingSettings = false
    @State private var scrollViewHeight: CGFloat = 0
    
    // Add observer for chat history deletion
    init() {
        // This is needed because @EnvironmentObject isn't available in init
    }
    
    // Helper function to reset chat when notification is received
    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ChatHistoryDeleted"),
            object: nil,
            queue: .main
        ) { [self] _ in
            // This will be called when chat history is deleted
            chatManager.messages = []
            
            // Instead of static welcome message, try to do a preemptive query
            Task {
                // Try preemptive query after chat history deletion
                await chatManager.checkAndPreemptivelyQueryAPIAfterHistoryDeletion()
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
            .navigationTitle("Cosmic Coach")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "gear")
                            .font(.system(size: 22))
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .onAppear {
                // Connect the memory manager to the chat manager
                chatManager.setMemoryManager(memoryManager)
                print("Connected memory manager to chat manager")
                
                // Setup notification observer for chat history deletion
                setupNotificationObserver()
                
                // Ensure memory is properly loaded
                Task {
                    await memoryManager.loadMemory()
                    if let fileURL = memoryManager.getMemoryFileURL() {
                        print("Memory file on app launch: \(FileManager.default.fileExists(atPath: fileURL.path))")
                        print("Memory content length: \(memoryManager.memoryContent.count)")
                    }
                    
                    // Check and potentially make a preemptive query to Claude
                    await chatManager.checkAndPreemptivelyQueryAPI()
                }
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
