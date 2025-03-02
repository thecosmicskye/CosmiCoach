import SwiftUI

class ThemeManager: ObservableObject {
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
    
    // Update the global accent color
    private func updateGlobalAccentColor() {
        // Set the global accent color
        let isDarkMode = UITraitCollection.current.userInterfaceStyle == .dark
        let tintColor = UIColor(isDarkMode ? currentTheme.darkModeAccentColor : currentTheme.accentColor)
        
        // Reset any existing appearance settings
        let defaultAppearance = UINavigationBarAppearance()
        defaultAppearance.configureWithDefaultBackground()
        
        // Create a new appearance
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        
        // Configure back button appearance
        let backImage = UIImage(systemName: "chevron.left")?.withTintColor(tintColor, renderingMode: .alwaysOriginal)
        appearance.setBackIndicatorImage(backImage, transitionMaskImage: backImage)
        
        // Apply to UIKit elements
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().tintColor = tintColor
        
        // Apply to UIBarButtonItem
        UIBarButtonItem.appearance().tintColor = tintColor
        
        // Apply to specific UIBarButtonItem types
        UIBarButtonItem.appearance(whenContainedInInstancesOf: [UINavigationBar.self]).tintColor = tintColor
        
        // Force update all windows
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene {
                for window in windowScene.windows {
                    window.tintColor = tintColor
                    for view in window.subviews {
                        view.setNeedsLayout()
                        view.setNeedsDisplay()
                    }
                }
            }
        }
    }
}
