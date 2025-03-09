import SwiftUI
import UIKit

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
        
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmedKey, forKey: "claude_api_key")
        UserDefaults.standard.synchronize()
        
        let savedKey = UserDefaults.standard.string(forKey: "claude_api_key") ?? ""
        
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue(savedKey, forHTTPHeaderField: "x-api-key")
        
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
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("💡 API Test Response: \(responseString)")
                    }
                    testResult = "✅ Connected"
                } else {
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
                            .font(.title3)
                            .foregroundColor(themeManager.accentColor(for: colorScheme))
                        Text("API Key")
                            .font(.headline)
                    }
                    
                    Text("Connect to Claude AI with your Anthropic API key to enable the personal coaching capabilities in this app.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                    
                    //Moved APIKeyCardView content here.
                    VStack(alignment: .leading, spacing: 12) {
                        SecureField("API Key ('sk-ant-')", text: $apiKey)
                            .padding()
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                            .onChange(of: apiKey) { oldValue, newValue in
                                let trimmedKey = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                UserDefaults.standard.set(trimmedKey, forKey: "claude_api_key")
                                print("API key saved to UserDefaults. Length: \(trimmedKey.count)")
                                testResult = nil
                            }
                        
                        if !apiKey.isEmpty && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("sk-ant") {
                            Text("Warning: This doesn't look like a Claude API key. Claude API keys start with 'sk-ant-'.")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        
                        // Status message display
                        if let result = testResult {
                            HStack {
                                if result.hasPrefix("✅") {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                } else {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                                Text(result.replacingOccurrences(of: "✅ ", with: "").replacingOccurrences(of: "❌ ", with: ""))
                                    .foregroundColor(result.hasPrefix("✅") ? .green : .red)
                            }
                            .padding(.vertical, 8)
                        }
                        
                        // Test API key button
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(themeManager.accentColor(for: colorScheme).opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(themeManager.accentColor(for: colorScheme).opacity(0.3), lineWidth: 1)
                                )
                            
                            Button(action: {
                                Task {
                                    await testApiKey()
                                }
                            }) {
                                HStack {
                                    Spacer()
                                    if isTestingKey {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle())
                                        Text("Connecting...")
                                    } else {
                                        Text("Test API Key")
                                            .fontWeight(.medium)
                                    }
                                    Spacer()
                                }
                                .padding()
                                .foregroundColor(themeManager.accentColor(for: colorScheme))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(apiKey.isEmpty || isTestingKey)
                        }
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                        
                        // Get API key link
                        HStack {
                            Spacer()
                            // This ButtonStyle wrapper prevents the tap area from extending beyond the visible content
                            Button(action: {
                                UIApplication.shared.open(URL(string: "https://console.anthropic.com/")!)
                            }) {
                                HStack(spacing: 4) {
                                    Text("Get a Claude API Key")
                                        .font(.caption)
                                        .foregroundColor(themeManager.accentColor(for: colorScheme))
                                    Image(systemName: "arrow.up.forward.square")
                                        .font(.caption)
                                        .foregroundColor(themeManager.accentColor(for: colorScheme))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.clear)
                                )
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        .padding(.top, 12)
                    }
                    .padding(.top, 8)
                }
                .padding(.vertical, 4)
            }
            
            Section(header: Text("Token Limit")) {
                TokenLimitView(tokenLimit: $tokenLimit)
            }
            
            Section(header: Text("About Claude API")) {
                Text("You will need to create an Anthropic account and subscribe to their API service to use this app. API usage is billed directly by Anthropic based on your account's plan.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            }
        }
        .navigationTitle("API Configuration")
        .navigationBarTitleDisplayMode(.inline)
        .id(refreshID)
        .accentColor(themeManager.accentColor(for: colorScheme))
    }
}

struct TokenLimitView: View {
    @Binding var tokenLimit: Int
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeManager: ThemeManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(tokenLimit)")
                    .font(.headline)
                Spacer()
                Text(tokenLimitDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(themeManager.accentColor(for: colorScheme).opacity(0.1))
                    )
            }
            
            Slider(value: Binding(
                get: { Double(tokenLimit) },
                set: { tokenLimit = Int($0) }
            ), in: 10000...100000, step: 5000)
            .accentColor(themeManager.accentColor(for: colorScheme))
            .padding(.vertical, 8)
            
            Text("Controls how much conversation history is sent to Claude. Higher limits provide more context but cost more per request.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
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