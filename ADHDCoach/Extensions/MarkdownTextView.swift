import SwiftUI
import Markdown

// Rename our view to avoid conflict with Markdown.Text
struct MarkdownTextView: View {
    let markdown: String
    
    private let markdownProcessor = MarkdownProcessor()
    @State private var attributedString: AttributedString = AttributedString("")
    
    var body: some View {
        Text(attributedString)
            .onAppear {
                processMarkdown()
            }
            .onChange(of: markdown) { _ in
                processMarkdown()
            }
    }
    
    private func processMarkdown() {
        Task {
            // Process markdown on a background thread
            let processed = await markdownProcessor.processMarkdown(markdown)
            // Update the UI on the main thread
            await MainActor.run {
                self.attributedString = processed
            }
        }
    }
}

// Processes markdown on a background thread
class MarkdownProcessor {
    func processMarkdown(_ text: String) async -> AttributedString {
        // This will run on a background thread thanks to the async function
        let document = Document(parsing: text)
        return createAttributedString(from: document)
    }
    
    private func createAttributedString(from document: Document) -> AttributedString {
        // Convert the Markdown document to NSAttributedString
        var attributedString = AttributedString("")
        
        for child in document.children {
            attributedString.append(renderBlock(child))
        }
        
        return attributedString
    }
    
    private func renderBlock(_ block: Markup) -> AttributedString {
        switch block {
        case let paragraph as Paragraph:
            var content = AttributedString("")
            for child in paragraph.children {
                content.append(renderInline(child))
            }
            content.append(AttributedString("\n\n"))
            return content
            
        case let heading as Heading:
            var content = AttributedString("")
            for child in heading.children {
                content.append(renderInline(child))
            }
            
            // Set heading level style
            var headingAttributes: AttributeContainer = AttributeContainer()
            switch heading.level {
            case 1:
                headingAttributes.font = .system(size: 28, weight: .bold)
            case 2:
                headingAttributes.font = .system(size: 24, weight: .bold)
            case 3:
                headingAttributes.font = .system(size: 20, weight: .bold)
            case 4:
                headingAttributes.font = .system(size: 18, weight: .semibold)
            case 5:
                headingAttributes.font = .system(size: 16, weight: .semibold)
            case 6:
                headingAttributes.font = .system(size: 14, weight: .semibold)
            default:
                headingAttributes.font = .system(size: 16, weight: .regular)
            }
            
            content.mergeAttributes(headingAttributes)
            content.append(AttributedString("\n\n"))
            return content
            
        case let blockQuote as BlockQuote:
            var content = AttributedString("")
            for child in blockQuote.children {
                content.append(renderBlock(child))
            }
            
            var attributes = AttributeContainer()
            attributes.foregroundColor = .secondary
            attributes.backgroundColor = Color(.systemGray6)
            
            content.mergeAttributes(attributes)
            return content
            
        case let list as UnorderedList:
            var content = AttributedString("")
            for item in list.listItems {
                content.append(AttributedString("• "))
                for child in item.children {
                    content.append(renderBlock(child))
                }
            }
            return content
            
        case let list as OrderedList:
            var content = AttributedString("")
            for (index, item) in list.listItems.enumerated() {
                content.append(AttributedString("\(index + 1). "))
                for child in item.children {
                    content.append(renderBlock(child))
                }
            }
            return content
            
        case let codeBlock as CodeBlock:
            var content = AttributedString(codeBlock.code)
            var attributes = AttributeContainer()
            attributes.font = .system(.body, design: .monospaced)
            attributes.backgroundColor = Color(.systemGray6)
            content.mergeAttributes(attributes)
            content.append(AttributedString("\n\n"))
            return content
            
        case let image as Markdown.Image:
            // We can't directly display images in AttributedString
            // but we can indicate that an image would be here
            let altText = image.plainText
            var content = AttributedString("[Image: \(altText)]")
            var attributes = AttributeContainer()
            attributes.foregroundColor = .blue
            content.mergeAttributes(attributes)
            return content
            
        case let html as HTMLBlock:
            // For HTML blocks, just display them as plain text
            var content = AttributedString(html.rawHTML)
            var attributes = AttributeContainer()
            attributes.font = .system(.body, design: .monospaced)
            content.mergeAttributes(attributes)
            return content
            
        case let thematicBreak as ThematicBreak:
            return AttributedString("---\n\n")
            
        default:
            // Default fallback for other block types
            return AttributedString(block.format() + "\n\n")
        }
    }
    
    private func renderInline(_ inline: Markup) -> AttributedString {
        switch inline {
        case let text as Markdown.Text:
            return AttributedString(text.string)
            
        case let emphasis as Emphasis:
            var content = AttributedString("")
            for child in emphasis.children {
                content.append(renderInline(child))
            }
            
            var attributes = AttributeContainer()
            attributes.font = .italicSystemFont(ofSize: 16)
            content.mergeAttributes(attributes)
            return content
            
        case let strong as Strong:
            var content = AttributedString("")
            for child in strong.children {
                content.append(renderInline(child))
            }
            
            var attributes = AttributeContainer()
            attributes.font = .boldSystemFont(ofSize: 16)
            content.mergeAttributes(attributes)
            return content
            
        case let code as InlineCode:
            var content = AttributedString(code.code)
            var attributes = AttributeContainer()
            attributes.font = .system(.body, design: .monospaced)
            attributes.backgroundColor = Color(.systemGray6)
            content.mergeAttributes(attributes)
            return content
            
        case let link as Markdown.Link:
            var content = AttributedString("")
            for child in link.children {
                content.append(renderInline(child))
            }
            
            var attributes = AttributeContainer()
            attributes.foregroundColor = .blue
            attributes.underlineStyle = .single
            if let url = URL(string: link.destination ?? "") {
                attributes.link = url
            }
            content.mergeAttributes(attributes)
            return content
            
        case let image as Markdown.Image:
            // Simplified image handling
            var content = AttributedString("[Image]")
            var attributes = AttributeContainer()
            attributes.foregroundColor = .blue
            content.mergeAttributes(attributes)
            return content
            
        default:
            // Default fallback
            return AttributedString(inline.format())
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        MarkdownTextView(markdown: """
        # Heading 1
        ## Heading 2
        
        This is a paragraph with **bold** and *italic* text.
        
        * List item 1
        * List item 2
        
        1. Ordered item 1
        2. Ordered item 2
        
        > This is a blockquote
        
        `code snippet`
        
        ```
        func example() {
            print("Hello world")
        }
        ```
        
        [Link to example](https://example.com)
        """)
    }
    .padding()
}
