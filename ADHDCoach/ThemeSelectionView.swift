import SwiftUI
import UIKit

struct ThemeSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedThemeId: String
    @State private var refreshID = UUID()
    
    init() {
        _selectedThemeId = State(initialValue: UserDefaults.standard.string(forKey: "selected_theme_id") ?? "pink")
    }
    
    // Method to force keyboard and accessory dismissal
    private func forceKeyboardDismissal() {
        // Dismiss any active keyboard
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        // Ensure keyboard accessory controller is deactivated
        if let controller = KeyboardAccessoryController.sharedInstance {
            controller.deactivateTextField()
        }
        
        // Notify the keyboard controller to dismiss
        NotificationCenter.default.post(name: NSNotification.Name("DismissKeyboardNotification"), object: nil)
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Theme.allThemes) { theme in
                        Button(action: {
                            // Force keyboard dismissal before changing theme
                            forceKeyboardDismissal()
                            
                            // Apply theme
                            selectedThemeId = theme.id
                            themeManager.setTheme(theme)
                            
                            // Post notification that theme changed
                            NotificationCenter.default.post(name: NSNotification.Name("ThemeDidChangeNotification"), object: nil)
                            
                            // Generate new ID to force SwiftUI view refresh
                            refreshID = UUID()
                        }) {
                            HStack {
                                Circle()
                                    .fill(colorScheme == .dark ? theme.darkModeAccentColor : theme.accentColor)
                                    .frame(width: 24, height: 24)
                                
                                Text(theme.name)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                if selectedThemeId == theme.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(themeManager.accentColor(for: colorScheme))
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .onAppear {
                // Force keyboard dismissal when view appears
                forceKeyboardDismissal()
            }
            .navigationTitle("Select Theme")
            .navigationBarTitleDisplayMode(.inline)
            .tint(themeManager.accentColor(for: colorScheme))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        // Force keyboard dismissal before returning
                        forceKeyboardDismissal()
                        dismiss()
                    }
                }
            }
        }
        // This forces SwiftUI to completely recreate the view when the theme changes
        .id(refreshID)
        // Apply accent color at the root level
        .accentColor(themeManager.accentColor(for: colorScheme))
        // Dismiss keyboard when view disappears
        .onDisappear {
            forceKeyboardDismissal()
        }
    }
}

#Preview {
    ThemeSelectionView()
        .environmentObject(ThemeManager())
}
