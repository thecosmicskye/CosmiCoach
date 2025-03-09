import SwiftUI

struct PromptCachingView: View {
    @ObservedObject var chatManager: ChatManager
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var showingResetConfirmation = false
    @State private var testResult: String? = nil
    @State private var refreshID = UUID()
    
    var body: some View {
        List {
            Section {
                MetricsCardView(chatManager: chatManager)
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, 8)
            }
            
            Section(header: Text("Detailed Report")) {
                Text(chatManager.getCachePerformanceReport())
                    .font(.system(.body, design: .monospaced))
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
        .navigationTitle("Prompt Caching")
        .navigationBarTitleDisplayMode(.inline)
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
                
                // Force refresh
                refreshID = UUID()
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
    }
}

struct MetricsCardView: View {
    @ObservedObject var chatManager: ChatManager
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeManager: ThemeManager
    
    // Parse values from performance report
    private var hitRate: Double {
        let report = chatManager.getCachePerformanceReport()
        if let range = report.range(of: "Cache hits:.*\\((.*?)%\\)", options: .regularExpression) {
            let substring = report[range]
            if let percentRange = substring.range(of: "[0-9.]+(?=%)", options: .regularExpression) {
                return Double(substring[percentRange]) ?? 0.0
            }
        }
        return 0.0
    }
    
    private var effectiveness: Double {
        let report = chatManager.getCachePerformanceReport()
        if let range = report.range(of: "Cache effectiveness: (.*?)%", options: .regularExpression) {
            let substring = report[range]
            if let percentRange = substring.range(of: "[0-9.]+(?=%)", options: .regularExpression) {
                return Double(substring[percentRange]) ?? 0.0
            }
        }
        return 0.0
    }
    
    private var estimatedSavings: String {
        let report = chatManager.getCachePerformanceReport()
        if let range = report.range(of: "Savings: \\$(.*?) \\(", options: .regularExpression) {
            let substring = report[range]
            if let valueRange = substring.range(of: "\\$(.*?) \\(", options: .regularExpression) {
                let value = substring[valueRange]
                return String(value.dropFirst(1).dropLast(2))
            }
        }
        return "$0.0000"
    }
    
    private var savingsPercent: Double {
        let report = chatManager.getCachePerformanceReport()
        if let range = report.range(of: "Savings: \\$.*? \\((.*?)%\\)", options: .regularExpression) {
            let substring = report[range]
            if let percentRange = substring.range(of: "[0-9.]+(?=%)", options: .regularExpression) {
                return Double(substring[percentRange]) ?? 0.0
            }
        }
        return 0.0
    }
    
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
                    .foregroundColor(themeManager.accentColor(for: colorScheme))
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