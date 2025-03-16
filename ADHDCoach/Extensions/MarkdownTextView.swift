import SwiftUI

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
    
    func getAttributedString(for markdown: String) async -> AttributedString {
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
        let processed = await processMarkdown(markdown)
        addToCache(key, attributedString: processed)
        saveAttributedStringToDisk(key: key, attributedString: processed)
        
        if (cacheMisses + cacheHits) % 100 == 0 {
            // Log cache efficiency periodically
            let hitRate = Double(cacheHits) / Double(cacheHits + cacheMisses) * 100
            print("MarkdownCache: Hit rate: \(String(format: "%.1f", hitRate))% (\(cacheHits) hits, \(cacheMisses) misses)")
        }
        
        return processed
    }
    
    // Simplified preprocessing for streaming content
    func preprocessMarkdownForStreaming(_ text: String) -> String {
        // Use the same approach as regular preprocessing for consistency
        // Replace all line breaks with special marker sequences before parsing
        let processedText = text
            .replacingOccurrences(of: "\n\n", with: "\n\u{00A0}\n")  // Double newlines preserved with non-breaking space
            .replacingOccurrences(of: "\n\n\n", with: "\n\u{00A0}\n\u{00A0}\n")  // Triple newlines
        
        // Process lines separately to ensure proper spacing
        var lines = processedText.components(separatedBy: .newlines)
        var processedLines: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Add extra spacing before and after headings for better visual separation
            if trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") || 
               trimmed.hasPrefix("### ") || trimmed.hasPrefix("#### ") {
                // If not at the beginning of the text, add a space before the heading
                if !processedLines.isEmpty && !processedLines.last!.isEmpty {
                    processedLines.append("\u{00A0}")
                }
                
                // Add the heading
                processedLines.append(line)
                
                // Add extra space after heading unless we're at the end
                if lines.last != line {
                    processedLines.append("\u{00A0}")
                }
                continue
            }
            
            // Always add the line, replacing empty lines with non-breaking space
            if trimmed.isEmpty {
                processedLines.append("\u{00A0}")  // Non-breaking space to preserve empty lines
            } else {
                processedLines.append(line)
            }
        }
        
        return processedLines.joined(separator: "\n")
    }
    
    private func processMarkdown(_ text: String) async -> AttributedString {
        // Preprocess the markdown to better handle code blocks
        let preprocessedText = self.preprocessMarkdown(text)
        
        // Create the markdown options
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible,
            languageCode: nil
        )
        
        // Process the markdown on a background thread
        return await Task.detached(priority: .userInitiated) {
            do {
                // Process with full markdown support
                var attributedString = try AttributedString(markdown: preprocessedText, options: options)
                
                // Style code blocks with a monospaced font and background color
                // We'll use a simpler approach to style code spans
                var codeFont = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
                
                // Apply styling manually by scanning for patterns
                // For inline code blocks with backticks
                do {
                    // NSAttributedString constructor is not optional, so we need a do-catch
                    let nsString = NSMutableAttributedString(attributedString)
                    
                    // Apply monospaced font to code spans with backticks
                    let pattern = "`[^`]+`"
                    if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                        let range = NSRange(location: 0, length: nsString.length)
                        regex.enumerateMatches(in: nsString.string, options: [], range: range) { match, _, _ in
                            if let matchRange = match?.range {
                                nsString.addAttribute(.font, value: codeFont, range: matchRange)
                                nsString.addAttribute(.backgroundColor, value: UIColor(white: 0.95, alpha: 1.0), range: matchRange)
                            }
                        }
                    }
                    
                    // Apply custom styling to headings
                    // H1 headings
                    let h1Pattern = "^# [^\n]+"
                    if let regex = try? NSRegularExpression(pattern: h1Pattern, options: [.anchorsMatchLines]) {
                        let range = NSRange(location: 0, length: nsString.length)
                        regex.enumerateMatches(in: nsString.string, options: [], range: range) { match, _, _ in
                            if let matchRange = match?.range {
                                let font = UIFont.systemFont(ofSize: 28, weight: .bold)
                                nsString.addAttribute(.font, value: font, range: matchRange)
                            }
                        }
                    }
                    
                    // H2 headings
                    let h2Pattern = "^## [^\n]+"
                    if let regex = try? NSRegularExpression(pattern: h2Pattern, options: [.anchorsMatchLines]) {
                        let range = NSRange(location: 0, length: nsString.length)
                        regex.enumerateMatches(in: nsString.string, options: [], range: range) { match, _, _ in
                            if let matchRange = match?.range {
                                let font = UIFont.systemFont(ofSize: 24, weight: .bold)
                                nsString.addAttribute(.font, value: font, range: matchRange)
                            }
                        }
                    }
                    
                    // H3 headings
                    let h3Pattern = "^### [^\n]+"
                    if let regex = try? NSRegularExpression(pattern: h3Pattern, options: [.anchorsMatchLines]) {
                        let range = NSRange(location: 0, length: nsString.length)
                        regex.enumerateMatches(in: nsString.string, options: [], range: range) { match, _, _ in
                            if let matchRange = match?.range {
                                let font = UIFont.systemFont(ofSize: 20, weight: .semibold)
                                nsString.addAttribute(.font, value: font, range: matchRange)
                            }
                        }
                    }
                    
                    // H4 headings
                    let h4Pattern = "^#### [^\n]+"
                    if let regex = try? NSRegularExpression(pattern: h4Pattern, options: [.anchorsMatchLines]) {
                        let range = NSRange(location: 0, length: nsString.length)
                        regex.enumerateMatches(in: nsString.string, options: [], range: range) { match, _, _ in
                            if let matchRange = match?.range {
                                let font = UIFont.systemFont(ofSize: 18, weight: .medium)
                                nsString.addAttribute(.font, value: font, range: matchRange)
                            }
                        }
                    }
                    
                    // Try to convert back to AttributedString
                    attributedString = try AttributedString(nsString)
                } catch {
                    print("Error applying code block styling: \(error)")
                }
                
                // Ensure proper line breaks are preserved
                // This is needed because SwiftUI Text view sometimes collapses multiple consecutive newlines
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineSpacing = 1.2
                paragraphStyle.paragraphSpacing = 10
                paragraphStyle.headIndent = 0
                paragraphStyle.firstLineHeadIndent = 0
                
                // We need to force paragraph style to preserve line breaks
                do {
                    let nsString = NSMutableAttributedString(attributedString)
                    // Apply paragraph style to entire string
                    nsString.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: nsString.length))
                    // Try to convert back to AttributedString
                    attributedString = try AttributedString(nsString)
                } catch {
                    // If conversion fails, fall back to attribute container approach
                    var container = AttributeContainer()
                    container.paragraphStyle = paragraphStyle
                    attributedString.mergeAttributes(container)
                }
                
                return attributedString
            } catch {
                print("Error parsing markdown: \(error)")
                // Return the plain text if markdown parsing fails
                return AttributedString(text)
            }
        }.value
    }
    
    // Preprocess markdown to better handle code blocks, line breaks, and headings
    func preprocessMarkdown(_ text: String) -> String {
        // Replace all line breaks with special marker sequences before parsing
        // This approach is more direct and ensures line breaks aren't collapsed
        let processedText = text
            .replacingOccurrences(of: "\n\n", with: "\n\u{00A0}\n")  // Double newlines preserved with non-breaking space
            .replacingOccurrences(of: "\n\n\n", with: "\n\u{00A0}\n\u{00A0}\n")  // Triple newlines
        
        // Process code blocks and headings separately to ensure they have proper padding
        var lines = processedText.components(separatedBy: .newlines)
        var processedLines: [String] = []
        var inCodeBlock = false
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Special handling for headings - add extra space before and after
            if !inCodeBlock && (trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") || 
                               trimmed.hasPrefix("### ") || trimmed.hasPrefix("#### ")) {
                // If this isn't the first line and the previous line isn't empty, add an empty line before
                if index > 0 && !processedLines.last!.isEmpty && !processedLines.last!.contains("\u{00A0}") {
                    processedLines.append("\u{00A0}")
                }
                
                // Add the heading
                processedLines.append(line)
                
                // If this isn't the last line and the next line isn't empty, add an empty line after
                if index < lines.count - 1 && !lines[index + 1].trimmingCharacters(in: .whitespaces).isEmpty {
                    processedLines.append("\u{00A0}")
                }
                continue
            }
            
            if trimmed.hasPrefix("```") {
                inCodeBlock = !inCodeBlock
                // Add extra spacing for code blocks
                if inCodeBlock {
                    // Start of code block - add a line with non-breaking space before it
                    processedLines.append("\u{00A0}")
                } else {
                    // End of code block - add a line with non-breaking space after it
                    processedLines.append(line)
                    processedLines.append("\u{00A0}")
                    continue
                }
            }
            
            // Always add the line, replacing empty lines with non-breaking space
            if trimmed.isEmpty && !inCodeBlock {
                processedLines.append("\u{00A0}")  // Non-breaking space to preserve empty lines
            } else {
                processedLines.append(line)
            }
        }
        
        return processedLines.joined(separator: "\n")
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

// Global dictionary for storing rendered AttributedStrings (only for completed messages)
fileprivate var globalRenderedContent: [String: AttributedString] = [:]
fileprivate let renderingQueue = DispatchQueue(label: "com.cosmiccoach.markdown.rendering", attributes: .concurrent)

struct MarkdownTextView: View {
    let markdown: String
    var isComplete: Bool = false
    
    @EnvironmentObject private var themeManager: ThemeManager
    
    var body: some View {
        CachedMarkdownContent(markdown: markdown, isCompleteMessage: isComplete)
            // This helps with layout stability
            .animation(nil, value: markdown.count)
    }
}

// A separate component that handles the actual markdown rendering and caching
struct CachedMarkdownContent: View {
    let markdown: String
    let isCompleteMessage: Bool
    
    @StateObject private var viewModel = MarkdownViewModel()
    
    @State private var renderedContent: AttributedString?
    @State private var isLoading: Bool = false
    @State private var lastProcessedContent: String = ""
    
    // Fetch from global cache
    private func fetchGlobalContent() -> AttributedString? {
        guard isCompleteMessage else { return nil }
        
        var result: AttributedString?
        renderingQueue.sync {
            result = globalRenderedContent[markdown]
        }
        return result
    }
    
    // Store to global cache
    private func storeGlobalContent(_ content: AttributedString) {
        guard isCompleteMessage else { return }
        
        renderingQueue.async(flags: .barrier) {
            globalRenderedContent[markdown] = content
        }
    }
    
    // Process text with line breaks and markdown formatting
    private func formatWithLineBreaks(_ text: String) -> Text {
        // First detect if we're dealing with a multiline code block - handle differently
        if text.contains("```") {
            return handleCodeBlocks(text)
        }
        
        // Split by lines and create a text view with explicit line breaks
        let lines = text.components(separatedBy: "\n")
        var result = Text("")
        
        // Handle special case of lists
        var inList = false
        var currentList: [String] = []
        
        for (index, line) in lines.enumerated() {
            // For empty lines, use a space to ensure the line break is preserved
            let lineText = line.isEmpty ? " " : line
            
            // Check if line is a heading (# Heading)
            let trimmed = lineText.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") || 
               trimmed.hasPrefix("### ") || trimmed.hasPrefix("#### ") {
                // Process heading
                let headingText = formatHeading(trimmed)
                result = result + headingText
                
                // Add line break after heading
                if index < lines.count - 1 {
                    result = result + Text("\n")
                }
                continue
            }
            
            // Check if line is a list item
            let isBulletPoint = trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ")
            let isNumberedItem = trimmed.range(of: "^\\d+\\. ", options: .regularExpression) != nil
            
            if isBulletPoint || isNumberedItem {
                // Either continue or start a list
                inList = true
                currentList.append(lineText)
                
                // If this is the last line or next line is not a list item, process the list
                if index == lines.count - 1 || 
                   !(lines[index + 1].trimmingCharacters(in: .whitespaces).hasPrefix("- ") || 
                     lines[index + 1].trimmingCharacters(in: .whitespaces).hasPrefix("* ") ||
                     lines[index + 1].trimmingCharacters(in: .whitespaces).hasPrefix("• ") ||
                     lines[index + 1].trimmingCharacters(in: .whitespaces).range(of: "^\\d+\\. ", options: .regularExpression) != nil) {
                    
                    // Process and add the list
                    let listText = processListItems(currentList)
                    result = result + listText
                    
                    // Reset list tracking
                    inList = false
                    currentList = []
                    
                    // Add line break if needed
                    if index < lines.count - 1 {
                        result = result + Text("\n")
                    }
                }
                
                // Skip to next iteration since we've handled this line as part of a list
                continue
            } else if inList {
                // This line is not a list item but we were in a list - process the list before continuing
                let listText = processListItems(currentList)
                result = result + listText
                
                // Reset list tracking
                inList = false
                currentList = []
                
                // Add line break
                result = result + Text("\n")
            }
            
            // Parse markdown for each line individually for non-list items
            let markdownText: Text
            if lineText.contains("**") || lineText.contains("*") || lineText.contains("`") || 
               lineText.contains("[") || lineText.contains("#") {
                // Try to apply markdown to this line
                do {
                    let options = AttributedString.MarkdownParsingOptions(
                        allowsExtendedAttributes: true,
                        interpretedSyntax: .inlineOnly,
                        failurePolicy: .returnPartiallyParsedIfPossible
                    )
                    var attrs = try AttributedString(markdown: lineText, options: options)
                    
                    // Check for code blocks and apply monospaced font
                    if lineText.contains("`") {
                        let nsString = NSMutableAttributedString(attrs)
                        let font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
                        let pattern = "`[^`]+`"
                        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                            let range = NSRange(location: 0, length: nsString.length)
                            regex.enumerateMatches(in: nsString.string, options: [], range: range) { match, _, _ in
                                if let matchRange = match?.range {
                                    nsString.addAttribute(.font, value: font, range: matchRange)
                                    nsString.addAttribute(.backgroundColor, value: UIColor(white: 0.95, alpha: 1.0), range: matchRange)
                                }
                            }
                        }
                        attrs = try AttributedString(nsString)
                    }
                    
                    markdownText = Text(attrs)
                } catch {
                    markdownText = Text(lineText)
                }
            } else {
                markdownText = Text(lineText)
            }
            
            // Add this line to the result
            result = result + markdownText
            
            // Add line break after each line except the last one
            if index < lines.count - 1 {
                result = result + Text("\n")
            }
        }
        
        // Process any remaining list items
        if inList && !currentList.isEmpty {
            let listText = processListItems(currentList)
            result = result + listText
        }
        
        return result
    }
    
    // Format headings with appropriate styles
    private func formatHeading(_ text: String) -> Text {
        if text.hasPrefix("# ") {
            // Heading 1
            let headingContent = text.dropFirst(2)
            return Text(String(headingContent))
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.primary)
        } else if text.hasPrefix("## ") {
            // Heading 2
            let headingContent = text.dropFirst(3)
            return Text(String(headingContent))
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.primary)
        } else if text.hasPrefix("### ") {
            // Heading 3
            let headingContent = text.dropFirst(4)
            return Text(String(headingContent))
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.primary)
        } else if text.hasPrefix("#### ") {
            // Heading 4
            let headingContent = text.dropFirst(5)
            return Text(String(headingContent))
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.primary)
        } else {
            // Fallback
            return Text(text)
        }
    }
    
    // Process a list of items with proper formatting
    private func processListItems(_ items: [String]) -> Text {
        var result = Text("")
        
        for (index, item) in items.enumerated() {
            let trimmed = item.trimmingCharacters(in: .whitespaces)
            var itemContent = trimmed
            
            // Extract the content without the bullet/number
            if trimmed.hasPrefix("- ") {
                itemContent = String(trimmed.dropFirst(2))
            } else if trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                itemContent = String(trimmed.dropFirst(2))
            } else if let range = trimmed.range(of: "^\\d+\\. ", options: .regularExpression) {
                itemContent = String(trimmed[range.upperBound...])
            }
            
            // Format the list item with bullet point
            let bulletPoint = Text("• ").fontWeight(.bold)
            
            // Format the content with markdown if needed
            let contentText: Text
            do {
                let options = AttributedString.MarkdownParsingOptions(
                    allowsExtendedAttributes: true,
                    interpretedSyntax: .inlineOnly,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
                
                let attrs = try AttributedString(markdown: itemContent, options: options)
                contentText = Text(attrs)
            } catch {
                contentText = Text(itemContent)
            }
            
            // Add bullet and content
            let listItemText = bulletPoint + contentText
            
            // Add to result with padding
            result = result + listItemText
            
            // Add line break after each item except the last one
            if index < items.count - 1 {
                result = result + Text("\n")
            }
        }
        
        return result
    }
    
    // Handle multiline code blocks
    private func handleCodeBlocks(_ text: String) -> Text {
        let lines = text.components(separatedBy: "\n")
        var result = Text("")
        var inCodeBlock = false
        var codeBlockContent = ""
        
        for (index, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inCodeBlock = !inCodeBlock
                
                if !inCodeBlock && !codeBlockContent.isEmpty {
                    // End of code block - render the collected content
                    // We need to use plain Text without styling since we're concatenating
                    let codeText = Text(codeBlockContent)
                        .font(.system(.body, design: .monospaced))
                    
                    // Can't apply view modifiers when concatenating Text objects
                    result = result + codeText
                    codeBlockContent = ""
                }
                
                // Skip the ``` line itself
                if index < lines.count - 1 {
                    result = result + Text("\n")
                }
                continue
            }
            
            if inCodeBlock {
                // Collect code block content
                codeBlockContent += line + (index < lines.count - 1 ? "\n" : "")
            } else {
                // Regular line - process with markdown
                let lineText = line.isEmpty ? " " : line
                
                // Check if line is a heading (# Heading)
                let trimmed = lineText.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") || 
                   trimmed.hasPrefix("### ") || trimmed.hasPrefix("#### ") {
                    // Process heading
                    let headingText = formatHeading(trimmed)
                    result = result + headingText
                    
                    // Add line break after heading
                    if index < lines.count - 1 {
                        result = result + Text("\n")
                    }
                    continue
                }
                
                // Use the same markdown processing as before for non-headings
                let markdownText: Text
                if lineText.contains("**") || lineText.contains("*") || lineText.contains("`") || 
                   lineText.contains("[") || lineText.contains("#") {
                    do {
                        let options = AttributedString.MarkdownParsingOptions(
                            allowsExtendedAttributes: true,
                            interpretedSyntax: .inlineOnly,
                            failurePolicy: .returnPartiallyParsedIfPossible
                        )
                        let attrs = try AttributedString(markdown: lineText, options: options)
                        markdownText = Text(attrs)
                    } catch {
                        markdownText = Text(lineText)
                    }
                } else {
                    markdownText = Text(lineText)
                }
                
                result = result + markdownText
                
                // Add line break after each line except the last one
                if index < lines.count - 1 {
                    result = result + Text("\n")
                }
            }
        }
        
        return result
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Use a VStack to apply styling to the formatted text
            formatWithLineBreaks(markdown)
                .font(.body)
                .textSelection(.enabled)
                // Add code block styling
                .padding(.vertical, 4)
        }
        .lineSpacing(8)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: markdown) { newContent in
            // For streaming messages, we need to update as content changes
            if !isCompleteMessage {
                // Only process if content actually changed
                if lastProcessedContent != newContent {
                    lastProcessedContent = newContent
                    // Process in background without blocking UI
                    Task {
                        await viewModel.processMarkdown(newContent, useCache: false)
                    }
                }
            }
        }
        .task {
            // First check if we already have it in global cache (only for complete messages)
            if let cached = fetchGlobalContent() {
                renderedContent = cached
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
                    let processedContent = await viewModel.processMarkdown(
                        markdown, 
                        useCache: isCompleteMessage
                    )
                    
                    // Only store in global cache for complete messages
                    if isCompleteMessage {
                        storeGlobalContent(processedContent)
                    }
                    
                    // Update our view state
                    renderedContent = processedContent
                }
            }
        }
    }
}

// ViewModel to handle markdown processing and caching
class MarkdownViewModel: ObservableObject {
    @Published var attributedString: AttributedString = AttributedString("")
    @Published var isLoading: Bool = false
    
    private var processingTask: Task<Void, Never>? = nil
    
    func cancelProcessing() {
        processingTask?.cancel()
    }
    
    // Single entry point for all markdown processing
    func processMarkdown(_ markdown: String, useCache: Bool = true) async -> AttributedString {
        // Cancel any previous task
        cancelProcessing()
        
        do {
            let processed: AttributedString
            
            // Use the cache for complete messages, skip for streaming
            if useCache {
                processed = await MarkdownCache.shared.getAttributedString(for: markdown)
            } else {
                // Create the markdown options for streaming (faster, simpler)
                let options = AttributedString.MarkdownParsingOptions(
                    allowsExtendedAttributes: true,
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
                
                // Process directly for streaming updates with lighter parsing
                processed = try await Task.detached {
                    do {
                        // For streaming we use a simpler preprocessing
                        // For streaming we use preprocessMarkdownForStreaming
                        let preprocessedText = MarkdownCache.shared.preprocessMarkdownForStreaming(markdown)
                        var attributedString = try AttributedString(markdown: preprocessedText, options: options)
                        
                        // Style code blocks with a monospaced font
                        // Similar approach to the non-streaming version but simplified
                        var codeFont = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
                        
                        // Apply styling manually by scanning for patterns
                        do {
                            // NSAttributedString constructor is not optional, so we need a do-catch
                            let nsString = NSMutableAttributedString(attributedString)
                            
                            // Apply monospaced font to code spans with backticks
                            let codePattern = "`[^`]+`"
                            if let regex = try? NSRegularExpression(pattern: codePattern, options: []) {
                                let range = NSRange(location: 0, length: nsString.length)
                                regex.enumerateMatches(in: nsString.string, options: [], range: range) { match, _, _ in
                                    if let matchRange = match?.range {
                                        nsString.addAttribute(.font, value: codeFont, range: matchRange)
                                        nsString.addAttribute(.backgroundColor, value: UIColor(white: 0.95, alpha: 1.0), range: matchRange)
                                    }
                                }
                            }
                            
                            // Apply custom styling to headings
                            // H1 headings
                            let h1Pattern = "^# [^\n]+"
                            if let regex = try? NSRegularExpression(pattern: h1Pattern, options: [.anchorsMatchLines]) {
                                let range = NSRange(location: 0, length: nsString.length)
                                regex.enumerateMatches(in: nsString.string, options: [], range: range) { match, _, _ in
                                    if let matchRange = match?.range {
                                        let font = UIFont.systemFont(ofSize: 28, weight: .bold)
                                        nsString.addAttribute(.font, value: font, range: matchRange)
                                    }
                                }
                            }
                            
                            // H2 headings
                            let h2Pattern = "^## [^\n]+"
                            if let regex = try? NSRegularExpression(pattern: h2Pattern, options: [.anchorsMatchLines]) {
                                let range = NSRange(location: 0, length: nsString.length)
                                regex.enumerateMatches(in: nsString.string, options: [], range: range) { match, _, _ in
                                    if let matchRange = match?.range {
                                        let font = UIFont.systemFont(ofSize: 24, weight: .bold)
                                        nsString.addAttribute(.font, value: font, range: matchRange)
                                    }
                                }
                            }
                            
                            // H3 headings
                            let h3Pattern = "^### [^\n]+"
                            if let regex = try? NSRegularExpression(pattern: h3Pattern, options: [.anchorsMatchLines]) {
                                let range = NSRange(location: 0, length: nsString.length)
                                regex.enumerateMatches(in: nsString.string, options: [], range: range) { match, _, _ in
                                    if let matchRange = match?.range {
                                        let font = UIFont.systemFont(ofSize: 20, weight: .semibold)
                                        nsString.addAttribute(.font, value: font, range: matchRange)
                                    }
                                }
                            }
                            
                            // H4 headings
                            let h4Pattern = "^#### [^\n]+"
                            if let regex = try? NSRegularExpression(pattern: h4Pattern, options: [.anchorsMatchLines]) {
                                let range = NSRange(location: 0, length: nsString.length)
                                regex.enumerateMatches(in: nsString.string, options: [], range: range) { match, _, _ in
                                    if let matchRange = match?.range {
                                        let font = UIFont.systemFont(ofSize: 18, weight: .medium)
                                        nsString.addAttribute(.font, value: font, range: matchRange)
                                    }
                                }
                            }
                            
                            // Try to convert back to AttributedString
                            attributedString = try AttributedString(nsString)
                        } catch {
                            print("Error applying code block styling (streaming): \(error)")
                        }
                        
                        // Apply paragraph styles to preserve line breaks even for streaming content
                        let paragraphStyle = NSMutableParagraphStyle()
                        paragraphStyle.lineSpacing = 1.2
                        paragraphStyle.paragraphSpacing = 8 // Slightly less spacing for streaming updates
                        paragraphStyle.headIndent = 0
                        paragraphStyle.firstLineHeadIndent = 0
                        
                        // We need to force paragraph style to preserve line breaks
                        do {
                            let nsString = NSMutableAttributedString(attributedString)
                            // Apply paragraph style to entire string
                            nsString.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: nsString.length))
                            // Try to convert back to AttributedString
                            attributedString = try AttributedString(nsString)
                        } catch {
                            // If conversion fails, fall back to attribute container approach
                            var container = AttributeContainer()
                            container.paragraphStyle = paragraphStyle
                            attributedString.mergeAttributes(container)
                        }
                        
                        return attributedString
                    } catch {
                        print("Error parsing markdown (streaming): \(error)")
                        return AttributedString(markdown)
                    }
                }.value
            }
            
            // Update the UI on the main thread
            await MainActor.run {
                self.attributedString = processed
                self.isLoading = false
            }
            
            return processed
            
        } catch {
            // Task was cancelled or failed
            print("Markdown processing failed: \(error)")
            
            // If processing failed, just show the plain text
            let fallback = AttributedString(markdown)
            await MainActor.run {
                self.attributedString = fallback
                self.isLoading = false
            }
            
            return fallback
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