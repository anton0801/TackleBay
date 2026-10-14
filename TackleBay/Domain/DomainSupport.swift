import Foundation

/// User-facing domain failure. The message is plain English UI copy.
enum DomainError: Error, Equatable, LocalizedError {
    case validation(String)
    case notFound(String)
    case conflict(String)
    case blocked(String)

    var message: String {
        switch self {
        case .validation(let m), .notFound(let m), .conflict(let m), .blocked(let m): return m
        }
    }

    var errorDescription: String? { message }

    var isConflict: Bool {
        if case .conflict = self { return true }
        return false
    }
}

/// Source of wall-clock time; injectable for tests.
protocol TimeProvider: AnyObject {
    func now() -> Date
}

final class SystemTimeProvider: TimeProvider {
    func now() -> Date { Date() }
}

final class FixedTimeProvider: TimeProvider {
    var current: Date
    init(_ date: Date) { current = date }
    func now() -> Date { current }
    func advance(_ seconds: TimeInterval) { current = current.addingTimeInterval(seconds) }
}

/// Uniform integer source. Production uses the system CSPRNG, tests use a deterministic sequence.
protocol RandomSource: AnyObject {
    func nextInt(upperBound: Int) -> Int
}

/// Deterministic source for tests: returns the scripted values in order, cycling.
final class ScriptedRandomSource: RandomSource {
    private let values: [Int]
    private var index = 0
    init(_ values: [Int]) { self.values = values }
    func nextInt(upperBound: Int) -> Int {
        defer { index += 1 }
        return values[index % values.count] % upperBound
    }
}

enum TextRules {
    static func trimmed(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func optional(_ s: String?) -> String? {
        let t = trimmed(s)
        return t.isEmpty ? nil : t
    }

    /// Returns an error message when the trimmed text length is outside `range`.
    static func check(_ s: String?, field: String, range: ClosedRange<Int>) -> String? {
        let count = trimmed(s).count
        if count < range.lowerBound {
            return range.lowerBound <= 1 ? "\(field) is required." : "\(field) needs at least \(range.lowerBound) characters."
        }
        if count > range.upperBound { return "\(field) can be up to \(range.upperBound) characters." }
        return nil
    }
}
