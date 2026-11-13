//
//  AccountDetailView.swift
//  TOTP Watch
//
//  One account, large: the code to read off the wrist and the time it has left.
//

import SwiftUI

struct AccountDetailView: View {
    let account: OtpModel

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        TimelineView(.codeTicks(paused: isLuminanceReduced)) { context in
            let code = account.code(at: context.date)
            VStack(spacing: 8) {
                CountdownRing(entry: account.entry, date: context.date, size: 52, lineWidth: 5, showsSeconds: true)

                Text(isLuminanceReduced ? code.maskedOTP : code.groupedOTP)
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.3), value: code)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .privacySensitive()

                if let subtitle = account.displaySubtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(code: code, date: context.date))
        }
        .id(isLuminanceReduced)
        .navigationTitle(account.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func accessibilityLabel(code: String, date: Date) -> String {
        var parts = [account.displayTitle]
        if let subtitle = account.displaySubtitle { parts.append(subtitle) }
        if !isLuminanceReduced {
            parts.append(code.spokenOTP)
            parts.append(String(localized: "\(account.entry.secondsRemaining(at: date)) seconds left"))
        }
        return parts.joined(separator: ", ")
    }
}

/// The countdown every code runs against. Steps once a second rather than animating, like the
/// iPhone's `CountdownIndicator`; turns red for the last five seconds.
struct CountdownRing: View {
    let entry: OtpEntry
    let date: Date
    var size: CGFloat = 26
    var lineWidth: CGFloat = 3
    var showsSeconds = false

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let interval = entry.interval ?? 30
        let remaining = entry.secondsRemaining(at: date)
        let tint: Color = isLuminanceReduced ? .secondary : remaining <= 5 ? .red : .accentColor
        ZStack {
            Circle()
                .stroke(tint.opacity(0.25), lineWidth: lineWidth)
            if !isLuminanceReduced {
                Circle()
                    .trim(from: 0, to: min(Double(remaining) / interval, 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if showsSeconds {
                    Text("\(remaining)")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                }
            }
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack {
        AccountDetailView(account: OtpModel(issuer: "Example Corp", name: "user@example.com",
                                            entry: .totp(key: Data("12345678901234567890".utf8), digits: 6, interval: 30)))
    }
}
