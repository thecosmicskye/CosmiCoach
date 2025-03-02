import SwiftUI

extension Color {
    static var dynamicAccent: Color {
        Color("AccentColor")
    }
}

struct ThemeColorKey: EnvironmentKey {
    static let defaultValue: Color = .accentColor
}

extension EnvironmentValues {
    var themeColor: Color {
        get { self[ThemeColorKey.self] }
        set { self[ThemeColorKey.self] = newValue }
    }
}

extension View {
    func themeColor(_ color: Color) -> some View {
        environment(\.themeColor, color)
    }
}
