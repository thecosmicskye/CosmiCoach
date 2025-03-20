import Foundation
import AVFoundation

class SpeechManager: NSObject, ObservableObject {
    @Published var availableVoices: [AVSpeechSynthesisVoice] = []
    @Published var selectedVoiceIdentifier: String = ""
    @Published var isSpeaking: Bool = false
    @Published var personalVoiceAuthStatus: AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus = .notDetermined
    @Published var hasPersonalVoices: Bool = false
    
    private let synthesizer = AVSpeechSynthesizer()
    
    override init() {
        super.init()
        synthesizer.delegate = self
        
        // Configure audio session to allow playback through speakers
        configureAudioSession()
        
        // Check personal voice authorization status
        if #available(iOS 17.0, macOS 14.0, *) {
            personalVoiceAuthStatus = AVSpeechSynthesizer.personalVoiceAuthorizationStatus
            
            // Setup notification listener for voice changes
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(availableVoicesDidChange),
                name: AVSpeechSynthesizer.availableVoicesDidChangeNotification,
                object: nil
            )
        }
        
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
    
    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Configure to allow playback through device speakers
            try audioSession.setCategory(.playback, mode: .default, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error.localizedDescription)")
        }
    }
    
    @objc private func availableVoicesDidChange(_ notification: Notification) {
        loadAvailableVoices()
    }
    
    private func loadAvailableVoices() {
        // Get all available voices
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        
        // Check if we have personal voices
        if #available(iOS 17.0, macOS 14.0, *) {
            hasPersonalVoices = allVoices.contains { voice in
                voice.quality == .premium && voice.name.contains("Personal Voice")
            }
        }
        
        // Sort voices by language and quality
        availableVoices = allVoices.sorted { (voice1, voice2) -> Bool in
            // Personal voices at the very top if available
            if #available(iOS 17.0, macOS 14.0, *) {
                if voice1.name.contains("Personal Voice") && !voice2.name.contains("Personal Voice") {
                    return true
                } else if !voice1.name.contains("Personal Voice") && voice2.name.contains("Personal Voice") {
                    return false
                }
            }
            
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
        
        // Ensure audio session is properly configured
        configureAudioSession()
        
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
    
    func requestPersonalVoiceAuthorization() async {
        if #available(iOS 17.0, macOS 14.0, *) {
            // Only request if not already authorized or denied
            if personalVoiceAuthStatus == .notDetermined {
                let status = await AVSpeechSynthesizer.requestPersonalVoiceAuthorization()
                DispatchQueue.main.async {
                    self.personalVoiceAuthStatus = status
                    // Reload voices to pick up any personal voices
                    self.loadAvailableVoices()
                }
            }
        }
    }
    
    func personalVoiceStatusText() -> String {
        if #available(iOS 17.0, macOS 14.0, *) {
            switch personalVoiceAuthStatus {
            case .authorized:
                return hasPersonalVoices ? "Authorized - Personal Voice available" : "Authorized - Create a Personal Voice in Settings"
            case .denied:
                return "Access Denied - Enable in Settings"
            case .notDetermined:
                return "Not Requested"
            case .unsupported:
                return "Not Supported on this Device"
            @unknown default:
                return "Unknown Status"
            }
        } else {
            return "Requires iOS 17 or macOS 14"
        }
    }
    
    func isPersonalVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        if #available(iOS 17.0, macOS 14.0, *) {
            return voice.name.contains("Personal Voice")
        }
        return false
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