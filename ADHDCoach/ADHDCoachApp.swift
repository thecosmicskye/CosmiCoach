import SwiftUI
import AVFoundation

@main
struct ADHDCoachApp: App {
    @StateObject private var chatManager = ChatManager()
    @StateObject private var eventKitManager = EventKitManager()
    @StateObject private var memoryManager = MemoryManager()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var speechManager = SpeechManager()
    @StateObject private var multipeerService = MultipeerService()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("enable_location_awareness") private var enableLocationAwareness = false
    
    // Track when the app enters background to update session time
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    
    init() {
        print("⏱️ ADHDCoachApp initializing at \(Date())")
        // Check if we have a last session time
        if let lastSessionTime = UserDefaults.standard.object(forKey: "last_app_session_time") as? TimeInterval {
            let lastTime = Date(timeIntervalSince1970: lastSessionTime)
            let timeSinceLastSession = Date().timeIntervalSince(lastTime)
            print("⏱️ ADHDCoachApp init - Last session time: \(lastTime)")
            print("⏱️ ADHDCoachApp init - Time since last session: \(timeSinceLastSession) seconds")
        } else {
            print("⏱️ ADHDCoachApp init - No previous session time found in UserDefaults")
        }
        
        // Ensure the default theme is set if no theme is saved
        if UserDefaults.standard.string(forKey: "selected_theme_id") == nil {
            UserDefaults.standard.set("pink", forKey: "selected_theme_id")
            UserDefaults.standard.synchronize()
        }
    }
    
    private func configureUIKitAppearance() {
        // Apply theme
        themeManager.setTheme(themeManager.currentTheme)
        
        // Configure navigation bar appearance to ensure visibility
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        
        // Get theme color for consistency
        let themeColor = themeManager.currentTheme.accentColor
        
        // Customize navigation bar appearance
        appearance.backgroundColor = UIColor.systemBackground
        appearance.titleTextAttributes = [.foregroundColor: UIColor(themeColor)]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(themeColor)]
        
        // Critical for visibility - set up all appearance types for navigation bar
        // Standard appearance (regular state)
        UINavigationBar.appearance().standardAppearance = appearance
        // Compact appearance (compact height state)
        UINavigationBar.appearance().compactAppearance = appearance
        // Scroll edge appearance (when content scrolls to edge)
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        // Background visibility - ensure it's not transparent
        UINavigationBar.appearance().isTranslucent = false
        
        // Make sure the navigation bar is never automatically hidden
        UINavigationBar.appearance().prefersLargeTitles = false
        UINavigationBar.appearance().isHidden = false
    }
    
    /// Sets up the message syncing between ChatManager and MultipeerService
    private func setupMessageSync() {
        // Set up chat manager notification subscription
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ChatMessageAdded"),
            object: nil,
            queue: .main
        ) { [self] notification in
            if let message = notification.object as? ChatMessage {
                // Send new message to connected peers by passing the individual properties
                multipeerService.syncAppMessage(
                    id: message.id,
                    content: message.content,
                    timestamp: message.timestamp,
                    isUser: message.isUser,
                    isComplete: message.isComplete
                )
            }
        }
        
        // Set up incoming message handling
        multipeerService.syncWithChatManager = { [weak chatManager] messageArrays in
            guard let chatManager = chatManager else { return }
            
            Task { @MainActor in
                // Add each message to the chat manager if it doesn't already exist
                for messageArray in messageArrays {
                    // Each array contains [id, content, timestamp, isUser, isComplete]
                    if messageArray.count >= 5,
                       let id = messageArray[0] as? UUID,
                       let content = messageArray[1] as? String,
                       let timestamp = messageArray[2] as? Date,
                       let isUser = messageArray[3] as? Bool,
                       let isComplete = messageArray[4] as? Bool {
                        
                        // Create app ChatMessage from extracted components
                        let appMessage = ChatMessage(
                            id: id,
                            content: content,
                            timestamp: timestamp,
                            isUser: isUser,
                            isComplete: isComplete
                        )
                        
                        // Check if message already exists
                        if !chatManager.messages.contains(where: { $0.id == id }) {
                            // Add message to chat manager without triggering notification
                            // (to prevent echo/loop between devices)
                            if isUser {
                                chatManager.addReceivedUserMessage(message: appMessage)
                            } else {
                                chatManager.addReceivedAssistantMessage(message: appMessage)
                            }
                        }
                    } else {
                        print("⚠️ Received malformed message array: \(messageArray)")
                    }
                }
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
                    .environmentObject(chatManager)
                    .environmentObject(eventKitManager)
                    .environmentObject(memoryManager)
                    .environmentObject(locationManager)
                    .environmentObject(themeManager)
                    .environmentObject(speechManager)
                    .environmentObject(multipeerService)
                    .onAppear {
                        // Configure UIKit appearance - now safe to use StateObjects
                        configureUIKitAppearance()
                        
                        // Request permissions when app launches
                        eventKitManager.requestAccess()
                        
                        // Request location permissions if feature is enabled
                        if enableLocationAwareness {
                            locationManager.requestAccess()
                        }
                        
                        // Connect the managers to the ChatManager
                        chatManager.setEventKitManager(eventKitManager)
                        chatManager.setLocationManager(locationManager)
                        
                        // Set up message sync between ChatManager and MultipeerService
                        setupMessageSync()
                        
                        // Debug: Verify last session time
                        print("⏱️ ADHDCoachApp.body.onAppear - Checking last session time")
                        if let lastSessionTime = UserDefaults.standard.object(forKey: "last_app_session_time") as? TimeInterval {
                            let lastTime = Date(timeIntervalSince1970: lastSessionTime)
                            let timeSinceLastSession = Date().timeIntervalSince(lastTime)
                            print("⏱️ ADHDCoachApp.body.onAppear - Last session time: \(lastTime)")
                            print("⏱️ ADHDCoachApp.body.onAppear - Time since last session: \(timeSinceLastSession) seconds")
                        } else {
                            print("⏱️ ADHDCoachApp.body.onAppear - No previous session time found in UserDefaults")
                        }
                    }
                    .onChange(of: colorScheme) { _, _ in
                        themeManager.setTheme(themeManager.currentTheme)
                    }
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .environmentObject(chatManager)
                    .environmentObject(locationManager)
                    .environmentObject(themeManager)
                    .environmentObject(speechManager)
                    .onAppear {
                        // Configure UIKit appearance - now safe to use StateObjects
                        configureUIKitAppearance()
                    }
                    .onChange(of: colorScheme) { _, _ in
                        themeManager.setTheme(themeManager.currentTheme)
                    }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            print("⏱️ App scene phase changed to: \(newPhase)")
            
            if newPhase == .background {
                // Update the last session time when app goes to background
                // This ensures we have an accurate timestamp for the automatic messages feature
                let timestamp = Date().timeIntervalSince1970
                let timeDate = Date(timeIntervalSince1970: timestamp)
                UserDefaults.standard.set(timestamp, forKey: "last_app_session_time")
                UserDefaults.standard.synchronize()
                print("⏱️ App entered background - updated session timestamp: \(timeDate)")
                
                // Notify MultipeerService of background state
                multipeerService.handleAppDidEnterBackground()
                
                // Save cache performance stats to ensure they persist when app closes
                CachePerformanceTracker.shared.saveStatsToUserDefaults()
                print("🧠 App entered background - saved cache performance stats")
            } else if newPhase == .active {
                print("⏱️ App becoming active")
                
                // Notify MultipeerService of active state
                multipeerService.handleAppDidBecomeActive()
                
                // Set theme when app becomes active
                self.themeManager.setTheme(self.themeManager.currentTheme)
                
                // Ensure navigation bar appearance is preserved when app becomes active
                configureUIKitAppearance()
                
                // Force navigation bar to be visible by modifying UINavigationBar global appearance
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    UINavigationBar.appearance().isHidden = false
                    
                    // Also try to find and make visible any existing navigation controller
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first,
                       let rootViewController = window.rootViewController {
                        
                        // Find navigation controller in view hierarchy
                        func findNavigationController(in viewController: UIViewController) -> UINavigationController? {
                            if let nav = viewController as? UINavigationController {
                                return nav
                            }
                            
                            for child in viewController.children {
                                if let navController = findNavigationController(in: child) {
                                    return navController
                                }
                            }
                            
                            return nil
                        }
                        
                        // Find and ensure navigation bar is visible
                        if let navigationController = findNavigationController(in: rootViewController) {
                            navigationController.setNavigationBarHidden(false, animated: false)
                        }
                    }
                }
                
                // Check if we have a last session time
                if let lastSessionTime = UserDefaults.standard.object(forKey: "last_app_session_time") as? TimeInterval {
                    let lastTime = Date(timeIntervalSince1970: lastSessionTime)
                    let timeSinceLastSession = Date().timeIntervalSince(lastTime)
                    print("⏱️ Last background time: \(lastTime)")
                    print("⏱️ Time since last background: \(timeSinceLastSession) seconds")
                    
                    // Check if the app has been in background for at least 5 minutes
                    if timeSinceLastSession >= 300 { // 300 seconds = 5 minutes
                        print("⏱️ App-level - Background time was >= 5 minutes, checking for automatic message")
                        
                        // Only run this if the user has completed onboarding
                        if hasCompletedOnboarding {
                            print("⏱️ App-level - User has completed onboarding, starting automatic message task")
                            
                            // Launch a task to check for automatic messages directly from the app level
                            Task {
                                print("⏱️ App-level - Starting direct automatic message check at \(Date())")
                                let _ = await memoryManager.readMemory()
                                
                                // Update location if enabled
                                if enableLocationAwareness && locationManager.locationAccessGranted {
                                    locationManager.startUpdatingLocation()
                                    print("📍 Location updates started - Location awareness is enabled")
                                } else if enableLocationAwareness && !locationManager.locationAccessGranted {
                                    print("📍 Location permission denied but location awareness is enabled")
                                    locationManager.requestAccess()
                                } else {
                                    print("📍 Location updates not started - Location awareness is disabled")
                                }
                                
                                await chatManager.checkAndSendAutomaticMessage()
                                print("⏱️ App-level - Completed automatic message check at \(Date())")
                            }
                        } else {
                            print("⏱️ App-level - User has not completed onboarding, skipping automatic message")
                        }
                    } else {
                        print("⏱️ App-level - Background time was < 5 minutes, NOT checking for automatic message")
                    }
                } else {
                    print("⏱️ No previous background time found in UserDefaults")
                }
            }
        }
    }
}
