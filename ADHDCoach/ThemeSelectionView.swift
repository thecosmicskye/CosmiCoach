import SwiftUI

struct ThemeSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedThemeId: String
    
    init(themeManager: ThemeManager) {
        self.themeManager = themeManager
        // Initialize with the current theme
        _selectedThemeId = State(initialValue: themeManager.currentTheme.id)
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Theme.allThemes) { theme in
                        Button(action: {
                            selectedThemeId = theme.id
                            themeManager.setTheme(theme)
                            
                            // Also save to UserDefaults directly to ensure it persists
                            UserDefaults.standard.set(theme.id, forKey: "selected_theme_id")
                            UserDefaults.standard.synchronize()
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
                        .foregroundColor(themeManager.accentColor(for: colorScheme))
                    }
                }
            }
            .navigationTitle("Select Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(colorScheme)
            .tint(themeManager.accentColor(for: colorScheme))
            .onAppear {
                // Force update the theme when the view appears
                themeManager.setTheme(themeManager.currentTheme)
                
                // Force update the navigation bar appearance
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    themeManager.setTheme(themeManager.currentTheme)
                }
            }
            .onChange(of: selectedThemeId) { _, _ in
                // Force update the navigation bar appearance when the theme changes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    themeManager.setTheme(themeManager.currentTheme)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(themeManager.accentColor(for: colorScheme))
                }
            }
        }
    }
}

#Preview {
    ThemeSelectionView(themeManager: ThemeManager())
}
