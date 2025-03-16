import SwiftUI
import UIKit

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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Use our custom markdown parser for rendering
            CustomMarkdownContentParser(text: markdown)
                .environmentObject(ThemeManager.shared)
                .font(.body)
                .padding(.vertical, 4)
        }
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: markdown) { newContent in
            // For streaming messages, we need to update as content changes
            if !isCompleteMessage {
                // Only process if content actually changed
                if lastProcessedContent != newContent {
                    lastProcessedContent = newContent
                }
            }
        }
        .task {
            // Process content immediately
            lastProcessedContent = markdown
        }
    }
}

// Define custom renderer components directly within this file to avoid import issues

// MARK: - Custom Renderers
// Bullet List Item
fileprivate struct BulletListItemView: View {
    let content: String
    let level: Int
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Bullet column with proper indentation based on level
            HStack(spacing: 0) {
                if level > 0 {
                    Spacer()
                        .frame(width: CGFloat(level * 20))
                }
                
                Text(bulletForLevel(level))
                    .fontWeight(.bold)
                    .frame(width: 16, alignment: .leading)
            }
            .frame(width: 16 + CGFloat(level * 20), alignment: .trailing)
            
            // Content column - using direct AttributedString handling
            contentView
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
    
    // Use the same bullet style regardless of level
    private func bulletForLevel(_ level: Int) -> String {
        return "•"
    }
    
    private var contentView: some View {
        let attributedString: AttributedString
        do {
            attributedString = try AttributedString(markdown: content, options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            ))
        } catch {
            attributedString = AttributedString(content)
        }
        
        return Text(attributedString)
            .textSelection(.enabled)
    }
}

// Numbered List Item
fileprivate struct NumberedListItemView: View {
    let number: Int
    let content: String
    let level: Int
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Number column with proper indentation based on level
            HStack(spacing: 0) {
                if level > 0 {
                    Spacer()
                        .frame(width: CGFloat(level * 20))
                }
                
                Text(numberMarkerForLevel(level, number: number))
                    .fontWeight(.medium)
                    .frame(width: 25, alignment: .leading)
            }
            .frame(width: 25 + CGFloat(level * 20), alignment: .trailing)
            
            // Content column - using direct AttributedString handling
            contentView
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
    
    // Use the same number style regardless of level
    private func numberMarkerForLevel(_ level: Int, number: Int) -> String {
        return "\(number)."
    }
    
    private var contentView: some View {
        let attributedString: AttributedString
        do {
            attributedString = try AttributedString(markdown: content, options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            ))
        } catch {
            attributedString = AttributedString(content)
        }
        
        return Text(attributedString)
            .textSelection(.enabled)
    }
}

// Horizontal Line
fileprivate struct HorizontalLineView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    
    var body: some View {
        Rectangle()
            .fill(themeManager.currentTheme.accentColor.opacity(0.5))
            .frame(height: 1)
            .padding(.vertical, 10)
    }
}

// Bullet List
fileprivate struct BulletListView: View {
    let items: [String]
    let nestedItems: [MarkdownListItem]
    
    init(items: [String], nestedItems: [MarkdownListItem] = []) {
        self.items = items
        self.nestedItems = nestedItems
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !nestedItems.isEmpty {
                // Render nested list items
                ForEach(nestedItems) { item in
                    BulletListItemView(content: item.content, level: item.level)
                    
                    // Render children recursively if they exist
                    if !item.children.isEmpty {
                        ForEach(item.children) { child in
                            BulletListItemView(content: child.content, level: child.level)
                            
                            // Render grandchildren if they exist (up to 3 levels)
                            if !child.children.isEmpty {
                                ForEach(child.children) { grandchild in
                                    BulletListItemView(content: grandchild.content, level: grandchild.level)
                                }
                            }
                        }
                    }
                }
            } else {
                // Fallback to flat list if no nested items
                ForEach(items.indices, id: \.self) { index in
                    BulletListItemView(content: items[index], level: 0)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// Numbered List
fileprivate struct NumberedListView: View {
    let items: [String]
    let nestedItems: [MarkdownListItem]
    
    init(items: [String], nestedItems: [MarkdownListItem] = []) {
        self.items = items
        self.nestedItems = nestedItems
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !nestedItems.isEmpty {
                // Render nested list items
                ForEach(Array(nestedItems.enumerated()), id: \.element.id) { i, item in
                    NumberedListItemView(number: i + 1, content: item.content, level: item.level)
                    
                    // Render children recursively if they exist
                    if !item.children.isEmpty {
                        ForEach(Array(item.children.enumerated()), id: \.element.id) { j, child in
                            NumberedListItemView(number: j + 1, content: child.content, level: child.level)
                            
                            // Render grandchildren if they exist (up to 3 levels)
                            if !child.children.isEmpty {
                                ForEach(Array(child.children.enumerated()), id: \.element.id) { k, grandchild in
                                    NumberedListItemView(number: k + 1, content: grandchild.content, level: grandchild.level)
                                }
                            }
                        }
                    }
                }
            } else {
                // Fallback to flat list if no nested items
                ForEach(items.indices, id: \.self) { index in
                    NumberedListItemView(number: index + 1, content: items[index], level: 0)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// Custom parser that generates appropriate SwiftUI views for markdown elements
struct CustomMarkdownContentParser: View {
    let text: String
    @EnvironmentObject private var themeManager: ThemeManager
    
    var body: some View {
        // Parse the content into different sections
        let sections = parseMarkdownSections(text)
        
        VStack(alignment: .leading, spacing: 6) {
            ForEach(sections) { section in
                Group {
                    switch section.type {
                    case .bulletList:
                        // Use nested items when available, fall back to flat list
                        if !section.nestedListItems.isEmpty {
                            BulletListView(items: section.listItems, nestedItems: section.nestedListItems)
                        } else {
                            BulletListView(items: section.listItems)
                        }
                    case .numberedList:
                        // Use nested items when available, fall back to flat list
                        if !section.nestedListItems.isEmpty {
                            NumberedListView(items: section.listItems, nestedItems: section.nestedListItems)
                        } else {
                            NumberedListView(items: section.listItems)
                        }
                    case .horizontalLine:
                        HorizontalLineView()
                    case .heading1:
                        Text(section.content.dropFirst(2))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.primary)
                            .padding(.vertical, 4)
                    case .heading2:
                        Text(section.content.dropFirst(3))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.primary)
                            .padding(.vertical, 3)
                    case .heading3:
                        Text(section.content.dropFirst(4))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.primary)
                            .padding(.vertical, 2)
                    case .heading4:
                        Text(section.content.dropFirst(5))
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(.vertical, 1)
                    case .codeBlock:
                        renderCodeBlock(section.content)
                            .padding(.vertical, 4)
                    case .paragraph:
                        renderRegularText(section.content)
                    }
                }
            }
        }
    }
    
    // Render a code block
    private func renderCodeBlock(_ content: String) -> some View {
        // Extract code content by removing the starting and ending ```
        let lines = content.components(separatedBy: "\n")
        var codeLines: [String] = []
        var inCodeBlock = false
        var language = ""
        
        for line in lines {
            if line.hasPrefix("```") {
                if !inCodeBlock {
                    inCodeBlock = true
                    // Extract language if specified (e.g., ```swift)
                    let remainder = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                    if !remainder.isEmpty {
                        language = remainder
                    }
                } else {
                    inCodeBlock = false
                }
            } else if inCodeBlock {
                codeLines.append(line)
            }
        }
        
        let codeContent = codeLines.joined(separator: "\n")
        
        return Text(codeContent)
            .font(.system(.body, design: .monospaced))
            .padding(10)
            .background(Color(UIColor.systemGray6))
            .cornerRadius(5)
            .textSelection(.enabled)
    }
    
    // Render regular markdown text
    private func renderRegularText(_ content: String) -> some View {
        // Process with basic markdown formatting
        let attributedString: AttributedString
        do {
            attributedString = try AttributedString(markdown: content, options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            ))
        } catch {
            attributedString = AttributedString(content)
        }
        
        return Text(attributedString)
            .textSelection(.enabled)
    }
    
    // Parse markdown into sections with support for nested lists
    private func parseMarkdownSections(_ text: String) -> [MarkdownSection] {
        let lines = text.components(separatedBy: "\n")
        var sections: [MarkdownSection] = []
        var currentSectionType: MarkdownSectionType = .paragraph
        var currentSectionContent: [String] = []
        var currentListItems: [String] = []
        var currentNestedListItems: [MarkdownListItem] = []
        var inCodeBlock = false
        var codeBlockContent: [String] = []
        
        // Helper to finalize the current section and start a new one
        func finalizeCurrentSection() {
            guard !currentSectionContent.isEmpty || !currentListItems.isEmpty || !currentNestedListItems.isEmpty || !codeBlockContent.isEmpty else { return }
            
            switch currentSectionType {
            case .bulletList:
                if !currentListItems.isEmpty || !currentNestedListItems.isEmpty {
                    sections.append(MarkdownSection(
                        id: UUID().uuidString,
                        type: currentSectionType,
                        content: "",
                        listItems: currentListItems,
                        nestedListItems: currentNestedListItems
                    ))
                    currentListItems = []
                    currentNestedListItems = []
                }
            case .numberedList:
                if !currentListItems.isEmpty || !currentNestedListItems.isEmpty {
                    sections.append(MarkdownSection(
                        id: UUID().uuidString,
                        type: currentSectionType,
                        content: "",
                        listItems: currentListItems,
                        nestedListItems: currentNestedListItems
                    ))
                    currentListItems = []
                    currentNestedListItems = []
                }
            case .codeBlock:
                if !codeBlockContent.isEmpty {
                    sections.append(MarkdownSection(
                        id: UUID().uuidString,
                        type: .codeBlock,
                        content: codeBlockContent.joined(separator: "\n"),
                        listItems: []
                    ))
                    codeBlockContent = []
                }
            default:
                if !currentSectionContent.isEmpty {
                    sections.append(MarkdownSection(
                        id: UUID().uuidString,
                        type: currentSectionType,
                        content: currentSectionContent.joined(separator: "\n"),
                        listItems: []
                    ))
                    currentSectionContent = []
                }
            }
        }
        
        // Determine the indentation level of a line
        func getIndentationLevel(_ line: String) -> Int {
            let leadingSpaces = line.prefix(while: { $0 == " " }).count
            return leadingSpaces / 2 // Every 2 spaces = 1 level
        }
        
        // A helper function to find the parent item for the current indentation level
        func findParentItem(for itemLevel: Int, in items: [MarkdownListItem]) -> MarkdownListItem? {
            if itemLevel == 0 || items.isEmpty {
                return nil
            }
            
            // Go backwards through the list to find the most recent item with a lower level
            for i in (0..<items.count).reversed() {
                if items[i].level < itemLevel {
                    return items[i]
                }
            }
            
            return nil
        }
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let originalIndent = getIndentationLevel(line)
            
            // Handle code blocks first
            if trimmed.hasPrefix("```") {
                if !inCodeBlock {
                    // Start of a code block
                    finalizeCurrentSection()
                    inCodeBlock = true
                    currentSectionType = .codeBlock
                    codeBlockContent.append(line)
                } else {
                    // End of a code block
                    codeBlockContent.append(line)
                    finalizeCurrentSection()
                    inCodeBlock = false
                    currentSectionType = .paragraph
                }
                continue
            }
            
            if inCodeBlock {
                codeBlockContent.append(line)
                continue
            }
            
            // Handle horizontal line
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                finalizeCurrentSection()
                sections.append(MarkdownSection(
                    id: UUID().uuidString,
                    type: .horizontalLine,
                    content: "",
                    listItems: []
                ))
                currentSectionType = .paragraph
                continue
            }
            
            // Handle headings
            if trimmed.hasPrefix("# ") {
                finalizeCurrentSection()
                currentSectionType = .heading1
                currentSectionContent.append(line)
                finalizeCurrentSection()
                currentSectionType = .paragraph
                continue
            } else if trimmed.hasPrefix("## ") {
                finalizeCurrentSection()
                currentSectionType = .heading2
                currentSectionContent.append(line)
                finalizeCurrentSection()
                currentSectionType = .paragraph
                continue
            } else if trimmed.hasPrefix("### ") {
                finalizeCurrentSection()
                currentSectionType = .heading3
                currentSectionContent.append(line)
                finalizeCurrentSection()
                currentSectionType = .paragraph
                continue
            } else if trimmed.hasPrefix("#### ") {
                finalizeCurrentSection()
                currentSectionType = .heading4
                currentSectionContent.append(line)
                finalizeCurrentSection()
                currentSectionType = .paragraph
                continue
            }
            
            // Handle bullet lists with indentation
            let isBulletPoint = trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ")
            if isBulletPoint {
                if currentSectionType != .bulletList {
                    finalizeCurrentSection()
                    currentSectionType = .bulletList
                }
                
                // Extract the content without the bullet marker
                var itemContent = trimmed
                if trimmed.hasPrefix("- ") {
                    itemContent = String(trimmed.dropFirst(2))
                } else if trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                    itemContent = String(trimmed.dropFirst(2))
                }
                
                let cleanedContent = itemContent.trimmingCharacters(in: .whitespaces)
                
                // Add to the flat list for backward compatibility
                currentListItems.append(cleanedContent)
                
                // Create a new list item with the appropriate level
                let newItem = MarkdownListItem(content: cleanedContent, level: originalIndent)
                
                if originalIndent == 0 {
                    // Top level item
                    currentNestedListItems.append(newItem)
                } else if originalIndent <= 2 { // Support up to 3 levels (0, 1, 2)
                    // Find the appropriate parent for this indented item
                    if let parentItem = findParentItem(for: originalIndent, in: currentNestedListItems) {
                        // Check if we're adding to a parent
                        if parentItem.level < originalIndent {
                            // We need to modify the parent item (which is immutable), so we find its index
                            if let parentIndex = currentNestedListItems.firstIndex(where: { $0.id == parentItem.id }) {
                                // Add this item as a child of the parent
                                currentNestedListItems[parentIndex].children.append(newItem)
                            }
                        }
                    } else {
                        // If no parent found, treat as top level
                        currentNestedListItems.append(newItem)
                    }
                }
                
                continue
            }
            
            // Handle numbered lists with indentation
            let isNumberedItem = trimmed.range(of: "^\\d+\\. ", options: .regularExpression) != nil
            if isNumberedItem {
                if currentSectionType != .numberedList {
                    finalizeCurrentSection()
                    currentSectionType = .numberedList
                }
                
                // Extract the content without the number marker
                if let range = trimmed.range(of: "^\\d+\\. ", options: .regularExpression) {
                    let itemContent = String(trimmed[range.upperBound...])
                    let cleanedContent = itemContent.trimmingCharacters(in: .whitespaces)
                    
                    // Add to flat list for backward compatibility
                    currentListItems.append(cleanedContent)
                    
                    // Create a new list item with the appropriate level
                    let newItem = MarkdownListItem(content: cleanedContent, level: originalIndent)
                    
                    if originalIndent == 0 {
                        // Top level item
                        currentNestedListItems.append(newItem)
                    } else if originalIndent <= 2 { // Support up to 3 levels (0, 1, 2)
                        // Find the appropriate parent for this indented item
                        if let parentItem = findParentItem(for: originalIndent, in: currentNestedListItems) {
                            // Check if we're adding to a parent
                            if parentItem.level < originalIndent {
                                // We need to modify the parent item (which is immutable), so we find its index
                                if let parentIndex = currentNestedListItems.firstIndex(where: { $0.id == parentItem.id }) {
                                    // Add this item as a child of the parent
                                    currentNestedListItems[parentIndex].children.append(newItem)
                                }
                            }
                        } else {
                            // If no parent found, treat as top level
                            currentNestedListItems.append(newItem)
                        }
                    }
                }
                continue
            }
            
            // If we were in a list and now we're not, finalize the list
            if (currentSectionType == .bulletList || currentSectionType == .numberedList) && 
               !isBulletPoint && !isNumberedItem {
                finalizeCurrentSection()
                currentSectionType = .paragraph
            }
            
            // Regular paragraph content
            if currentSectionType != .paragraph {
                finalizeCurrentSection()
                currentSectionType = .paragraph
            }
            
            currentSectionContent.append(line)
        }
        
        // Make sure to finalize the last section
        finalizeCurrentSection()
        
        return sections
    }
}

// Define the different types of markdown sections
enum MarkdownSectionType {
    case paragraph
    case heading1
    case heading2
    case heading3
    case heading4
    case bulletList
    case numberedList
    case codeBlock
    case horizontalLine
}

// Define a structure for markdown list items with support for nesting
struct MarkdownListItem: Identifiable {
    let id: String = UUID().uuidString
    let content: String
    let level: Int // Nesting level: 0 for top level, 1 for first indent, etc.
    var children: [MarkdownListItem] = []
}

// Define a structure for markdown sections
struct MarkdownSection: Identifiable {
    let id: String
    let type: MarkdownSectionType
    let content: String
    let listItems: [String] // Used for flat list rendering
    var nestedListItems: [MarkdownListItem] = [] // Used for nested list rendering
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
        ### Heading 3
        #### Heading 4
        
        This is a paragraph with **bold** and *italic* text.
        
        Here's a horizontal line:
        
        ---
        
        ## Basic Bullet List
        
        * This is a bullet item with longer text that should wrap to the next line while maintaining proper hanging indentation
        * Another bullet item with **bold** and *italic* formatting
        * A third item with `inline code`
        
        ## Nested Bullet List
        
        * First level item 1
          * Second level item 1.1
          * Second level item 1.2
            * Third level item 1.2.1
            * Third level item 1.2.2
        * First level item 2
          * Second level item 2.1
        * First level item 3
        
        ## Basic Numbered List
        
        1. This is a numbered item with longer text that should wrap to the next line while maintaining proper hanging indentation
        2. Another numbered item with **bold** and *italic* formatting
        3. A third item with `inline code`
        
        ## Nested Numbered List
        
        1. First level item 1
           1) Second level item 1.1
           2) Second level item 1.2
              (1) Third level item 1.2.1
              (2) Third level item 1.2.2
        2. First level item 2
           1) Second level item 2.1
        3. First level item 3
        
        ## Mixed List Types
        
        1. First level numbered item
           * Second level bullet item
           * Another second level bullet item
             1) Third level numbered item
             2) Another third level numbered item
        2. Second first level numbered item
           * Second level bullet under item 2
        
        ## Code Block Example
        
        ```swift
        func example() {
            print("Hello world")
            // This is a comment
            let x = 10
        }
        ```
        
        [Link to example](https://example.com)
        """)
    }
    .padding()
    .environmentObject(ThemeManager())
}
