//
//  OTP.swift
//  Shared (app, widget, AutoFill)
//

import Foundation

public enum OtpEntry: Hashable, Sendable {
    case hotp(key: Data, digits: Int, counter: UInt64, algorithm: OtpAlgorithm = .sha1)
    case totp(key: Data, digits: Int, interval: Double, algorithm: OtpAlgorithm = .sha1)

    // MARK: Accessors

    public var key: Data {
        switch self {
        case let .hotp(key, _, _, _), let .totp(key, _, _, _): key
        }
    }

    public var digits: Int {
        switch self {
        case let .hotp(_, digits, _, _), let .totp(_, digits, _, _): digits
        }
    }

    public var algorithm: OtpAlgorithm {
        switch self {
        case let .hotp(_, _, _, algorithm), let .totp(_, _, _, algorithm): algorithm
        }
    }

    public var isHotp: Bool {
        if case .hotp = self { return true }
        return false
    }

    /// TOTP period in seconds (`nil` for HOTP).
    public var interval: Double? {
        if case let .totp(_, _, interval, _) = self { return interval }
        return nil
    }

    /// HOTP counter (`nil` for TOTP).
    public var counter: UInt64? {
        if case let .hotp(_, _, counter, _) = self { return counter }
        return nil
    }

    // MARK: Code generation

    /// The code valid at `date`. For HOTP this is the code for the current counter;
    /// call ``advanced()`` after the code has been used.
    public func code(at date: Date = .now) -> String {
        switch self {
        case let .hotp(key, digits, counter, algorithm):
            return hotpCode(key: key, digits: digits, counter: counter, algorithm: algorithm)
        case let .totp(key, digits, interval, algorithm):
            return hotpCode(key: key, digits: digits, counter: Self.timeStep(at: date, interval: interval), algorithm: algorithm)
        }
    }

    /// HOTP with the counter incremented; TOTP unchanged.
    public func advanced() -> OtpEntry {
        if case let .hotp(key, digits, counter, algorithm) = self {
            return .hotp(key: key, digits: digits, counter: counter &+ 1, algorithm: algorithm)
        }
        return self
    }

    // MARK: Time helpers (TOTP)

    /// RFC 6238 time step `T = floor(unixTime / X)`.
    public static func timeStep(at date: Date, interval: Double) -> UInt64 {
        let seconds = max(0, date.timeIntervalSince1970)
        return UInt64(floor(seconds / max(interval, 1)))
    }

    /// Start of the period that contains `date` (TOTP only).
    public func periodStart(containing date: Date) -> Date? {
        guard let interval else { return nil }
        let step = Double(Self.timeStep(at: date, interval: interval))
        return Date(timeIntervalSince1970: step * interval)
    }

    /// Moment the code shown at `date` expires (TOTP only).
    public func nextRefresh(after date: Date) -> Date? {
        guard let interval, let start = periodStart(containing: date) else { return nil }
        return start.addingTimeInterval(interval)
    }

    /// Whole seconds left until the code changes (TOTP) — HOTP returns 0.
    public func secondsRemaining(at date: Date = .now) -> Int {
        guard let next = nextRefresh(after: date) else { return 0 }
        return Int(ceil(next.timeIntervalSince(date)))
    }

    /// Fraction of the current period still remaining, 1 → 0 (TOTP). HOTP returns 1.
    public func remainingFraction(at date: Date = .now) -> Double {
        guard let interval, let next = nextRefresh(after: date) else { return 1 }
        return min(max(next.timeIntervalSince(date) / interval, 0), 1)
    }
}

/// Dates at which a set of TOTP codes change, used to build widget timelines.
public enum CodeTimeline {
    /// `count` dates: `now`, then each following boundary of the shortest period among `entries`.
    public static func refreshDates(for entries: [OtpEntry], now: Date = .now, count: Int = 10) -> [Date] {
        guard count > 0 else { return [] }
        let interval = entries.compactMap(\.interval).min() ?? 30
        let start = Double(OtpEntry.timeStep(at: now, interval: interval)) * interval
        return (0..<count).map { index in
            index == 0 ? now : Date(timeIntervalSince1970: start + Double(index) * interval)
        }
    }
}

extension String {
    /// Groups an OTP for display: "123456" → "123 456", "12345678" → "1234 5678".
    public var groupedOTP: String {
        let chars = Array(self)
        let group: Int
        switch chars.count {
        case 6, 9: group = 3
        case 8: group = 4
        case 7: group = 4
        case 10: group = 5
        default: return self
        }
        var result = ""
        for (index, char) in chars.enumerated() {
            if index > 0 && index % group == 0 { result.append(" ") }
            result.append(char)
        }
        return result
    }
}
