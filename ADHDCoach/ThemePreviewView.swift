import SwiftUI

struct ThemePreviewView: View {
    let theme: Theme
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Theme Preview")
                .font(.headline)
            
            HStack(spacing: 16) {
                // User message bubble
                Text("Hello!")
                    .padding(10)
                    .background(colorScheme == .dark ? theme.darkModeAccentColor : theme.accentColor)
                    .foregroundColor(colorScheme == .light ? .white : .black)
                    .cornerRadius(16)
                
                // Send button
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(colorScheme == .dark ? theme.darkModeAccentColor : theme.accentColor)
            }
            
            // Button example
            Button(action: {}) {
                Text("Button Example")
                    .foregroundColor(colorScheme == .light ? .white : .black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(colorScheme == .dark ? theme.darkModeAccentColor : theme.accentColor)
                    .cornerRadius(8)
            }
            .disabled(true)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

#Preview {
    VStack(spacing: 20) {
        ThemePreviewView(theme: Theme.pink)
        ThemePreviewView(theme: Theme.blue)
        ThemePreviewView(theme: Theme.purple)
    }
    .padding()
}
