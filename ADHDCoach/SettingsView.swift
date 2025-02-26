import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @AppStorage("check_basics_daily") private var checkBasicsDaily = true
    @AppStorage("token_limit") private var tokenLimit = 75000
    @State private var isTestingKey = false
    @State private var testResult: String? = nil
    
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
        
        // Simple request body
        let requestBody: [String: Any] = [
            "model": "claude-3-7-sonnet-20240229",
            "max_tokens": 10,
            "messages": [
                ["role": "user", "content": "Hello"]
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    testResult = "✅ API key is valid!"
                } else {
                    // Try to extract error message
                    if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = errorJson["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        testResult = "❌ Error: \(message)"
                    } else {
                        testResult = "❌ Error: Status code \(httpResponse.statusCode)"
                    }
                }
            }
        } catch {
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
                }
                
                Section(header: Text("Coaching Preferences")) {
                    Toggle("Daily Basics Check", isOn: $checkBasicsDaily)
                    
                    Stepper("Token Limit: \(tokenLimit)", value: $tokenLimit, in: 10000...100000, step: 5000)
                        .help("Controls how much conversation history is sent to Claude")
                }
                
                Section(header: Text("Memory Management")) {
                    Button("View Memory File") {
                        // This would navigate to a memory file viewer
                    }
                    
                    Button("Reset Memory") {
                        // This would show a confirmation dialog
                    }
                    .foregroundColor(.red)
                }
                
                Section(header: Text("About")) {
                    Text("ADHD Coach v1.0")
                        .foregroundColor(.secondary)
                    
                    Text("This app uses Claude 3.7 to help manage your calendar, reminders, and provide ADHD coaching.")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
