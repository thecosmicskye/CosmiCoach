import SwiftUI
import UIKit
import AVFoundation

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var memoryManager: MemoryManager
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var chatManager: ChatManager
    @EnvironmentObject private var speechManager: SpeechManager
    @EnvironmentObject private var multipeerService: MultipeerService
    @AppStorage("claude_api_key") private var apiKey = ""
    @AppStorage("check_basics_daily") private var checkBasicsDaily = true
    @AppStorage("token_limit") private var tokenLimit = 75000
    @AppStorage("enable_automatic_responses") private var enableAutomaticResponses = false
    @AppStorage("enable_location_awareness") private var enableLocationAwareness = false
    @State private var isTestingKey = false
    @State private var testResult: String? = nil
    @State private var showingDeleteChatConfirmation = false
    @State private var showingResetConfirmation = false
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
        
        // Simple request body - just testing if API key is valid
        let requestBody: [String: Any] = [
            "model": "claude-3-7-sonnet-20250219",
            "max_tokens": 10,
            "stream": false,
            "messages": [
                ["role": "user", "content": [
                    ["type": "text", "text": "Hello"]
                ]]
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            print("💡 Sending test API request")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("💡 API Test Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    // API key is valid if we got a 200 response
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("💡 API Test Response: \(responseString)")
                    }
                    testResult = "✅ API key is valid!"
                } else {
                    // Try to extract error message
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("💡 API Test Error: \(responseString)")
                        
                        if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let error = errorJson["error"] as? [String: Any],
                           let message = error["message"] as? String {
                            testResult = "❌ Error: \(message)"
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
                Section {
                    NavigationLink {
                        APIConfigurationView()
                            .environmentObject(themeManager)
                            .environmentObject(chatManager)
                    } label: {
                        HStack {
                            Text("API Configuration")
                            
                            Spacer()
                            
                            HStack {
                                if !apiKey.isEmpty && apiKey.hasPrefix("sk-ant") {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Connected")
                                        .foregroundColor(.secondary)
                                } else {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("Not configured")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                
                Section {
                    NavigationLink {
                        MemoryContentView(
                            memoryManager: memoryManager,
                            chatManager: chatManager,
                            showingResetConfirmation: $showingResetConfirmation
                        )
                    } label: {
                        HStack {
                            Text("Memory")
                            
                            Spacer()
                            
                            HStack {
                                Text("\(memoryManager.memories.count)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
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
                                
                                // Reload memory and ensure API service is updated
                                let _ = await memoryManager.readMemory() // This will recreate with default content
                                
                                // Refresh the context data in the API service
                                await chatManager.refreshContextData()
                                print("📝 Memory reset: Refreshed context data in API service")
                                
                                // Show confirmation to user
                                await MainActor.run {
                                    // Provide haptic feedback
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    
                                    testResult = "✅ Memory reset successfully!"
                                    
                                    // Clear the success message after a delay
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                        if testResult == "✅ Memory reset successfully!" {
                                            testResult = nil
                                        }
                                    }
                                    
                                    // No need for forced reload with NavigationLink
                                }
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will delete all memory data. This action cannot be undone.")
                    }
                }
                
                Section {
                    NavigationLink {
                        ThemeSelectionView()
                            .environmentObject(themeManager)
                    } label: {
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
                    
                    NavigationLink {
                        SpeechSettingsView()
                            .environmentObject(themeManager)
                            .environmentObject(speechManager)
                    } label: {
                        HStack {
                            Text("Speech")
                            
                            Spacer()
                            
                            HStack {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundColor(.secondary)
                                    .frame(width: 16, height: 16)
                                Text("Voices")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Section(footer: 
                    Text("Cosmic Coach will remind you to check important daily basics like eating and drinking water.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                ) {
                    Toggle("Daily Basics Check", isOn: $checkBasicsDaily)
                }
                
                Section(footer:
                    Text("Cosmic Coach will automatically send you a message when you open the app (only if you've been away for at least 5 minutes).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                ) {
                    Toggle("Automatic Messages", isOn: $enableAutomaticResponses)
                }
                
                Section(footer:
                    Text("Cosmic Coach will use your location in its context window.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                ) {
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
                }
                
                Section {
                    NavigationLink {
                        SyncDevicesView()
                            .environmentObject(themeManager)
                            .environmentObject(multipeerService)
                    } label: {
                        HStack {
                            Text("Sync Devices")
                            
                            Spacer()
                            
                            HStack {
                                if multipeerService.isSyncEnabled {
                                    Text("\(multipeerService.connectedPeers.count) connected")
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Off")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                
                Section {
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
                            // Use the proper ChatManager method to clear all chat messages
                            chatManager.clearAllMessages()
                            
                            // Verify memory file still exists after chat deletion and reload it
                            Task {
                                // Ensure memory is loaded after chat deletion
                                let _ = await memoryManager.readMemory()
                                
                                // Refresh the context data in the API service 
                                await chatManager.refreshContextData()
                                print("📝 Chat history deleted: Refreshed context data in API service")
                                
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
                                    
                                    // We already used haptic feedback above, no need to repeat
                                }
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will delete all Chat message data. This action cannot be undone.")
                    }
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
            .applyThemeColor()
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
        .environmentObject(SpeechManager())
        .environmentObject(MultipeerService())
}
