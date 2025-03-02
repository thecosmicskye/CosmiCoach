import SwiftUI

struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let accentColor: Color
    let darkModeAccentColor: Color
    
    // Predefined themes
    static let pink = Theme(
        id: "pink",
        name: "Pink",
        accentColor: Color(red: 0.8, green: 0.2, blue: 0.7),
        darkModeAccentColor: Color(red: 0.75, green: 0.3, blue: 0.4)
    )
    
    static let blue = Theme(
        id: "blue",
        name: "Blue",
        accentColor: Color.blue, // Default Apple blue
        darkModeAccentColor: Color.blue.opacity(0.8)
    )
    
    static let purple = Theme(
        id: "purple",
        name: "Purple",
        accentColor: Color(red: 0.5, green: 0.0, blue: 0.8),
        darkModeAccentColor: Color(red: 0.7, green: 0.4, blue: 1.0)
    )
    
    static let green = Theme(
        id: "green",
        name: "Green",
        accentColor: Color(red: 0.0, green: 0.7, blue: 0.4),
        darkModeAccentColor: Color(red: 0.4, green: 0.9, blue: 0.6)
    )
    
    static let orange = Theme(
        id: "orange",
        name: "Orange",
        accentColor: Color(red: 1.0, green: 0.5, blue: 0.0),
        darkModeAccentColor: Color(red: 1.0, green: 0.7, blue: 0.4)
    )
    
    // All available themes
    static let allThemes = [pink, blue, purple, green, orange]
    
    // Get a theme by ID
    static func getThemeById(_ id: String) -> Theme {
        return allThemes.first { $0.id == id } ?? pink
    }
}
