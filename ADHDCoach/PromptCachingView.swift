import SwiftUI

/// A lightweight wrapper view that loads and presents the actual content
struct PromptCachingView: View {
    @ObservedObject var chatManager: ChatManager
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var isLoaded = false
    
    var body: some View {
        ZStack {
            if isLoaded {
                // Only show the content view once we're ready
                PromptCachingContentView(chatManager: chatManager)
                    .environmentObject(themeManager)
            } else {
                // Show loading indicator
                VStack {
                    ProgressView()
                        .padding()
                    Text("Loading cache metrics...")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Prompt Caching")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Small delay to allow the view to render first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isLoaded = true
            }
        }
    }
}

/// The actual content view that loads after the wrapper view is displayed
struct PromptCachingContentView: View {
    @ObservedObject var chatManager: ChatManager
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var showingResetConfirmation = false
    @State private var testResult: String? = nil
    @State private var refreshID = UUID()
    @State private var performanceReport: String = "Loading report..."
    @State private var hitRate: Double = 0.0
    @State private var effectiveness: Double = 0.0
    @State private var savingsPercent: Double = 0.0
    @State private var estimatedSavings: String = "0.0000"
    @State private var isMetricsLoaded = false
    
    var body: some View {
        List {
            Section {
                if isMetricsLoaded {
                    MetricsView(
                        hitRate: hitRate,
                        effectiveness: effectiveness,
                        savingsPercent: savingsPercent,
                        estimatedSavings: estimatedSavings,
                        accentColor: themeManager.accentColor(for: colorScheme)
                    )
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, 8)
                } else {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, 8)
                }
            }
            
            Section(header: Text("Detailed Report")) {
                Text(performanceReport)
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .padding(.vertical, 4)
            }
            
            Section(header: Text("About Prompt Caching")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "gear.badge.checkmark")
                            .font(.title)
                            .foregroundColor(themeManager.accentColor(for: colorScheme))
                        Text("How Prompt Caching Works")
                            .font(.headline)
                    }
                    
                    Text("Prompt caching reduces token usage by reusing parts of previous prompts. When you send a message, Claude can reuse cached content instead of processing it again.")
                        .font(.body)
                    
                    HStack {
                        Image(systemName: "star.fill")
                            .font(.title3)
                            .foregroundColor(themeManager.accentColor(for: colorScheme))
                        Text("Benefits")
                            .font(.headline)
                    }
                    .padding(.top, 8)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        BulletPointView(text: "Reduced API costs", icon: "dollarsign.circle")
                        BulletPointView(text: "Faster response times", icon: "bolt.fill")
                        BulletPointView(text: "Lower token usage", icon: "text.badge.checkmark")
                    }
                    .padding(.leading, 4)
                    
                    HStack {
                        Image(systemName: "chart.pie.fill")
                            .font(.title3)
                            .foregroundColor(themeManager.accentColor(for: colorScheme))
                        Text("Cost Calculation")
                            .font(.headline)
                    }
                    .padding(.top, 8)
                    
                    Text("The cost savings are calculated by comparing what it would cost without caching (all tokens at standard input rates) vs. with caching (standard input tokens + cache creation tokens + cache read tokens at their respective rates).")
                        .font(.body)
                    
                    InfoCardView(
                        title: "Claude 3.7 Token Pricing (per million tokens)",
                        items: [
                            InfoItem(name: "Regular Input", value: "$3.00"),
                            InfoItem(name: "Cache Creation", value: "$3.75"),
                            InfoItem(name: "Cache Read", value: "$0.30")
                        ]
                    )
                    .padding(.top, 12)
                    
                    Text("Note: These metrics reflect Claude's API usage and Anthropic's official pricing. Actual API costs may vary based on your specific subscription plan.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                .padding(.vertical, 4)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Reset", role: .destructive) {
                    showingResetConfirmation = true
                }
                .foregroundColor(.red)
            }
        }
        .confirmationDialog(
            "Reset Cache Metrics",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                chatManager.resetCachePerformanceMetrics()
                
                // Show confirmation to user
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                
                testResult = "✅ Cache metrics reset successfully!"
                
                // Clear the success message after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if testResult == "✅ Cache metrics reset successfully!" {
                        testResult = nil
                    }
                }
                
                // Reload the data after reset
                loadData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset all cache performance metrics to zero. This action cannot be undone.")
        }
        .overlay(
            Group {
                if let result = testResult {
                    VStack {
                        Spacer()
                        Text(result)
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                            .shadow(radius: 2)
                            .padding(.bottom, 20)
                    }
                }
            }
        )
        .id(refreshID)  // Force refresh when metrics are reset
        .accentColor(themeManager.accentColor(for: colorScheme))
        .onAppear {
            loadData()
        }
    }
    
    private func loadData() {
        // Reset loading states
        isMetricsLoaded = false
        performanceReport = "Loading report..."
        
        // Run calculations in background
        DispatchQueue.global(qos: .userInitiated).async {
            // Get a direct reference to the tracker
            let tracker = CachePerformanceTracker.shared
            
            // Calculate hit rate
            let hitRateValue = tracker.totalRequests > 0 ? 
                Double(tracker.cacheHits) / Double(tracker.totalRequests) * 100.0 : 0.0
            
            // Calculate effectiveness
            let potentialTokensWithoutCache = tracker.totalInputTokens + tracker.totalCacheReadTokens
            let effectivenessValue = potentialTokensWithoutCache > 0 ? 
                Double(tracker.totalCacheReadTokens) / Double(potentialTokensWithoutCache) * 100.0 : 0.0
            
            // Calculate savings percent
            let regularCostPerMille = 0.003 // $3/MTok input tokens
            let costWithoutCaching = Double(potentialTokensWithoutCache) * regularCostPerMille / 1000.0
            let savingsPercentValue = costWithoutCaching > 0 ? 
                (tracker.estimatedSavings / costWithoutCaching) * 100.0 : 0.0
                
            // Format estimated savings
            let savingsString = String(format: "%.4f", tracker.estimatedSavings)
            
            // Get performance report text
            var reportText = "Loading report..."
            
            // Add a small artificial delay to prevent potential race conditions
            Thread.sleep(forTimeInterval: 0.1)
            
            // Call the report function through the chatManager to avoid any access issues
            reportText = chatManager.getCachePerformanceReport()
            
            // Update UI on main thread
            DispatchQueue.main.async {
                self.hitRate = hitRateValue
                self.effectiveness = effectivenessValue
                self.savingsPercent = savingsPercentValue
                self.estimatedSavings = savingsString
                self.performanceReport = reportText
                self.isMetricsLoaded = true
                
                // Update the refresh ID to ensure the view updates
                self.refreshID = UUID()
            }
        }
    }
}

/// Lightweight view for displaying metrics
struct MetricsView: View {
    let hitRate: Double
    let effectiveness: Double
    let savingsPercent: Double
    let estimatedSavings: String
    let accentColor: Color
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                MetricCircleView(
                    value: hitRate, 
                    label: "Hit Rate",
                    icon: "checkmark.circle.fill", 
                    color: Color.green
                )
                Spacer()
                MetricCircleView(
                    value: effectiveness, 
                    label: "Effectiveness",
                    icon: "bolt.fill", 
                    color: Color.orange
                )
                Spacer()
                MetricCircleView(
                    value: savingsPercent, 
                    label: "Savings",
                    icon: "dollarsign.circle.fill", 
                    color: Color.blue
                )
                Spacer()
            }
            .padding(.vertical, 8)
            
            VStack {
                Text("Estimated Cost Savings")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("$\(estimatedSavings)")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundColor(accentColor)
            }
        }
        .padding()
    }
}

struct MetricCircleView: View {
    let value: Double
    let label: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 8)
                    .frame(width: 70, height: 70)
                
                Circle()
                    .trim(from: 0, to: min(CGFloat(value) / 100.0, 1.0))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: value)
                
                VStack(spacing: 0) {
                    Image(systemName: icon)
                        .foregroundColor(color)
                    Text("\(Int(value))%")
                        .font(.system(.body, design: .rounded, weight: .bold))
                }
            }
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct InfoItem: Identifiable {
    let id = UUID()
    let name: String
    let value: String
}

struct InfoCardView: View {
    let title: String
    let items: [InfoItem]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
                .padding(.bottom, 2)
            
            ForEach(items) { item in
                HStack {
                    Text(item.name)
                        .foregroundColor(.primary)
                    Spacer()
                    Text(item.value)
                        .foregroundColor(.secondary)
                        .bold()
                }
                .font(.subheadline)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

struct BulletPointView: View {
    let text: String
    let icon: String
    
    init(text: String, icon: String = "circle.fill") {
        self.text = text
        self.icon = icon
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(text)
                .font(.body)
        }
    }
}

#Preview {
    NavigationStack {
        PromptCachingView(
            chatManager: ChatManager()
        )
        .environmentObject(ThemeManager())
    }
}