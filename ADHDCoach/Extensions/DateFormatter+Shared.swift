import Foundation

/**
 * Extension to provide shared date formatters for consistent date formatting across the app.
 */
extension DateFormatter {
    /**
     * Returns a shared date formatter for standard date and time display.
     *
     * This formatter uses medium date style and short time style with the current time zone.
     * It's suitable for displaying dates in user-facing contexts.
     *
     * @return A configured DateFormatter instance
     */
    static var shared: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone.current
        return formatter
    }()
    
    /**
     * Returns a shared date formatter for parsing date strings from Claude API.
     *
     * This formatter uses the format "MMM d, yyyy 'at' h:mm a" which is the expected
     * format for dates in tool inputs from Claude.
     *
     * @return A configured DateFormatter instance
     */
    static var claudeDateParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return formatter
    }()
    
    /**
     * Returns a shared date formatter for full date and time display with timezone.
     *
     * This formatter uses full date style and full time style with the current time zone.
     * It's suitable for displaying detailed date and time information.
     *
     * @return A configured DateFormatter instance
     */
    static var fullDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .full
        formatter.timeZone = TimeZone.current
        return formatter
    }()
    
    /**
     * Formats the current date and time with timezone information.
     *
     * @return A formatted string representing the current date and time with timezone
     */
    static func formatCurrentDateTimeWithTimezone() -> String {
        return "\(fullDateTime.string(from: Date())) (\(TimeZone.current.identifier))"
    }
}
