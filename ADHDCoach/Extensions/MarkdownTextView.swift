import SwiftUI
import Markdown

// Forward declaration of MarkdownProcessor
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
    
    // Cache stats for logging/debugging
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0
    
    // For memory management
    private let maxMemoryCacheSize = 200 // Maximum number of entries to keep in memory
    private var cacheAccessLog: [String] = [] // Track access order for LRU eviction
    
    // Persistent storage for rendered markdown
    private let cacheDirectoryURL: URL? = {
        do {
            let fileManager = FileManager.default
            let cachesDirectory = try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let cacheDirectory = cachesDirectory.appendingPathComponent("MarkdownCache", isDirectory: true)
            
            if !fileManager.fileExists(atPath: cacheDirectory.path) {
                try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            }
            
            return cacheDirectory
        } catch {
            print("Failed to create cache directory: \(error)")
            return nil
        }
    }()
    
    private init() {
        loadCacheFromDisk()
        
        // Register for memory warnings to clear in-memory cache if needed
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleMemoryWarning() {
        print("MarkdownCache: Received memory warning, clearing in-memory cache")
        processingQueue.async(flags: .barrier) {
            // Don't clear disk cache, just the memory cache
            self.cache.removeAll()
            self.cacheAccessLog.removeAll()
        }
    }
    
    func getAttributedString(for markdown: String, processor: MarkdownProcessor) async -> AttributedString {
        // Generate a unique key for the markdown content
        let key = generateCacheKey(for: markdown)
        
        // Check in-memory cache first
        if let cached = getFromCache(key) {
            cacheHits += 1
            updateCacheAccessOrder(key)
            return cached
        }
        
        cacheMisses += 1
        
        // Try to load from disk if not in memory
        if let fromDisk = loadAttributedStringFromDisk(key: key) {
            // Add to memory cache
            addToCache(key, attributedString: fromDisk)
            return fromDisk
        }
        
        // Process, cache, and persist
        let processed = await processor.processMarkdown(markdown)
        addToCache(key, attributedString: processed)
        saveAttributedStringToDisk(key: key, attributedString: processed)
        
        if (cacheMisses + cacheHits) % 100 == 0 {
            // Log cache efficiency periodically
            let hitRate = Double(cacheHits) / Double(cacheHits + cacheMisses) * 100
            print("MarkdownCache: Hit rate: \(String(format: "%.1f", hitRate))% (\(cacheHits) hits, \(cacheMisses) misses)")
        }
        
        return processed
    }
    
    // Generate a deterministic cache key from markdown content
    private func generateCacheKey(for markdown: String) -> String {
        let hash = markdown.data(using: .utf8)?.hashValue ?? markdown.hashValue
        return "markdown-\(hash)"
    }
    
    // Track LRU for cache eviction
    private func updateCacheAccessOrder(_ key: String) {
        processingQueue.async(flags: .barrier) {
            // Remove key from current position (if exists)
            if let index = self.cacheAccessLog.firstIndex(of: key) {
                self.cacheAccessLog.remove(at: index)
            }
            
            // Add to the end (most recently used)
            self.cacheAccessLog.append(key)
        }
    }
    
    // Evict least recently used items when cache gets too big
    private func evictCacheItemsIfNeeded() {
        processingQueue.async(flags: .barrier) {
            // If we're over capacity, remove oldest items
            while self.cache.count > self.maxMemoryCacheSize && !self.cacheAccessLog.isEmpty {
                // Get the least recently used key
                if let oldestKey = self.cacheAccessLog.first {
                    self.cache.removeValue(forKey: oldestKey)
                    self.cacheAccessLog.removeFirst()
                }
            }
        }
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
            self.updateCacheAccessOrder(key)
            
            // Check if we need to evict items
            if self.cache.count > self.maxMemoryCacheSize {
                self.evictCacheItemsIfNeeded()
            }
        }
    }
    
    // Loads an AttributedString from disk if available
    private func loadAttributedStringFromDisk(key: String) -> AttributedString? {
        guard let cacheDirectoryURL = cacheDirectoryURL else { return nil }
        
        let fileURL = cacheDirectoryURL.appendingPathComponent("\(key).data")
        
        do {
            // Check if file exists
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let data = try Data(contentsOf: fileURL)
                if let nsAttributedString = try NSKeyedUnarchiver.unarchivedObject(
                    ofClass: NSAttributedString.self,
                    from: data
                ) {
                    return AttributedString(nsAttributedString)
                }
            }
        } catch {
            print("Failed to load AttributedString from disk: \(error)")
        }
        
        return nil
    }
    
    func clearCache() {
        processingQueue.async(flags: .barrier) {
            self.cache.removeAll()
            self.cacheAccessLog.removeAll()
            self.cacheHits = 0
            self.cacheMisses = 0
            self.clearDiskCache()
        }
    }
    
    // Save AttributedString to disk
    private func saveAttributedStringToDisk(key: String, attributedString: AttributedString) {
        guard let cacheDirectoryURL = cacheDirectoryURL else { return }
        
        processingQueue.async(flags: .barrier) {
            do {
                let fileURL = cacheDirectoryURL.appendingPathComponent("\(key).data")
                
                // Convert AttributedString to NSAttributedString for serialization
                let nsAttributedString = try NSAttributedString(attributedString)
                
                // Archive the NSAttributedString
                let data = try NSKeyedArchiver.archivedData(withRootObject: nsAttributedString, requiringSecureCoding: true)
                
                // Write to disk
                try data.write(to: fileURL)
            } catch {
                print("Failed to save AttributedString to disk: \(error)")
            }
        }
    }
    
    // Load cached AttributedStrings from disk
    private func loadCacheFromDisk() {
        guard let cacheDirectoryURL = cacheDirectoryURL else { return }
        
        processingQueue.async {
            do {
                let fileManager = FileManager.default
                let fileURLs = try fileManager.contentsOfDirectory(at: cacheDirectoryURL, includingPropertiesForKeys: nil)
                
                for fileURL in fileURLs {
                    if fileURL.pathExtension == "data" {
                        do {
                            let data = try Data(contentsOf: fileURL)
                            if let nsAttributedString = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: data) {
                                // Convert NSAttributedString back to AttributedString
                                let attributedString = AttributedString(nsAttributedString)
                                
                                // Extract key from filename
                                let filename = fileURL.deletingPathExtension().lastPathComponent
                                
                                // Add to in-memory cache
                                self.addToCache(filename, attributedString: attributedString)
                            }
                        } catch {
                            print("Failed to load AttributedString from \(fileURL.lastPathComponent): \(error)")
                        }
                    }
                }
            } catch {
                print("Failed to read cache directory contents: \(error)")
            }
        }
    }
    
    // Clear all cached files from disk
    private func clearDiskCache() {
        guard let cacheDirectoryURL = cacheDirectoryURL else { return }
        
        do {
            let fileManager = FileManager.default
            let fileURLs = try fileManager.contentsOfDirectory(at: cacheDirectoryURL, includingPropertiesForKeys: nil)
            
            for fileURL in fileURLs {
                try fileManager.removeItem(at: fileURL)
            }
        } catch {
            print("Failed to clear disk cache: \(error)")
        }
    }
}

// Rename our view to avoid conflict with Markdown.Text
struct MarkdownTextView: View {
    let markdown: String
    // Default isComplete to false, MessageBubbleView can pass this from the message
    var isComplete: Bool = false
    
    // By adding the @EnvironmentObject here but not reinitializing it,
    // we ensure the view is stable across re-renders
    @EnvironmentObject private var themeManager: ThemeManager
    
    var body: some View {
        CachedMarkdownContent(markdown: markdown, isCompleteMessage: isComplete)
            // This helps with layout stability
            .animation(nil, value: markdown.count)
    }
}

// Global dictionary for storing rendered AttributedStrings (only for completed messages)
fileprivate var globalRenderedContent: [String: AttributedString] = [:]
fileprivate let renderingQueue = DispatchQueue(label: "com.cosmiccoach.markdown.rendering", attributes: .concurrent)

// A separate component that handles the actual markdown rendering and caching
struct CachedMarkdownContent: View {
    let markdown: String
    // Check if this is a complete message or still streaming
    let isCompleteMessage: Bool
    
    // Use StateObject to maintain view state
    @StateObject private var viewModel = MarkdownViewModel()
    
    // Access global rendered content
    @State private var renderedContent: AttributedString?
    @State private var isLoading: Bool = true
    @State private var lastProcessedContent: String = ""
    
    // Fetch from global cache
    private func fetchGlobalContent() -> AttributedString? {
        // Only use cache for complete messages
        guard isCompleteMessage else { return nil }
        
        var result: AttributedString?
        renderingQueue.sync {
            result = globalRenderedContent[markdown]
        }
        return result
    }
    
    // Store to global cache
    private func storeGlobalContent(_ content: AttributedString) {
        // Only cache complete messages
        guard isCompleteMessage else { return }
        
        renderingQueue.async(flags: .barrier) {
            globalRenderedContent[markdown] = content
        }
    }
    
    var body: some View {
        Group {
            // Just render the content directly without ZStack loading states
            // This prevents UI blocking while ensuring content is visible immediately
            if let cachedContent = renderedContent {
                // Use cached content if we have it
                Text(cachedContent)
            } else if !viewModel.attributedString.characters.isEmpty {
                // Use processed content if we have it
                Text(viewModel.attributedString)
            } else {
                // Show plain text initially while rendering in background
                Text(markdown)
            }
        }
        .onChange(of: markdown) { newContent in
            // For streaming messages, we need to update as content changes
            if !isCompleteMessage {
                // Only process if content actually changed
                if lastProcessedContent != newContent {
                    lastProcessedContent = newContent
                    // Process in background without blocking UI
                    Task {
                        viewModel.processIfNeeded(markdown: newContent, isStreaming: true)
                    }
                }
            }
        }
        .task {
            // First check if we already have it in global cache (only for complete messages)
            if let cached = fetchGlobalContent() {
                renderedContent = cached
                isLoading = false
            } else {
                // Start processing immediately without blocking
                lastProcessedContent = markdown
                
                // Always show something immediately
                if viewModel.attributedString.characters.isEmpty {
                    // Just initialize with plain text to avoid blank UI
                    viewModel.attributedString = AttributedString(markdown)
                }
                
                // Process in background
                Task {
                    await viewModel.processIfNeededAsync(
                        markdown: markdown, 
                        isStreaming: !isCompleteMessage
                    ) { processedContent in
                        // Only store in global cache for complete messages
                        if isCompleteMessage {
                            storeGlobalContent(processedContent)
                        }
                        // Update our view state
                        renderedContent = processedContent
                        isLoading = false
                    }
                }
            }
        }
    }
    }

// ViewModel to handle markdown processing and caching
class MarkdownViewModel: ObservableObject {
    private let markdownProcessor = MarkdownProcessor()
    
    @Published var attributedString: AttributedString = AttributedString("")
    @Published var isLoading: Bool = false // Default to not loading for immediate display
    
    private var processingTask: Task<Void, Never>? = nil
    
    func cancelProcessing() {
        processingTask?.cancel()
    }
    
    // Non-async version for backward compatibility and simpler cases
    func processIfNeeded(markdown: String, isStreaming: Bool = false, completion: ((AttributedString) -> Void)? = nil) {
        // Default to plaintext immediately 
        if attributedString.characters.isEmpty {
            attributedString = AttributedString(markdown)
        }
        
        // For streaming content, always process to show latest updates
        if isStreaming {
            isLoading = false // Don't show loading indicator for streaming updates
            processMarkdown(markdown, useCache: false, completion: completion)
            return
        }
        
        // For complete messages, we can use caching logic
        if !attributedString.characters.isEmpty {
            isLoading = false
            completion?(attributedString)
            return
        }
        
        // Need to process this markdown
        isLoading = true
        
        // Cancel any previous task
        cancelProcessing()
        processMarkdown(markdown, useCache: true, completion: completion)
    }
    
    // Async version for proper task handling
    func processIfNeededAsync(markdown: String, isStreaming: Bool = false, completion: ((AttributedString) -> Void)? = nil) async {
        // Default to plaintext immediately
        await MainActor.run {
            if attributedString.characters.isEmpty {
                attributedString = AttributedString(markdown)
            }
        }
        
        do {
            // Process directly so not to block UI
            let processed: AttributedString
            if isStreaming {
                // Always process fresh content for streaming
                processed = await markdownProcessor.processMarkdown(markdown)
            } else {
                // Use cache for complete messages
                processed = await MarkdownCache.shared.getAttributedString(
                    for: markdown,
                    processor: markdownProcessor
                )
            }
            
            // Update UI on main thread
            await MainActor.run {
                self.attributedString = processed
                self.isLoading = false
                completion?(processed)
            }
        } catch {
            print("Async markdown processing failed: \(error)")
            
            // Fallback to plain text
            let fallback = AttributedString(markdown)
            await MainActor.run {
                self.attributedString = fallback
                self.isLoading = false
                completion?(fallback)
            }
        }
    }
    
    private func processMarkdown(_ markdown: String, useCache: Bool = true, completion: ((AttributedString) -> Void)? = nil) {
        // Create a new task and store the reference
        processingTask = Task {
            do {
                // Check for cancellation before processing
                try Task.checkCancellation()
                
                // Use the cache for complete messages, skip for streaming
                let processed: AttributedString
                if useCache {
                    processed = await MarkdownCache.shared.getAttributedString(
                        for: markdown,
                        processor: markdownProcessor
                    )
                } else {
                    // Process directly for streaming updates
                    processed = await markdownProcessor.processMarkdown(markdown)
                }
                
                // Check for cancellation before updating UI
                try Task.checkCancellation()
                
                // Update the UI on the main thread
                await MainActor.run {
                    self.attributedString = processed
                    self.isLoading = false
                    // Call the completion handler with processed content
                    completion?(processed)
                }
            } catch {
                // Task was cancelled or failed
                print("Markdown processing cancelled or failed: \(error)")
                
                // If processing failed, just show the plain text
                let fallback = AttributedString(markdown)
                await MainActor.run {
                    self.attributedString = fallback
                    self.isLoading = false
                    // Call completion with fallback content
                    completion?(fallback)
                }
            }
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
