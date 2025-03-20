import Foundation
import AVFoundation

class SpeechManager: NSObject, ObservableObject {
    @Published var availableVoices: [AVSpeechSynthesisVoice] = []
    @Published var selectedVoiceIdentifier: String = ""
    @Published var isSpeaking: Bool = false
    
    private let synthesizer = AVSpeechSynthesizer()
    
    override init() {
        super.init()
        synthesizer.delegate = self
        loadAvailableVoices()
        
        // Load saved voice or use default
        if let savedVoiceId = UserDefaults.standard.string(forKey: "selected_voice_identifier"),
           availableVoices.contains(where: { $0.identifier == savedVoiceId }) {
            selectedVoiceIdentifier = savedVoiceId
        } else {
            // Default to system voice or first English voice
            selectedVoiceIdentifier = AVSpeechSynthesisVoice.currentLanguageCode()
        }
    }
    
    private func loadAvailableVoices() {
        // Get all available voices
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        
        // Sort voices by language and quality
        availableVoices = allVoices.sorted { (voice1, voice2) -> Bool in
            if voice1.language == voice2.language {
                // Premium voices first, then alphabetical by name
                if voice1.quality != voice2.quality {
                    return voice1.quality.rawValue > voice2.quality.rawValue
                }
                return voice1.name < voice2.name
            }
            // Sort by language code
            return voice1.language < voice2.language
        }
    }
    
    func getDisplayName(for voice: AVSpeechSynthesisVoice) -> String {
        let quality = voice.quality == .premium ? " (Premium)" : ""
        let languageName = getLanguageName(for: voice.language)
        return "\(voice.name) - \(languageName)\(quality)"
    }
    
    private func getLanguageName(for languageCode: String) -> String {
        let locale = Locale(identifier: languageCode)
        if let languageName = locale.localizedString(forLanguageCode: languageCode) {
            return languageName
        }
        return languageCode
    }
    
    func speak(text: String) {
        // Stop any current speech
        if isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        // Create utterance with selected voice
        let utterance = AVSpeechUtterance(string: text)
        
        // Set the voice if available
        if let voice = availableVoices.first(where: { $0.identifier == selectedVoiceIdentifier }) {
            utterance.voice = voice
        } else if let defaultVoice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode()) {
            utterance.voice = defaultVoice
        }
        
        // Configure speech parameters
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        // Start speaking
        isSpeaking = true
        synthesizer.speak(utterance)
    }
    
    func stopSpeaking() {
        if isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
    
    func setVoice(identifier: String) {
        selectedVoiceIdentifier = identifier
        UserDefaults.standard.set(identifier, forKey: "selected_voice_identifier")
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension SpeechManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }
}