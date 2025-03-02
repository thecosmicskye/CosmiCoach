import Foundation

/**
 * ChatAutomaticMessageService manages automatic message generation based on app usage patterns.
 *
 * This class is responsible for:
 * - Determining when to send automatic messages to the user
 * - Tracking app open/close times
 * - Checking user preferences for automatic messages
 * - Handling special cases like post-history deletion messages
 */
class ChatAutomaticMessageService {
    /// Tracks when the app was last opened
    private var lastAppOpenTime: Date?
    
    /**
     * Initializes the service and records the current time as the app open time.
     */
    init() {
        // Record the time the app was opened
        lastAppOpenTime = Date()
        print("⏱️ ChatAutomaticMessageService initialized - lastAppOpenTime set to: \(lastAppOpenTime!)")
    }
    
    /**
     * Returns the time when the app was last opened.
     *
     * @return The last app open time, or nil if not available
     */
    func getLastAppOpenTime() -> Date? {
        return lastAppOpenTime
    }
    
    /**
     * Determines if an automatic message should be sent based on app usage patterns.
     *
     * This method checks:
     * - If automatic messages are enabled in settings
     * - If an API key is available
     * - If the app hasn't been opened for at least 5 minutes
     *
     * @return True if an automatic message should be sent, false otherwise
     */
    func shouldSendAutomaticMessage() async -> Bool {
        print("⏱️ AUTOMATIC MESSAGE CHECK START - \(Date())")
        
        // Check if automatic messages are enabled in settings
        let automaticMessagesEnabled = UserDefaults.standard.bool(forKey: "enable_automatic_responses")
        print("⏱️ Automatic messages enabled in settings: \(automaticMessagesEnabled)")
        guard automaticMessagesEnabled else {
            print("⏱️ Automatic message skipped: Automatic messages are disabled in settings")
            return false
        }
        
        // Check if we have the API key
        let apiKey = UserDefaults.standard.string(forKey: "claude_api_key") ?? ""
        let hasApiKey = !apiKey.isEmpty
        print("⏱️ API key available: \(hasApiKey)")
        guard hasApiKey else {
            print("⏱️ Automatic message skipped: No API key available")
            return false
        }
        
        // Always update lastAppOpenTime to ensure background->active transitions work properly
        lastAppOpenTime = Date()
        print("⏱️ Updated lastAppOpenTime to current time: \(lastAppOpenTime!)")
        
        // Check if the app hasn't been opened for at least 5 minutes
        let lastSessionKey = "last_app_session_time"
        
        // Always store current time when checking - this fixes the bug where
        // closing the app without fully terminating doesn't update the session time
        let currentTime = Date().timeIntervalSince1970
        print("⏱️ Current time: \(Date(timeIntervalSince1970: currentTime))")
        
        // IMPORTANT: Get the current store time BEFORE updating it
        var timeSinceLastSession: TimeInterval = 999999 // Default to a large value to ensure we run
        
        if let lastSessionTimeInterval = UserDefaults.standard.object(forKey: lastSessionKey) as? TimeInterval {
            let lastSessionTime = Date(timeIntervalSince1970: lastSessionTimeInterval)
            timeSinceLastSession = Date().timeIntervalSince(lastSessionTime)
            
            print("⏱️ Last session time: \(lastSessionTime)")
            print("⏱️ Time since last session: \(timeSinceLastSession) seconds")
        } else {
            print("⏱️ No previous session time found in UserDefaults")
        }
        
        // Store current session time for future reference
        UserDefaults.standard.set(currentTime, forKey: lastSessionKey)
        UserDefaults.standard.synchronize() // Force synchronize to ensure it's saved
        print("⏱️ Updated session timestamp in UserDefaults: \(Date(timeIntervalSince1970: currentTime))")
        
        // Check if app was opened less than 5 minutes ago
        if timeSinceLastSession < 300 { // 300 seconds = 5 minutes
            print("⏱️ Automatic message skipped: App was opened less than 5 minutes ago (timeSinceLastSession = \(timeSinceLastSession))")
            return false
        }
        
        // If we get here, all conditions are met - send the automatic message
        print("⏱️ All conditions met for sending automatic message")
        return true
    }
    
    /**
     * Determines if an automatic message should be sent after chat history deletion.
     *
     * This is a special case that provides a welcome message after history is cleared.
     *
     * @return True if an automatic message should be sent, false otherwise
     */
    func shouldSendAutomaticMessageAfterHistoryDeletion() async -> Bool {
        // Check if automatic messages are enabled in settings
        // For history deletion, we respect the setting but always provide a fallback message
        let automaticMessagesEnabled = UserDefaults.standard.bool(forKey: "enable_automatic_responses")
        
        if !automaticMessagesEnabled {
            print("Automatic message after history deletion skipped: Automatic messages are disabled in settings")
            return false
        }
        
        // Check if we have the API key
        let apiKey = UserDefaults.standard.string(forKey: "claude_api_key") ?? ""
        guard !apiKey.isEmpty else {
            print("Automatic message after history deletion skipped: No API key available")
            return false
        }
        
        return true
    }
}
