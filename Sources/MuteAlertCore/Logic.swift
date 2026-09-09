import Foundation

public enum Match {
    public static func tokens(_ value: String) -> [String] {
        value.lowercased().split(separator: "|").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
    }
    public static func label(_ name: String, _ patterns: String) -> Bool {
        let text = name.lowercased()
        return tokens(patterns).contains { token in
            var start = text.startIndex
            while start < text.endIndex,
                  let range = text.range(of: token, range: start..<text.endIndex) {
                let left = range.lowerBound == text.startIndex ||
                    !text[text.index(before: range.lowerBound)].isLetter
                let right = range.upperBound == text.endIndex ||
                    !text[range.upperBound].isLetter
                if left && right { return true }
                start = text.index(after: range.lowerBound)
            }
            return false
        }
    }
}

public struct SpeechGate {
    private var since: TimeInterval?
    private var lastAlert: TimeInterval = -.infinity
    public init() {}
    public mutating func update(now: TimeInterval, peak: Double, muted: Bool,
                                canHear: Bool, threshold: Double, delay: Double) -> Bool {
        guard muted && canHear && peak >= threshold else { since = nil; return false }
        if since == nil { since = now }
        guard now - (since ?? now) >= delay, now - lastAlert >= 10 else { return false }
        lastAlert = now
        return true
    }
}

public struct Version: Comparable {
    public let parts: [Int]
    public init?(_ value: String) {
        let raw = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let fields = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard fields.count == 3 else { return nil }
        let numbers = fields.compactMap { Int($0) }
        guard numbers.count == 3, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        parts = numbers
    }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.parts.lexicographicallyPrecedes(rhs.parts)
    }
}

public enum SteelSeriesState {
    public struct Observation: Equatable {
        public let online: Bool
        public let muted: Bool
    }
    public static func parse(report: [UInt8]) -> Observation? {
        guard report.count >= 16, report[0] == 0x06, report[1] == 0xB0,
              report[9] <= 1 else { return nil }
        return Observation(online: report[15] == 0x08, muted: report[9] == 1)
    }
    public static func muted(report: [UInt8]) -> Bool? {
        guard let observation = parse(report: report), observation.online else { return nil }
        return observation.muted
    }
}

public struct LatchedMuteReconciler {
    private var initialPending = true
    private var known = false
    private var previous = false

    public init() {}

    public mutating func observe(_ muted: Bool?) -> Bool? {
        guard let muted else {
            known = false
            return nil
        }
        defer { known = true; previous = muted; initialPending = false }
        return initialPending || (known && previous != muted) ? muted : nil
    }
}
