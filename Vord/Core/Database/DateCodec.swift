import Foundation

final class DateCodec: @unchecked Sendable {
    static let shared = DateCodec()

    private let lock = NSLock()
    private let fractional: ISO8601DateFormatter
    private let basic: ISO8601DateFormatter

    private init() {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.fractional = fractional
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        self.basic = basic
    }

    func format(_ date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return fractional.string(from: date)
    }

    func parse(_ string: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return fractional.date(from: string) ?? basic.date(from: string)
    }
}

enum DayBounds {
    static func range(for now: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }
}
