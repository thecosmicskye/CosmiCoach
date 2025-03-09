import SwiftUI

struct MemoryContentView: View {
    @ObservedObject var memoryManager: MemoryManager
    var chatManager: ChatManager
    @Binding var showingResetConfirmation: Bool
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeManager: ThemeManager
    
    var body: some View {
        List {
            ForEach(MemoryCategory.allCases, id: \.self) { category in
                if let memories = getMemoriesForCategory(category), !memories.isEmpty {
                    Section(header: Text(category.rawValue)) {
                        ForEach(memories) { memory in
                            Text(memory.content)
                                .textSelection(.enabled)
                                .padding(.vertical, 2)
                        }
                    }
                }
            }
            
            Section {
                Text("Last updated: \(Date().formatted(date: .abbreviated, time: .standard))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            Task {
                // Ensure we're getting the latest memory content from disk
                let _ = await memoryManager.readMemory()
                
                // Make sure the API service also has the latest memory content
                await chatManager.refreshContextData()
                print("📝 View Memory: Refreshed context data in API service")
            }
        }
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Reset", role: .destructive) {
                    showingResetConfirmation = true
                }
                .foregroundColor(.red)
            }
        }
    }
    
    private func getMemoriesForCategory(_ category: MemoryCategory) -> [MemoryItem]? {
        let memories = memoryManager.memories.filter { $0.category == category }
        
        if memories.isEmpty {
            return nil
        }
        
        // Sort by timestamp (newer first)
        return memories.sorted { $0.timestamp > $1.timestamp }
    }
    
}

#Preview {
    NavigationStack {
        MemoryContentView(
            memoryManager: MemoryManager(),
            chatManager: ChatManager(),
            showingResetConfirmation: .constant(false)
        )
        .environmentObject(ThemeManager())
    }
}