import SwiftUI

@main
struct ADHDCoachApp: App {
    @StateObject private var chatManager = ChatManager()
    @StateObject private var eventKitManager = EventKitManager()
    @StateObject private var memoryManager = MemoryManager()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var themeManager = ThemeManager()
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
        
        // Configure UIKit appearance for UINavigationBar
        // This is needed because SwiftUI's NavigationView/NavigationStack uses UIKit underneath
        configureUIKitAppearance()
    }
    
    private func configureUIKitAppearance() {
        themeManager.setTheme(themeManager.currentTheme)
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
                    .onAppear {
                        // Request permissions when app launches
                        eventKitManager.requestAccess()
                        
                        // Request location permissions if feature is enabled
                        if enableLocationAwareness {
                            locationManager.requestAccess()
                        }
                        
                        // Connect the managers to the ChatManager
                        chatManager.setEventKitManager(eventKitManager)
                        chatManager.setLocationManager(locationManager)
                        
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
                    .onChange(of: colorScheme) { _, _ in
                        themeManager.setTheme(themeManager.currentTheme)
                    }
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            print("⏱️ App scene phase changed: \(oldPhase) -> \(newPhase)")
            
            if newPhase == .background {
                // Update the last session time when app goes to background
                // This ensures we have an accurate timestamp for the automatic messages feature
                let timestamp = Date().timeIntervalSince1970
                let timeDate = Date(timeIntervalSince1970: timestamp)
                UserDefaults.standard.set(timestamp, forKey: "last_app_session_time")
                UserDefaults.standard.synchronize()
                print("⏱️ App entered background - updated session timestamp: \(timeDate)")
                
                // Save cache performance stats to ensure they persist when app closes
                CachePerformanceTracker.shared.saveStatsToUserDefaults()
                print("🧠 App entered background - saved cache performance stats")
            } else if newPhase == .active {
                print("⏱️ App becoming active")
                
                // Set theme when app becomes active
                self.themeManager.setTheme(self.themeManager.currentTheme)
                
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
