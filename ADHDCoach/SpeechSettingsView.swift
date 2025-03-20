import SwiftUI
import AVFoundation

struct SpeechSettingsView: View {
    @EnvironmentObject private var speechManager: SpeechManager
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var selectedVoiceId: String
    @State private var testText = "Hello, this is a test of the selected voice."
    
    init() {
        // Initialize with the current selection from UserDefaults
        let savedVoiceId = UserDefaults.standard.string(forKey: "selected_voice_identifier") ?? ""
        _selectedVoiceId = State(initialValue: savedVoiceId)
    }
    
    var filteredVoices: [AVSpeechSynthesisVoice] {
        if searchText.isEmpty {
            return speechManager.availableVoices
        } else {
            return speechManager.availableVoices.filter { voice in
                let displayName = speechManager.getDisplayName(for: voice).lowercased()
                return displayName.contains(searchText.lowercased())
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                // Search bar
                if #available(iOS 15.0, *) {
                    List {
                        Section(header: Text("Test Voice")) {
                            TextField("Enter text to test voices", text: $testText)
                                .textFieldStyle(.roundedBorder)
                                .padding(.vertical, 5)
                            
                            Button(action: {
                                if let selectedVoice = speechManager.availableVoices.first(where: { $0.identifier == selectedVoiceId }) {
                                    speechManager.setVoice(identifier: selectedVoice.identifier)
                                    speechManager.speak(text: testText)
                                }
                            }) {
                                HStack {
                                    Text("Speak Test Text")
                                    Spacer()
                                    Image(systemName: "speaker.wave.2.fill")
                                }
                            }
                            .disabled(testText.isEmpty)
                        }
                        
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
                                        .foregroundColor(selectedVoiceId == voice.identifier ? themeManager.accentColor(for: colorScheme) : .gray)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedVoiceId = voice.identifier
                                    speechManager.setVoice(identifier: voice.identifier)
                                    
                                    // Provide haptic feedback
                                    let generator = UIImpactFeedbackGenerator(style: .light)
                                    generator.impactOccurred()
                                }
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search voices")
                } else {
                    // Fallback for iOS 14
                    List {
                        Section(header: Text("Search")) {
                            TextField("Search voices", text: $searchText)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Section(header: Text("Test Voice")) {
                            TextField("Enter text to test voices", text: $testText)
                                .textFieldStyle(.roundedBorder)
                                .padding(.vertical, 5)
                            
                            Button(action: {
                                if let selectedVoice = speechManager.availableVoices.first(where: { $0.identifier == selectedVoiceId }) {
                                    speechManager.setVoice(identifier: selectedVoice.identifier)
                                    speechManager.speak(text: testText)
                                }
                            }) {
                                HStack {
                                    Text("Speak Test Text")
                                    Spacer()
                                    Image(systemName: "speaker.wave.2.fill")
                                }
                            }
                            .disabled(testText.isEmpty)
                        }
                        
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
                                        .foregroundColor(selectedVoiceId == voice.identifier ? themeManager.accentColor(for: colorScheme) : .gray)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedVoiceId = voice.identifier
                                    speechManager.setVoice(identifier: voice.identifier)
                                    
                                    // Provide haptic feedback
                                    let generator = UIImpactFeedbackGenerator(style: .light)
                                    generator.impactOccurred()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Speech")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(colorScheme)
            .applyThemeColor()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        speechManager.stopSpeaking()
                        dismiss()
                    }
                    .foregroundColor(themeManager.accentColor(for: colorScheme))
                }
            }
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