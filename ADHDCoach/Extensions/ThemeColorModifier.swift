import SwiftUI

struct ThemeColorModifier: ViewModifier {
    @ObservedObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        content
            .accentColor(themeManager.accentColor(for: colorScheme))
            .themeColor(themeManager.accentColor(for: colorScheme))
            .onAppear {
                // Update the global accent color when the view appears
                themeManager.setTheme(themeManager.currentTheme)
            }
            .onChange(of: colorScheme) { _, _ in
                // Update the global accent color when the color scheme changes
                themeManager.setTheme(themeManager.currentTheme)
            }
            .onChange(of: themeManager.currentTheme) { _, _ in
                // Update the global accent color when the theme changes
                themeManager.setTheme(themeManager.currentTheme)
            }
    }
}

extension View {
    func applyThemeColor(themeManager: ThemeManager) -> some View {
        self.modifier(ThemeColorModifier(themeManager: themeManager))
    }
}
