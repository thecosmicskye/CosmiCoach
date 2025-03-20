import SwiftUI
import AVFoundation

struct SpeechSettingsView: View {
    @EnvironmentObject private var speechManager: SpeechManager
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var selectedVoiceId: String
    @State private var isRequestingPermission = false
    @State private var showGoToSettingsAlert = false
    
    init() {
        // Initialize with the current selection from UserDefaults
        let savedVoiceId = UserDefaults.standard.string(forKey: "selected_voice_identifier") ?? ""
        _selectedVoiceId = State(initialValue: savedVoiceId)
    }
    
    var personalVoices: [AVSpeechSynthesisVoice] {
        speechManager.availableVoices.filter { voice in
            return speechManager.isPersonalVoice(voice)
        }
    }
    
    var filteredVoices: [AVSpeechSynthesisVoice] {
        // Get only English voices (excluding personal voices) and sort with Enhanced first
        let englishVoices = speechManager.availableVoices.filter { voice in 
            return voice.language.starts(with: "en-") && !speechManager.isPersonalVoice(voice)
        }.sorted { (voice1, voice2) -> Bool in
            // Enhanced voices at the top
            if voice1.name.contains("Enhanced") && !voice2.name.contains("Enhanced") {
                return true
            } else if !voice1.name.contains("Enhanced") && voice2.name.contains("Enhanced") {
                return false
            }
            
            // Then sort by quality
            if voice1.quality != voice2.quality {
                return voice1.quality.rawValue > voice2.quality.rawValue
            }
            
            // Then by name
            return voice1.name < voice2.name
        }
        
        // Apply search filter if needed
        if searchText.isEmpty {
            return englishVoices
        } else {
            return englishVoices.filter { voice in
                let displayName = speechManager.getDisplayName(for: voice).lowercased()
                return displayName.contains(searchText.lowercased())
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if #available(iOS 17.0, macOS 14.0, *) {
                    Section(header: Text("Personal Voice")) {
                        if speechManager.personalVoiceAuthStatus != .authorized {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Status: \(speechManager.personalVoiceStatusText())")
                                        .font(.subheadline)
                                    
                                    Spacer()
                                    
                                    if speechManager.personalVoiceAuthStatus == .notDetermined {
                                        Button("Request Access") {
                                            isRequestingPermission = true
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(isRequestingPermission)
                                    } else if speechManager.personalVoiceAuthStatus == .denied {
                                        Button("Settings") {
                                            showGoToSettingsAlert = true
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                                
                                Text("Personal Voice lets you use a voice that sounds like you or someone you know for speech synthesis.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                        
                        if !personalVoices.isEmpty {
                            ForEach(personalVoices, id: \.identifier) { voice in
                                voiceRow(for: voice)
                            }
                        } else if speechManager.personalVoiceAuthStatus == .authorized {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("No Personal Voices Found")
                                    .font(.headline)
                                Text("Create a Personal Voice in iOS Settings > Accessibility > Personal Voice")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
                
                Section(header: Text("System Voices")) {
                    ForEach(filteredVoices, id: \.identifier) { voice in
                        voiceRow(for: voice)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search voices")
            .navigationTitle("Speech")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(colorScheme)
            .applyThemeColor()
            .onChange(of: selectedVoiceId) { _, newValue in
                speechManager.setVoice(identifier: newValue)
            }
            .onDisappear {
                speechManager.stopSpeaking()
            }
            .task {
                // Check authorization status when view appears
                if #available(iOS 17.0, macOS 14.0, *) {
                    speechManager.personalVoiceAuthStatus = AVSpeechSynthesizer.personalVoiceAuthorizationStatus
                }
            }
            .task(id: isRequestingPermission) {
                // Request authorization when the button is tapped
                if isRequestingPermission {
                    await speechManager.requestPersonalVoiceAuthorization()
                    isRequestingPermission = false
                }
            }
            .alert("Open Settings", isPresented: $showGoToSettingsAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } message: {
                Text("Enable Personal Voice access in Settings to use this feature.")
            }
        }
    }
    
    private func voiceRow(for voice: AVSpeechSynthesisVoice) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(voice.name)
                    .font(.headline)
                Text(getLanguageName(for: voice.language))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if voice.quality == .premium {
                if speechManager.isPersonalVoice(voice) {
                    Text("Personal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                } else {
                    Text("Premium")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            
            Image(systemName: selectedVoiceId == voice.identifier ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundColor(selectedVoiceId == voice.identifier ? themeManager.accentColor(for: colorScheme) : .gray)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedVoiceId = voice.identifier
            speechManager.setVoice(identifier: voice.identifier)
            
            // Speak test message with the selected voice
            speechManager.speak(text: "This is my voice.")
            
            // Provide haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
    }
    
    private func getLanguageName(for languageCode: String) -> String {
        let locale = Locale(identifier: languageCode)
        if let languageName = locale.localizedString(forLanguageCode: languageCode) {
            return languageName
        }
        return languageCode
    }
}

#Preview {
    SpeechSettingsView()
        .environmentObject(SpeechManager())
        .environmentObject(ThemeManager())
}