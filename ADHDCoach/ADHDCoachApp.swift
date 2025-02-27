import SwiftUI

@main
struct ADHDCoachApp: App {
    @StateObject private var chatManager = ChatManager()
    @StateObject private var eventKitManager = EventKitManager()
    @StateObject private var memoryManager = MemoryManager()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    // Track when the app enters background to update session time
    @Environment(\.scenePhase) private var scenePhase
    
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
    }
    
    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
                    .environmentObject(chatManager)
                    .environmentObject(eventKitManager)
                    .environmentObject(memoryManager)
                    .onAppear {
                        // Request permissions when app launches
                        eventKitManager.requestAccess()
                        
                        // Connect the EventKitManager to the ChatManager
                        chatManager.setEventKitManager(eventKitManager)
                        
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
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .environmentObject(chatManager)
            }
        }
        .onChange(of: scenePhase) { newPhase in
            let oldPhase = scenePhase
            print("⏱️ App scene phase changed: \(oldPhase) -> \(newPhase)")
            
            if newPhase == .background {
                // Update the last session time when app goes to background
                // This ensures we have an accurate timestamp for the automatic messages feature
                let timestamp = Date().timeIntervalSince1970
                let timeDate = Date(timeIntervalSince1970: timestamp)
                UserDefaults.standard.set(timestamp, forKey: "last_app_session_time")
                UserDefaults.standard.synchronize()
                print("⏱️ App entered background - updated session timestamp: \(timeDate)")
            } else if newPhase == .active {
                print("⏱️ App becoming active")
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
                                await memoryManager.loadMemory()
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
