import Foundation

enum AppFormat {
    static func day(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func dayYear(_ date: Date) -> String {
        dayYearFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }()

    private static let dayYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }()
}
