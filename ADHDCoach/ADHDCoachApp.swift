import SwiftUI

@main
struct ADHDCoachApp: App {
    @StateObject private var chatManager = ChatManager()
    @StateObject private var eventKitManager = EventKitManager()
    @StateObject private var memoryManager = MemoryManager()
    
    var body: some Scene {
        WindowGroup {
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
        }
    }
}
