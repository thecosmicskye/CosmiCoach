import SwiftUI
import AVFoundation

struct SpeechSettingsView: View {
    @EnvironmentObject private var speechManager: SpeechManager
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var selectedVoiceId: String
    
    init() {
        // Initialize with the current selection from UserDefaults
        let savedVoiceId = UserDefaults.standard.string(forKey: "selected_voice_identifier") ?? ""
        _selectedVoiceId = State(initialValue: savedVoiceId)
    }
    
    var filteredVoices: [AVSpeechSynthesisVoice] {
        // Get only English voices and sort with Enhanced first
        let englishVoices = speechManager.availableVoices.filter { voice in 
            return voice.language.starts(with: "en-")
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
                Section(header: Text("Voices")) {
                    ForEach(filteredVoices, id: \.identifier) { voice in
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
                                Text("Premium")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.2))
                                    .cornerRadius(4)
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