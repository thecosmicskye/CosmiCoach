import SwiftUI

struct ThemeSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedThemeId: String
    @State private var refreshID = UUID()
    
    init() {
        _selectedThemeId = State(initialValue: UserDefaults.standard.string(forKey: "selected_theme_id") ?? "pink")
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Theme.allThemes) { theme in
                        Button(action: {
                            selectedThemeId = theme.id
                            themeManager.setTheme(theme)
                            
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
            .navigationTitle("Select Theme")
            .navigationBarTitleDisplayMode(.inline)
            .tint(themeManager.accentColor(for: colorScheme))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        // This forces SwiftUI to completely recreate the view when the theme changes
        .id(refreshID)
        // Apply accent color at the root level
        .accentColor(themeManager.accentColor(for: colorScheme))
    }
}

#Preview {
    ThemeSelectionView()
        .environmentObject(ThemeManager())
}
