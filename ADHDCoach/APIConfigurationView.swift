import SwiftUI

struct APIConfigurationView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var chatManager: ChatManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String
    @AppStorage("token_limit") private var tokenLimit = 75000
    @State private var isTestingKey = false
    @State private var testResult: String? = nil
    @State private var refreshID = UUID()
    
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
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "key.fill")
                            .font(.title)
                            .foregroundColor(themeManager.accentColor(for: colorScheme))
                        Text("API Configuration")
                            .font(.headline)
                    }
                    
                    Text("Connect to Claude AI with your Anthropic API key to enable the personal coaching capabilities in this app.")
                        .font(.body)
                        .padding(.vertical, 4)
                    
                    APIKeyCardView(
                        apiKey: $apiKey,
                        isTestingKey: $isTestingKey,
                        testResult: $testResult,
                        onTest: {
                            Task {
                                await testApiKey()
                                
                                // Clear result after 3 seconds
                                if testResult != nil {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                        testResult = nil
                                    }
                                }
                            }
                        }
                    )
                    .padding(.top, 8)
                }
                .padding(.vertical, 4)
            }
            
            Section(header: Text("Model Configuration")) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "cpu.fill")
                            .font(.title3)
                            .foregroundColor(themeManager.accentColor(for: colorScheme))
                        Text("Claude 3.7 Sonnet")
                            .font(.headline)
                    }
                    
                    Text("This app uses Claude 3.7 Sonnet, optimized for daily ADHD coaching with enhanced reasoning and planning capabilities.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                    
                    TokenLimitView(tokenLimit: $tokenLimit)
                }
                .padding(.vertical, 8)
            }
            
            Section(header: Text("About Claude API")) {
                InfoCardView(
                    title: "Getting Started",
                    items: [
                        InfoItem(name: "1. Create Anthropic Account", value: "anthropic.com"),
                        InfoItem(name: "2. Get API Key", value: "console.anthropic.com"),
                        InfoItem(name: "3. Enter Key Above", value: "")
                    ]
                )
                .padding(.vertical, 8)
                
                Link(destination: URL(string: "https://console.anthropic.com/")!) {
                    HStack {
                        Spacer()
                        Text("Go to Anthropic Console")
                            .foregroundColor(.white)
                            .padding(.vertical, 10)
                        Spacer()
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(themeManager.accentColor(for: colorScheme))
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.vertical, 8)
                
                Text("You will need to create an Anthropic account and subscribe to their API service to use this app. API usage is billed directly by Anthropic based on your account's plan.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
        }
        .navigationTitle("API Configuration")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(
            Group {
                if let result = testResult {
                    VStack {
                        Spacer()
                        Text(result)
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                            .shadow(radius: 2)
                            .padding(.bottom, 20)
                    }
                }
            }
        )
        .id(refreshID)
        .accentColor(themeManager.accentColor(for: colorScheme))
    }
}

struct APIKeyCardView: View {
    @Binding var apiKey: String
    @Binding var isTestingKey: Bool
    @Binding var testResult: String?
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeManager: ThemeManager
    let onTest: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SecureField("Paste API Key Here (starts with 'sk-ant-')", text: $apiKey)
                .padding()
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .onChange(of: apiKey) { oldValue, newValue in
                    // Trim whitespace before saving
                    let trimmedKey = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    UserDefaults.standard.set(trimmedKey, forKey: "claude_api_key")
                    print("API key saved to UserDefaults. Length: \(trimmedKey.count)")
                    
                    // Reset test result when key changes
                    testResult = nil
                }
            
            if !apiKey.isEmpty && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("sk-ant") {
                Text("Warning: This doesn't look like a Claude API key. Claude API keys start with 'sk-ant-'.")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            Button(action: onTest) {
                HStack {
                    Spacer()
                    if isTestingKey {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .padding(.trailing, 8)
                        Text("Testing Connection...")
                    } else {
                        Image(systemName: "network")
                            .padding(.trailing, 8)
                        Text("Test API Key")
                    }
                    Spacer()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(themeManager.accentColor(for: colorScheme).opacity(0.2))
                )
                .foregroundColor(themeManager.accentColor(for: colorScheme))
            }
            .disabled(apiKey.isEmpty || isTestingKey || testResult != nil)
        }
    }
}

struct TokenLimitView: View {
    @Binding var tokenLimit: Int
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeManager: ThemeManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Token Limit: \(tokenLimit)")
                    .font(.headline)
                Spacer()
                Text(tokenLimitDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Slider(value: Binding(
                get: { Double(tokenLimit) },
                set: { tokenLimit = Int($0) }
            ), in: 10000...100000, step: 5000)
            .accentColor(themeManager.accentColor(for: colorScheme))
            
            Text("Controls how much conversation history is sent to Claude. Higher limits provide more context but cost more per request.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var tokenLimitDescription: String {
        switch tokenLimit {
        case 10000...25000: return "Minimal"
        case 25001...50000: return "Balanced"
        case 50001...75000: return "Enhanced"
        case 75001...100000: return "Maximum"
        default: return "Custom"
        }
    }
}

#Preview {
    NavigationStack {
        APIConfigurationView()
            .environmentObject(ThemeManager())
            .environmentObject(ChatManager())
    }
}