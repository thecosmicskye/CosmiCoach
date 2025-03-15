import SwiftUI
import Markdown

/// A property wrapper that delays initialization until the value is first accessed
@propertyWrapper
struct LazyProcessed<Value> {
    private var initializer: () -> Value
    private var storage: Value?
    
    init(wrappedValue: @autoclosure @escaping () -> Value) {
        self.initializer = wrappedValue
    }
    
    var wrappedValue: Value {
        mutating get {
            if storage == nil {
                storage = initializer()
            }
            return storage!
        }
        set {
            storage = newValue
        }
    }
}

/// A shared cache for processed markdown to avoid reprocessing the same content
class MarkdownCache {
    static let shared = MarkdownCache()
    private var cache: [String: AttributedString] = [:]
    private var processingQueue = DispatchQueue(label: "com.cosmiccoach.markdown.cache", attributes: .concurrent)
    
    func getAttributedString(for markdown: String, processor: MarkdownProcessor) async -> AttributedString {
        // Check cache first
        if let cached = getFromCache(markdown) {
            return cached
        }
        
        // Process and cache
        let processed = await processor.processMarkdown(markdown)
        addToCache(markdown, attributedString: processed)
        return processed
    }
    
    func getFromCache(_ key: String) -> AttributedString? {
        var result: AttributedString?
        processingQueue.sync {
            result = cache[key]
        }
        return result
    }
    
    private func addToCache(_ key: String, attributedString: AttributedString) {
        processingQueue.async(flags: .barrier) {
            self.cache[key] = attributedString
        }
    }
    
    func clearCache() {
        processingQueue.async(flags: .barrier) {
            self.cache.removeAll()
        }
    }
}

// Rename our view to avoid conflict with Markdown.Text
struct MarkdownTextView: View {
    let markdown: String
    
    private let markdownProcessor = MarkdownProcessor()
    @State private var attributedString: AttributedString = AttributedString("")
    @State private var processingTask: Task<Void, Never>? = nil
    @State private var retryCount: Int = 0
    @State private var lastProcessedMarkdown: String = ""
    @State private var isLoading: Bool = true
    
    var body: some View {
        ZStack {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(0.7)
                
                Text(markdown)
                    .opacity(0.01) // Almost invisible but preserves layout
            }
            
            Text(attributedString)
                .opacity(isLoading ? 0 : 1)
        }
        .onAppear {
            processMarkdown()
        }
        .onChange(of: markdown) { _ in
            // Cancel previous task if it's still running
            processingTask?.cancel()
            isLoading = true
            processMarkdown()
        }
        .onDisappear {
            // Clean up task if view disappears
            processingTask?.cancel()
        }
        // Adding an id based on markdown length ensures the view refreshes
        // when content changes, even if SwiftUI doesn't detect it
        .id("markdown-\(markdown.count)-\(retryCount)")
    }
    
    private func processMarkdown() {
        // Save the markdown we're processing
        let currentMarkdown = markdown
        
        // Skip processing if the content is identical and we already processed it
        if currentMarkdown == lastProcessedMarkdown && !attributedString.characters.isEmpty {
            isLoading = false
            return
        }
        
        // Create a new task and store the reference
        processingTask = Task {
            do {
                // Check for cancellation before processing
                try Task.checkCancellation()
                
                // Use the cache to avoid reprocessing
                let processed = await MarkdownCache.shared.getAttributedString(
                    for: currentMarkdown,
                    processor: markdownProcessor
                )
                
                // Check for cancellation before updating UI
                try Task.checkCancellation()
                
                // Short delay to allow UI to finish layout calculations
                try await Task.sleep(nanoseconds: 50_000_000) // 50ms
                
                // Update the UI on the main thread
                await MainActor.run {
                    self.attributedString = processed
                    self.lastProcessedMarkdown = currentMarkdown
                    self.isLoading = false
                    
                    // If processing produced empty or minimal results for non-empty markdown,
                    // retry up to 3 times with a delay
                    if currentMarkdown.count > 10 && processed.characters.count < min(10, currentMarkdown.count/2) && retryCount < 3 {
                        retryCount += 1
                        print("Markdown processing produced minimal results, retrying (\(retryCount)/3)")
                        
                        // Schedule a retry after a short delay
                        Task {
                            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                            if !Task.isCancelled {
                                isLoading = true
                                processMarkdown()
                            }
                        }
                    } else {
                        retryCount = 0
                    }
                }
            } catch {
                // Task was cancelled or failed
                print("Markdown processing cancelled or failed: \(error)")
                
                // If we failed and haven't exceeded retry limit, try again
                if retryCount < 3 {
                    await MainActor.run {
                        retryCount += 1
                        print("Retrying after failure (\(retryCount)/3)")
                    }
                    
                    // Schedule a retry after a delay
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    if !Task.isCancelled {
                        processMarkdown()
                    }
                } else {
                    // If all retries failed, just show the plain text
                    await MainActor.run {
                        self.attributedString = AttributedString(currentMarkdown)
                        self.isLoading = false
                    }
                }
            }
        }
    }
}

// Processes markdown on a background thread
class MarkdownProcessor {
    func processMarkdown(_ text: String) async -> AttributedString {
        // This will run on a background thread thanks to the async function
        do {
            // Add error handling to prevent crashes
            let document = Document(parsing: text)
            return createAttributedString(from: document)
        } catch {
            print("Error parsing markdown: \(error)")
            // Return the plain text if markdown parsing fails
            return AttributedString(text)
        }
    }
    
    private func createAttributedString(from document: Document) -> AttributedString {
        // Convert the Markdown document to NSAttributedString
        var attributedString = AttributedString("")
        
        do {
            for child in document.children {
                attributedString.append(renderBlock(child))
            }
            return attributedString
        } catch {
            print("Error creating attributed string: \(error)")
            // Return a simple attributed string with the document's plain text
            return AttributedString(document.format())
        }
    }
    
    private func renderBlock(_ block: Markup) -> AttributedString {
        do {
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
        } catch {
            print("Error rendering block: \(error)")
            // Return a simple block with the content
            return AttributedString(block.format() + "\n\n")
        }
    }
    
    private func renderInline(_ inline: Markup) -> AttributedString {
        do {
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
        } catch {
            print("Error rendering inline: \(error)")
            // Return a simple string with the inline content
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
