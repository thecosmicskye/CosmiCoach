import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject var chatManager: ChatManager
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
                            .fill(currentStep == step ? Color.accentColor : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 24)
                
                if currentStep == 0 {
                    welcomeView
                } else {
                    apiKeyView
                }
            }
            .padding()
            .animation(.spring(), value: currentStep)
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
                withAnimation {
                    currentStep = 1
                }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .cornerRadius(14)
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - API Key Screen
    private var apiKeyView: some View {
        VStack(alignment: .center, spacing: 20) {
            Spacer()
            
            Text("Add Claude API Key")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Text("You'll need to use your own API key for this app to work.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            VStack(alignment: .leading) {
                Text("Claude API Key")
                    .font(.headline)
                
                SecureField("sk-ant-...", text: $apiKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                
                if !apiKey.isEmpty && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("sk-ant-") {
                    Text("API key should start with 'sk-ant-'")
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                if let result = testResult {
                    Text(result)
                        .foregroundColor(result.contains("Success") ? .green : .red)
                        .font(.caption)
                        .padding(.top, 4)
                }
                
                Link("Get a Claude API key", destination: URL(string: "https://console.anthropic.com/")!)
                    .font(.caption)
                    .padding(.top, 4)
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
                    Text(isTestingKey ? "Testing..." : "Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .cornerRadius(14)
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
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
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
                testResult = result ? "Success! API key is valid." : "Error: Could not connect with this API key."
                isTestingKey = false
                
                if result {
                    // Save the API key to UserDefaults
                    UserDefaults.standard.set(trimmedKey, forKey: "claude_api_key")
                    
                    // Complete onboarding after a short delay to show success message
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        completeOnboarding()
                    }
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
}
