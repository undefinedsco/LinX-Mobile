import Foundation

enum LinxDate {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")
    private static let utcTimeZone = TimeZone(secondsFromGMT: 0)!

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

    private static func dateFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = posixLocale
        formatter.timeZone = utcTimeZone
        formatter.dateFormat = format
        return formatter
    }

    static func string(from date: Date) -> String {
        fractionalFormatter().string(from: date)
    }

    static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        if let date = fractionalFormatter().date(from: trimmed) ?? basicFormatter().date(from: trimmed) {
            return date
        }

        if let epochDate = parseEpoch(trimmed) {
            return epochDate
        }

        for format in [
            "yyyy-MM-dd HH:mm:ss.SSS Z",
            "yyyy-MM-dd HH:mm:ss Z",
            "yyyy-MM-dd HH:mm:ss.SSS",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
        ] {
            if let date = dateFormatter(format: format).date(from: trimmed) {
                return date
            }
        }

        return nil
    }

    private static func parseEpoch(_ value: String) -> Date? {
        guard let number = Double(value), number.isFinite else { return nil }

        let isMilliseconds = abs(number) >= 1_000_000_000_000
        let seconds = isMilliseconds ? number / 1_000 : number
        return Date(timeIntervalSince1970: seconds)
    }
}
