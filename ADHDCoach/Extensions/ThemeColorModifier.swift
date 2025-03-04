import SwiftUI

struct ThemeColorModifier: ViewModifier {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var refreshFlag = false
    
    func body(content: Content) -> some View {
        content
            .accentColor(themeManager.accentColor(for: colorScheme))
            .themeColor(themeManager.accentColor(for: colorScheme))
            .onChange(of: colorScheme) { _ in
                themeManager.setTheme(themeManager.currentTheme)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ThemeDidChangeNotification"))) { _ in
                refreshFlag.toggle()
            }
            .id(refreshFlag)
    }
}

extension View {
    func applyThemeColor() -> some View {
        self.modifier(ThemeColorModifier())
    }
}
