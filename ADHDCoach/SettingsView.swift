import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var memoryManager: MemoryManager
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var chatManager: ChatManager
    @State private var apiKey = ""
    @AppStorage("check_basics_daily") private var checkBasicsDaily = true
    @AppStorage("token_limit") private var tokenLimit = 75000
    @AppStorage("enable_automatic_responses") private var enableAutomaticResponses = false
    @AppStorage("enable_location_awareness") private var enableLocationAwareness = false
    @State private var isTestingKey = false
    @State private var testResult: String? = nil
    @State private var showingMemoryViewer = false
    @State private var showingResetConfirmation = false
    @State private var showingDeleteChatConfirmation = false
    
    init() {
        _apiKey = State(initialValue: UserDefaults.standard.string(forKey: "claude_api_key") ?? "")
    }
    
    func testApiKey() async {
        isTestingKey = true
        testResult = nil
        
        // Save the key to UserDefaults first
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmedKey, forKey: "claude_api_key")
        UserDefaults.standard.synchronize()
        
        // Get the key from UserDefaults to ensure we're using the same key as the ChatManager
        let savedKey = UserDefaults.standard.string(forKey: "claude_api_key") ?? ""
        
        // Create a simple request to test the API key
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue(savedKey, forHTTPHeaderField: "x-api-key")
        
        // Simple request body - including tools to test if they're supported
        let requestBody: [String: Any] = [
            "model": "claude-3-7-sonnet-20250219",
            "max_tokens": 10,
            "stream": false,
            "tools": [
                [
                    "name": "test_tool",
                    "description": "A test tool",
                    "input_schema": [
                        "type": "object",
                        "properties": [
                            "test": ["type": "string"]
                        ]
                    ]
                ]
            ],
            "messages": [
                ["role": "user", "content": [
                    ["type": "text", "text": "Hello"]
                ]]
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            print("💡 Sending test API request with tools")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("💡 API Test Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    // Try to decode the response to check for tool errors
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("💡 API Test Response: \(responseString)")
                        
                        // Check if there's any indication of tool errors
                        if responseString.contains("tool") {
                            testResult = "✅ API key is valid with tools support!"
                        } else {
                            testResult = "✅ API key is valid, but tools support is unclear"
                        }
                    } else {
                        testResult = "✅ API key is valid!"
                    }
                } else {
                    // Try to extract error message
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("💡 API Test Error: \(responseString)")
                        
                        if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let error = errorJson["error"] as? [String: Any],
                           let message = error["message"] as? String {
                            testResult = "❌ Error: \(message)"
                            
                            // Check for specific errors related to tools
                            if message.contains("tool") {
                                testResult = "❌ Error with tools: \(message)"
                            }
                        } else {
                            testResult = "❌ Error: Status code \(httpResponse.statusCode)"
                        }
                    } else {
                        testResult = "❌ Error: Status code \(httpResponse.statusCode)"
                    }
                }
            }
        } catch {
            print("💡 API Test Exception: \(error)")
            testResult = "❌ Error: \(error.localizedDescription)"
        }
        
        isTestingKey = false
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("API Configuration")) {
                    SecureField("Claude API Key", text: $apiKey)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .onChange(of: apiKey) { oldValue, newValue in
                            // Trim whitespace before saving
                            let trimmedKey = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            UserDefaults.standard.set(trimmedKey, forKey: "claude_api_key")
                            print("API key saved to UserDefaults. Length: \(trimmedKey.count)")
                            
                            // Reset test result when key changes
                            testResult = nil
                        }
                    
                    Text("Enter your Claude API key (starts with 'sk-ant-')")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !apiKey.isEmpty && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("sk-ant") {
                        Text("Warning: This doesn't look like a Claude API key. Claude API keys start with 'sk-ant-'.")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    
                    Button(action: {
                        Task {
                            await testApiKey()
                        }
                    }) {
                        if isTestingKey {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                            Text("Testing API Key...")
                        } else {
                            Text("Test API Key")
                                .foregroundColor(themeManager.accentColor(for: colorScheme))
                        }
                    }
                    .disabled(apiKey.isEmpty || isTestingKey)
                    
                    if let result = testResult {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(result.hasPrefix("✅") ? .green : .red)
                    }
                    
                    Link("Get a Claude API Key", destination: URL(string: "https://console.anthropic.com/")!)
                        .font(.caption)
                        .foregroundColor(themeManager.accentColor(for: colorScheme))
                }
                
                Section(header: Text("Coaching Preferences")) {
                    Toggle("Daily Basics Check", isOn: $checkBasicsDaily)
                    
                    Stepper("Token Limit: \(tokenLimit)", value: $tokenLimit, in: 10000...100000, step: 5000)
                        .help("Controls how much conversation history is sent to Claude")
                }
                
                Section(header: Text("Memory Management")) {
                    Button("View Memory File") {
                        Task {
                            await memoryManager.loadMemory()
                            showingMemoryViewer = true
                        }
                    }
                    .foregroundColor(themeManager.accentColor(for: colorScheme))
                    .sheet(isPresented: $showingMemoryViewer) {
                        NavigationStack {
                            ScrollView {
                                Text(memoryManager.memoryContent)
                                    .padding()
                                    .textSelection(.enabled)
                            }
                            .navigationTitle("Memory File")
                            .applyThemeColor(themeManager: themeManager)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    Button("Done") {
                                        showingMemoryViewer = false
                                    }
                                    .foregroundColor(themeManager.accentColor(for: colorScheme))
                                }
                            }
                        }
                    }
                    
                    Button("Reset Memory") {
                        showingResetConfirmation = true
                    }
                    .foregroundColor(.red)
                    .confirmationDialog(
                        "Reset Memory",
                        isPresented: $showingResetConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Reset", role: .destructive) {
                            Task {
                                // Create a new memory file with default content
                                if let fileURL = memoryManager.getMemoryFileURL(),
                                   FileManager.default.fileExists(atPath: fileURL.path) {
                                    try? FileManager.default.removeItem(at: fileURL)
                                }
                                await memoryManager.loadMemory() // This will recreate with default content
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will delete all memory data. This action cannot be undone.")
                    }
                }
                
                Section(header: Text("Chat Management")) {
                    Button("Delete Chat History") {
                        showingDeleteChatConfirmation = true
                    }
                    .foregroundColor(.red)
                    .confirmationDialog(
                        "Delete Chat History",
                        isPresented: $showingDeleteChatConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive) {
                            // First log memory status before deletion
                            if let fileURL = memoryManager.getMemoryFileURL() {
                                print("Memory file exists before chat deletion: \(FileManager.default.fileExists(atPath: fileURL.path))")
                                print("Memory file path: \(fileURL.path)")
                            }
                            
                            // Clear chat messages from UserDefaults
                            UserDefaults.standard.removeObject(forKey: "chat_messages")
                            UserDefaults.standard.removeObject(forKey: "streaming_message_id")
                            UserDefaults.standard.removeObject(forKey: "last_streaming_content")
                            UserDefaults.standard.set(false, forKey: "chat_processing_state")
                            
                            // Post notification to refresh chat view
                            NotificationCenter.default.post(name: NSNotification.Name("ChatHistoryDeleted"), object: nil)
                            
                            // Verify memory file still exists after chat deletion
                            Task {
                                // Ensure memory is loaded after chat deletion
                                await memoryManager.loadMemory()
                                
                                if let fileURL = memoryManager.getMemoryFileURL() {
                                    print("Memory file exists after chat deletion: \(FileManager.default.fileExists(atPath: fileURL.path))")
                                    print("Memory content length after deletion: \(memoryManager.memoryContent.count)")
                                }
                                
                                // Show confirmation toast or alert
                                await MainActor.run {
                                    let generator = UINotificationFeedbackGenerator()
                                    generator.notificationOccurred(.success)
                                    
                                    testResult = "✅ Chat history deleted!"
                                    
                                    // Clear the success message after a delay
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                        if testResult == "✅ Chat history deleted!" {
                                            testResult = nil
                                        }
                                    }
                                }
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will delete all Chat message data. This action cannot be undone.")
                    }
                }
                
                Section(header: Text("Prompt Caching")) {
                    Text(chatManager.getCachePerformanceReport())
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                    
                    Button("Reset Cache Metrics") {
                        chatManager.resetCachePerformanceMetrics()
                        // Show a brief confirmation
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                        
                        testResult = "✅ Cache metrics reset!"
                        
                        // Clear the success message after a delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            if testResult == "✅ Cache metrics reset!" {
                                testResult = nil
                            }
                        }
                    }
                    .foregroundColor(themeManager.accentColor(for: colorScheme))
                    
                    Text("Prompt caching reduces token usage by reusing parts of previous prompts.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Appearance")) {
                    NavigationLink(destination: 
                        ThemeSelectionView(themeManager: themeManager)
                            .onAppear {
                                // Force update the theme when the view appears
                                themeManager.setTheme(themeManager.currentTheme)
                            }
                            .onChange(of: themeManager.currentTheme) { _, _ in
                                // Update the theme when it changes
                                themeManager.setTheme(themeManager.currentTheme)
                            }
                    ) {
                        HStack {
                            Text("Theme")
                            
                            Spacer()
                            
                            HStack {
                                Circle()
                                    .fill(colorScheme == .dark ? themeManager.currentTheme.darkModeAccentColor : themeManager.currentTheme.accentColor)
                                    .frame(width: 16, height: 16)
                                Text(themeManager.currentTheme.name)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Section(header: Text("Experimental Features")) {
                    Toggle("Automatic Messages", isOn: $enableAutomaticResponses)
                    
                    Text("Cosmic Coach will automatically send you a message when you open the app (only if you've been away for at least 5 minutes).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Toggle("Location Awareness", isOn: $enableLocationAwareness)
                        .onChange(of: enableLocationAwareness) { oldValue, newValue in
                            if newValue {
                                // When enabled, immediately request location access
                                print("📍 Location awareness toggled ON - requesting access")
                                locationManager.requestAccess()
                            } else {
                                print("📍 Location awareness toggled OFF - stopping updates")
                                locationManager.stopUpdatingLocation()
                            }
                        }
                    
                    Text("Cosmic Coach will use your location in its context window.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("About")) {
                    Text("Cosmic Coach v1.0")
                        .foregroundColor(.secondary)
                    
                    Text("This app uses Claude 3.7 to help manage your calendar, reminders, and provide ADHD coaching.")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(colorScheme)
            .applyThemeColor(themeManager: themeManager)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(themeManager.accentColor(for: colorScheme))
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(MemoryManager())
        .environmentObject(LocationManager())
        .environmentObject(ThemeManager())
        .environmentObject(ChatManager())
}
