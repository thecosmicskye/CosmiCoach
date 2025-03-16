import SwiftUI

// MARK: - Bullet List Item
struct BulletListItemView: View {
    let content: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Bullet column
            Text("•")
                .fontWeight(.bold)
                .frame(width: 16, alignment: .leading)
            
            // Content column
            MarkdownContentView(content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Numbered List Item
struct NumberedListItemView: View {
    let number: Int
    let content: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Number column
            Text("\(number).")
                .fontWeight(.medium)
                .frame(width: 25, alignment: .leading)
            
            // Content column
            MarkdownContentView(content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Horizontal Line
struct HorizontalLineView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    
    var body: some View {
        Rectangle()
            .fill(themeManager.currentTheme.accentColor.opacity(0.5))
            .frame(height: 1)
            .padding(.vertical, 10)
    }
}

// MARK: - Bullet List
struct BulletListView: View {
    let items: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items.indices, id: \.self) { index in
                BulletListItemView(content: items[index])
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Numbered List
struct NumberedListView: View {
    let items: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items.indices, id: \.self) { index in
                NumberedListItemView(number: index + 1, content: items[index])
            }
        }
        .padding(.vertical, 4)
    }
}

// Helper view for rendering individual markdown content items
struct MarkdownContentView: View {
    let content: String
    
    var body: some View {
        // Process the content with markdown formatting (without list markers)
        Text(try? AttributedString(markdown: content, options: .init(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )) ?? AttributedString(content))
        .textSelection(.enabled)
    }
}