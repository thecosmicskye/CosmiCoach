import SwiftUI

struct OnboardingView: View {
    @FocusState private var apiKeyIsFocused: Bool
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject var chatManager: ChatManager
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentStep = 0
    @State private var apiKey = ""
    @State private var isTestingKey = false
    @State private var testResult: String? = nil
    @State private var showAlert = false
    
    var body: some View {
        NavigationStack {
            VStack {
                // Step indicator
                HStack(spacing: 8) {
                    ForEach(0..<2) { step in
                        Circle()
                            .fill(currentStep == step ? themeManager.accentColor(for: colorScheme) : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 24)
                
                TabView(selection: $currentStep) {
                    welcomeView
                        .tag(0)
                    
                    apiKeyView
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(), value: currentStep)
                .onChange(of: currentStep) { newValue in
                    if newValue == 0 && apiKeyIsFocused {
                        apiKeyIsFocused = false
                    }
                }
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(colorScheme)
            .applyThemeColor()
        }
    }
    
    // MARK: - Welcome Screen
    private var welcomeView: some View {
        VStack(alignment: .center, spacing: 32) {
            Spacer()
            
            Image("AppIconImage")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)
                .cornerRadius(25)
                .padding(.bottom, 16)
            
            Text("Overcome overwhelm")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Text("Get support from AI to manage tasks, calendar and daily life.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Spacer()
            
            Button {
                currentStep = 1
            } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(themeManager.accentColor(for: colorScheme))
                    .cornerRadius(14)
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - API Key Screen
    private var apiKeyView: some View {
        VStack(alignment: .center, spacing: 12) {
            Spacer().frame(height: 20)
            
            Text("Add Claude API Key")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Show the description only when the API key field is not focused
            if !apiKeyIsFocused {
                Text("You'll need to use your own API key for this app to work.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            
            VStack(alignment: .leading) {
                Text("Claude API Key")
                    .font(.headline)
                
                SecureField("sk-ant-...", text: $apiKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .focused($apiKeyIsFocused)
                
                if !apiKey.isEmpty && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("sk-ant-") {
                    Text("API key should start with 'sk-ant-'")
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                if let result = testResult {
                    HStack {
                        if result.contains("Success") {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                        Text(result)
                            .foregroundColor(result.contains("Success") ? .green : .red)
                            .font(.caption)
                    }
                    .padding(.top, 4)
                }
                
                Link("Get a Claude API key", destination: URL(string: "https://console.anthropic.com/")!)
                    .font(.caption)
                    .padding(.top, 4)
                    .foregroundColor(themeManager.accentColor(for: colorScheme))
            }
            .padding()
            
            Spacer()
            
            VStack(spacing: 12) {
                Button {
                    if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("sk-ant-") {
                        testAPIKey()
                    } else {
                        showAlert = true
                    }
                } label: {
                    if isTestingKey {
                        HStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .tint(.white)
                            Text("Connecting...")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(themeManager.accentColor(for: colorScheme))
                        .cornerRadius(14)
                    } else {
                        Text("Continue")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(themeManager.accentColor(for: colorScheme))
                            .cornerRadius(14)
                    }
                }
                .disabled(isTestingKey)
                .alert(isPresented: $showAlert) {
                    Alert(
                        title: Text("Invalid API Key"),
                        message: Text("Please enter a valid Claude API key starting with 'sk-ant-'."),
                        dismissButton: .default(Text("OK"))
                    )
                }
                
                Button {
                    completeOnboarding()
                } label: {
                    Text("Skip for now")
                        .foregroundColor(themeManager.accentColor(for: colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .padding(.horizontal)
        }
    }
    
    private func testAPIKey() {
        guard let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty else {
            return
        }
        
        isTestingKey = true
        
        Task {
            let result = await chatManager.testAPIKey(trimmedKey)
            
            await MainActor.run {
                isTestingKey = false
                
                if result {
                    // Save the API key to UserDefaults
                    UserDefaults.standard.set(trimmedKey, forKey: "claude_api_key")
                    
                    // Complete onboarding immediately on success
                    completeOnboarding()
                } else {
                    // Only show error message if API key is invalid
                    testResult = "Error: Could not connect with this API key."
                }
            }
        }
    }
    
    private func completeOnboarding() {
        withAnimation {
            hasCompletedOnboarding = true
        }
    }
}

extension String {
    var nonEmpty: String? {
        return self.isEmpty ? nil : self
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
        .environmentObject(ChatManager())
        .environmentObject(ThemeManager())
}
