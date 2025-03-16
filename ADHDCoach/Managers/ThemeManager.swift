import SwiftUI

class ThemeManager: ObservableObject {
    // Shared instance for use in places where @EnvironmentObject isn't available
    static let shared = ThemeManager()
    
    @Published var currentTheme: Theme
    @AppStorage("selected_theme_id") private var selectedThemeId: String = "pink"
    
    init() {
        // Load the saved theme or use pink as default
        let savedThemeId = UserDefaults.standard.string(forKey: "selected_theme_id") ?? "pink"
        self.currentTheme = Theme.getThemeById(savedThemeId)
        self.selectedThemeId = savedThemeId
        
        // Update the global accent color
        DispatchQueue.main.async {
            self.updateGlobalAccentColor()
        }
    }
    
    func setTheme(_ theme: Theme) {
        currentTheme = theme
        selectedThemeId = theme.id
        
        // Also save to UserDefaults directly to ensure it persists
        UserDefaults.standard.set(theme.id, forKey: "selected_theme_id")
        UserDefaults.standard.synchronize()
        
        updateGlobalAccentColor()
    }
    
    // Get the current accent color based on color scheme
    func accentColor(for colorScheme: ColorScheme) -> Color {
        return colorScheme == .dark ? currentTheme.darkModeAccentColor : currentTheme.accentColor
    }
    
    private func updateGlobalAccentColor() {
        let isDarkMode = UITraitCollection.current.userInterfaceStyle == .dark
        let tintColor = UIColor(isDarkMode ? currentTheme.darkModeAccentColor : currentTheme.accentColor)
        
        // Set window tint color
        for window in UIApplication.shared.windows {
            window.tintColor = tintColor
        }
        
        // Notify observers
        NotificationCenter.default.post(name: NSNotification.Name("ThemeDidChangeNotification"), object: nil)
    }
}
