import SwiftUI

@main
struct ADHDCoachApp: App {
    @StateObject private var chatManager = ChatManager()
    @StateObject private var eventKitManager = EventKitManager()
    @StateObject private var memoryManager = MemoryManager()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    // Track when the app enters background to update session time
    @Environment(\.scenePhase) private var scenePhase
    
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
                    }
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .environmentObject(chatManager)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                // Update the last session time when app goes to background
                // This ensures we have an accurate timestamp for the automatic messages feature
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "last_app_session_time")
                UserDefaults.standard.synchronize()
                print("App entered background - updated session timestamp")
            }
        }
    }
}
