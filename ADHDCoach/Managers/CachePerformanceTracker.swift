import Foundation

/**
 * CachePerformanceTracker monitors and analyzes prompt caching performance.
 *
 * This class is responsible for:
 * - Tracking cache hits and misses
 * - Calculating token usage and cost savings
 * - Providing performance reports
 * - Persisting cache statistics between app sessions
 */
class CachePerformanceTracker {
    /// Shared instance for app-wide access
    static let shared = CachePerformanceTracker()
    
    /// Total number of API requests made
    private(set) var totalRequests: Int = 0
    
    /// Number of requests that resulted in cache hits
    private(set) var cacheHits: Int = 0
    
    /// Number of requests that resulted in cache misses
    private(set) var cacheMisses: Int = 0
    
    /// Total number of input tokens processed
    private(set) var totalInputTokens: Int = 0
    
    /// Total number of tokens used for cache creation
    private(set) var totalCacheCreationTokens: Int = 0
    
    /// Total number of tokens read from cache
    private(set) var totalCacheReadTokens: Int = 0
    
    /// Estimated cost savings from using cache
    private(set) var estimatedSavings: Double = 0.0
    
    /// UserDefaults keys for persistence
    private enum UserDefaultsKeys {
        static let totalRequests = "cache_total_requests"
        static let cacheHits = "cache_hits"
        static let cacheMisses = "cache_misses"
        static let totalInputTokens = "cache_total_input_tokens"
        static let totalCacheCreationTokens = "cache_total_creation_tokens"
        static let totalCacheReadTokens = "cache_total_read_tokens"
        static let estimatedSavings = "cache_estimated_savings"
    }
    
    /// Private initializer to enforce singleton pattern
    private init() {
        loadStatsFromUserDefaults()
    }
    
    /**
     * Records metrics from an API request.
     *
     * @param cacheCreationTokens Number of tokens used for cache creation
     * @param cacheReadTokens Number of tokens read from cache
     * @param inputTokens Number of regular input tokens
     */
    func recordRequest(
        cacheCreationTokens: Int,
        cacheReadTokens: Int,
        inputTokens: Int
    ) {
        totalRequests += 1
        
        if cacheReadTokens > 0 {
            cacheHits += 1
        } else if cacheCreationTokens > 0 {
            cacheMisses += 1
        }
        
        totalInputTokens += inputTokens
        totalCacheCreationTokens += cacheCreationTokens
        totalCacheReadTokens += cacheReadTokens
        
        // Calculate estimated savings
        // Claude 3.7 Sonnet pricing: $3/MTok input tokens, $3.75/MTok cache write tokens, $0.30/MTok cache read tokens
        let regularCost = Double(totalInputTokens + totalCacheReadTokens) * 0.003 / 1000.0
        let cacheCost = (Double(totalInputTokens) * 0.003 / 1000.0) + 
                        (Double(totalCacheCreationTokens) * 0.00375 / 1000.0) + 
                        (Double(totalCacheReadTokens) * 0.0003 / 1000.0)
        
        estimatedSavings = regularCost - cacheCost
        
        print("🧠 CachePerformanceTracker.recordRequest:")
        print("🧠 - cacheCreationTokens: \(cacheCreationTokens)")
        print("🧠 - cacheReadTokens: \(cacheReadTokens)")
        print("🧠 - inputTokens: \(inputTokens)")
        print("🧠 - totalRequests: \(totalRequests)")
        print("🧠 - cacheHits: \(cacheHits)")
        print("🧠 - cacheMisses: \(cacheMisses)")
        print("🧠 - totalInputTokens: \(totalInputTokens)")
        print("🧠 - totalCacheCreationTokens: \(totalCacheCreationTokens)")
        print("🧠 - totalCacheReadTokens: \(totalCacheReadTokens)")
        print("🧠 - estimatedSavings: \(estimatedSavings)")
        
        // Save stats to UserDefaults after each update
        saveStatsToUserDefaults()
    }
    
    /**
     * Generates a performance report.
     *
     * @return A string containing cache performance metrics
     */
    func getPerformanceReport() -> String {
        let hitRate = totalRequests > 0 ? Double(cacheHits) / Double(totalRequests) * 100.0 : 0.0
        
        return """
        Cache Performance Report:
        - Total Requests: \(totalRequests)
        - Cache Hits: \(cacheHits) (\(String(format: "%.1f", hitRate))%)
        - Cache Misses: \(cacheMisses)
        - Total Input Tokens: \(totalInputTokens)
        - Total Cache Creation Tokens: \(totalCacheCreationTokens)
        - Total Cache Read Tokens: \(totalCacheReadTokens)
        - Estimated Cost Savings: $\(String(format: "%.4f", estimatedSavings))
        """
    }
    
    /**
     * Resets all performance metrics.
     */
    func reset() {
        totalRequests = 0
        cacheHits = 0
        cacheMisses = 0
        totalInputTokens = 0
        totalCacheCreationTokens = 0
        totalCacheReadTokens = 0
        estimatedSavings = 0.0
        
        // Clear saved stats from UserDefaults
        saveStatsToUserDefaults()
    }
    
    /**
     * Saves current cache performance stats to UserDefaults.
     */
    func saveStatsToUserDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(totalRequests, forKey: UserDefaultsKeys.totalRequests)
        defaults.set(cacheHits, forKey: UserDefaultsKeys.cacheHits)
        defaults.set(cacheMisses, forKey: UserDefaultsKeys.cacheMisses)
        defaults.set(totalInputTokens, forKey: UserDefaultsKeys.totalInputTokens)
        defaults.set(totalCacheCreationTokens, forKey: UserDefaultsKeys.totalCacheCreationTokens)
        defaults.set(totalCacheReadTokens, forKey: UserDefaultsKeys.totalCacheReadTokens)
        defaults.set(estimatedSavings, forKey: UserDefaultsKeys.estimatedSavings)
        
        // Ensure changes are written to disk
        defaults.synchronize()
        
        print("🧠 Cache performance stats saved to UserDefaults")
    }
    
    /**
     * Loads cache performance stats from UserDefaults.
     */
    private func loadStatsFromUserDefaults() {
        let defaults = UserDefaults.standard
        
        totalRequests = defaults.integer(forKey: UserDefaultsKeys.totalRequests)
        cacheHits = defaults.integer(forKey: UserDefaultsKeys.cacheHits)
        cacheMisses = defaults.integer(forKey: UserDefaultsKeys.cacheMisses)
        totalInputTokens = defaults.integer(forKey: UserDefaultsKeys.totalInputTokens)
        totalCacheCreationTokens = defaults.integer(forKey: UserDefaultsKeys.totalCacheCreationTokens)
        totalCacheReadTokens = defaults.integer(forKey: UserDefaultsKeys.totalCacheReadTokens)
        estimatedSavings = defaults.double(forKey: UserDefaultsKeys.estimatedSavings)
        
        print("🧠 Cache performance stats loaded from UserDefaults")
        print("🧠 - totalRequests: \(totalRequests)")
        print("🧠 - cacheHits: \(cacheHits)")
        print("🧠 - cacheMisses: \(cacheMisses)")
        print("🧠 - totalInputTokens: \(totalInputTokens)")
        print("🧠 - totalCacheCreationTokens: \(totalCacheCreationTokens)")
        print("🧠 - totalCacheReadTokens: \(totalCacheReadTokens)")
        print("🧠 - estimatedSavings: \(estimatedSavings)")
    }
}
