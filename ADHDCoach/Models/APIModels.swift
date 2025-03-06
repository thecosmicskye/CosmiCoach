import Foundation

/**
 * Models for Claude API communication.
 * 
 * This file contains all the model structures needed for API requests and responses.
 */

// MARK: - Error Type Definitions

/// Known error types from the Claude API
enum ClaudeAPIErrorType: String {
    case invalidRequest = "invalid_request_error"
    case authentication = "authentication_error"
    case permission = "permission_error"
    case notFound = "not_found_error"
    case requestTooLarge = "request_too_large"
    case rateLimit = "rate_limit_error"
    case apiError = "api_error"
    case overloaded = "overloaded_error"
    case unknown
    
    init(from string: String) {
        self = ClaudeAPIErrorType(rawValue: string) ?? .unknown
    }
}

// MARK: - Cache Performance Tracking

/// Structure to store cache performance metrics for a Claude API request
struct CachePerformanceMetrics {
    var cacheCreationTokens: Int
    var cacheReadTokens: Int
    var inputTokens: Int
    
    var totalTokens: Int {
        return cacheCreationTokens + cacheReadTokens + inputTokens
    }
    
    var cacheSavingsPercent: Double {
        guard totalTokens > 0 else { return 0.0 }
        return Double(cacheReadTokens) / Double(totalTokens) * 100.0
    }
    
    var hasCacheHit: Bool {
        return cacheReadTokens > 0
    }
}

// MARK: - Tool Use Models

/// Structure representing a tool use result
struct ToolUseResult {
    let toolId: String
    let content: String
}

/// Fallback tool input generator
struct ToolInputFallback {
    static func createInput(for toolName: String?) -> [String: Any] {
        let now = Date()
        
        switch toolName {
        case "add_calendar_event":
            let oneHourLater = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now
            return [
                "title": "Test Calendar Event",
                "start": DateFormatter.claudeDateParser.string(from: now),
                "end": DateFormatter.claudeDateParser.string(from: oneHourLater),
                "notes": "Created by Claude when JSON parsing failed"
            ]
        case "add_reminder":
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
            return [
                "title": "Test Reminder",
                "due": DateFormatter.claudeDateParser.string(from: tomorrow),
                "notes": "Created by Claude when JSON parsing failed"
            ]
        case "add_memory":
            return [
                "content": "User asked Claude to create a test memory",
                "category": "Miscellaneous Notes",
                "importance": 3
            ]
        default:
            // For other tools, provide a basic fallback
            return ["note": "Fallback tool input for \(toolName ?? "unknown tool")"]
        }
    }
}

// MARK: - API Response Message Creator

/// Utility for creating user-friendly error messages
struct APIErrorMessageCreator {
    static func createUserFriendlyErrorMessage(
        statusCode: Int,
        errorType: String,
        errorDetails: String,
        isFollowUp: Bool = false
    ) -> String {
        let prefix = isFollowUp ? "\n\nUnable to continue: " : "Sorry, I encountered an issue: "
        
        // Special case for stream errors (statusCode == 0)
        if statusCode == 0 {
            // Handle stream-specific errors
            switch errorType {
            case "overloaded_error":
                return "\(prefix)The assistant service is currently overloaded. Please try again in a few moments\(errorDetails.isEmpty ? "" : ". \(errorDetails)")"
            case "api_error":
                return "\(prefix)The assistant service is experiencing internal errors. Please try again later\(errorDetails.isEmpty ? "" : ". \(errorDetails)")"
            default:
                return "\(prefix)Error communicating with assistant service\(errorDetails.isEmpty ? "" : ". \(errorDetails)")"
            }
        }
        
        // Check for specific error types and status codes
        switch statusCode {
        case 400:
            if errorType == "invalid_request_error" {
                return "\(prefix)There was an issue with my request. Please try again or simplify your request\(errorDetails.isEmpty ? "" : ". \(errorDetails)")"
            } else {
                return "\(prefix)There was a problem with how I'm trying to talk to the assistant. Please try again\(errorDetails.isEmpty ? "" : ". \(errorDetails)")"
            }
            
        case 401:
            if errorType == "authentication_error" {
                return "\(prefix)There's an issue with the API key. Please check your API key in settings\(errorDetails.isEmpty ? "" : ". \(errorDetails)")"
            } else {
                return "\(prefix)Not authorized to use this service. Please check your API key in settings\(errorDetails.isEmpty ? "" : ". \(errorDetails)")"
            }
            
        case 403:
            if errorType == "permission_error" {
                return "\(prefix)The API key doesn't have permission to use this service. Please check your API subscription\(errorDetails.isEmpty ? "" : ". \(errorDetails)")"
            } else {
                return "\(prefix)Access denied. Please check your API subscription\(errorDetails.isEmpty ? "" : ". \(errorDetails)")"
            }
            
        case 404:
            if errorType == "not_found_error" {
                return "\(prefix)The service endpoint couldn't be found. Please update the app or try again later\(errorDetails.isEmpty ? "" : ". \(errorDetails)")"
            } else {
                return "\(prefix)The requested resource was not found. Please try again later\(errorDetails.isEmpty ? "" : ". \(errorDetails)")"
            }
            
        case 413:
            if errorType == "request_too_large" {
                return "\(prefix)Your request was too large. Please try a shorter message or clear some conversation history\(errorDetails.isEmpty ? "" : ". \(errorDetails)")"
            } else {
                return "\(prefix)The message was too large to process. Please try a shorter message\(errorDetails.isEmpty ? "" : ". \(errorDetails)")"
            }
            
        case 429:
            if errorType == "rate_limit_error" {
                return "\(prefix)Rate limit exceeded. Please wait a moment and try again\(errorDetails.isEmpty ? "" : ". \(errorDetails)")"
            } else {
                return "\(prefix)Too many requests. Please wait a moment and try again\(errorDetails.isEmpty ? "" : ". \(errorDetails)")"
            }
            
        case 500:
            if errorType == "api_error" {
                return "\(prefix)The assistant service is experiencing internal errors. Please try again later\(errorDetails.isEmpty ? "" : ". \(errorDetails)")"
            } else {
                return "\(prefix)An unexpected error occurred. Please try again later\(errorDetails.isEmpty ? "" : ". \(errorDetails)")"
            }
            
        case 529:
            if errorType == "overloaded_error" {
                return "\(prefix)The assistant service is currently overloaded. Please try again later\(errorDetails.isEmpty ? "" : ". \(errorDetails)")"
            } else {
                return "\(prefix)The service is temporarily unavailable. Please try again later\(errorDetails.isEmpty ? "" : ". \(errorDetails)")"
            }
            
        default:
            return "\(prefix)Error communicating with assistant service. Status code: \(statusCode)\(errorDetails.isEmpty ? "" : ". \(errorDetails)")"
        }
    }
}
