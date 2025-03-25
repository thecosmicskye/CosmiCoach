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
    
    // Custom corner radius modifier that allows specifying which corners to round
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

// Custom shape that creates rounded corners for specific corners
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
