import Foundation

enum LinxDate {
    private static func fractionalFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func basicFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    static func string(from date: Date) -> String {
        fractionalFormatter().string(from: date)
    }

    static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        return fractionalFormatter().date(from: value) ?? basicFormatter().date(from: value)
    }
}
