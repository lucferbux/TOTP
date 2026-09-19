//
//  AccountCodeView.swift
//  TOTP
//
//  One account: live code, countdown and metadata. Used as a List row (compact width)
//  and as a card in the adaptive grid (regular width / Mac).
//

import SwiftUI

struct AccountCodeView: View {
    enum Style {
        case row
        case card
    }

    let account: OtpModel
    var style: Style = .row
    var isCopied = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(at: context.date)
        }
    }

    @ViewBuilder
    private func content(at date: Date) -> some View {
        let code = account.code(at: date)
        HStack(spacing: 14) {
            CountdownIndicator(entry: account.entry, date: date)

            VStack(alignment: .leading, spacing: 2) {
                Text(code.groupedOTP)
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.3), value: code)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityIdentifier("code-\(account.displayTitle)")

                Text(account.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                if let subtitle = account.displaySubtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.body)
                    .foregroundStyle(isCopied ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)

                if account.hasPrefix {
                    Label("PIN", systemImage: "key.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: .capsule)
                        .help("A fixed prefix is added before the code when copying or using AutoFill")
                }
            }
        }
        .padding(style == .card ? 16 : 0)
        .padding(.vertical, style == .row ? 4 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if style == .card {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(PlatformColors.secondarySystemGroupedBackground)
            }
        }
        .contentShape(.rect(cornerRadius: style == .card ? 16 : 0))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(code: code, date: date))
        .accessibilityHint("Copies the code")
        .accessibilityAddTraits(.isButton)
    }

    private func accessibilityLabel(code: String, date: Date) -> String {
        var parts = [account.displayTitle]
        if let subtitle = account.displaySubtitle { parts.append(subtitle) }
        parts.append(code.map(String.init).joined(separator: " "))
        if !account.entry.isHotp {
            parts.append(String(localized: "\(account.entry.secondsRemaining(at: date)) seconds left"))
        }
        if isCopied { parts.append(String(localized: "Copied")) }
        return parts.joined(separator: ", ")
    }
}

/// Circular countdown for TOTP; counter badge for HOTP.
struct CountdownIndicator: View {
    let entry: OtpEntry
    let date: Date

    @ScaledMetric(relativeTo: .title2) private var size: CGFloat = 44

    var body: some View {
        Group {
            if let interval = entry.interval {
                let remaining = entry.secondsRemaining(at: date)
                Gauge(value: Double(remaining), in: 0...interval) {
                    EmptyView()
                } currentValueLabel: {
                    Text("\(remaining)")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(remaining <= 5 ? .red : .accentColor)
                .animation(.smooth(duration: 0.3), value: remaining)
            } else {
                Image(systemName: "arrow.trianglehead.clockwise")
                    .font(.headline)
                    .foregroundStyle(.tint)
                    .frame(width: size, height: size)
                    .background(.tint.opacity(0.12), in: .circle)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview("Row") {
    List {
        AccountCodeView(account: .preview(issuer: "Example Corp", name: "user@example.com", prefix: "1234"))
        AccountCodeView(account: .preview(issuer: "GitHub", name: "octocat"), isCopied: true)
    }
}

#Preview("Card") {
    AccountCodeView(account: .preview(issuer: "Example Corp", name: "user@example.com", prefix: "1234"), style: .card)
        .padding()
        .background(PlatformColors.systemGroupedBackground)
}

extension OtpModel {
    /// Sample account for previews (RFC 6238 test secret).
    static func preview(issuer: String, name: String, prefix: String? = nil) -> OtpModel {
        OtpModel(issuer: issuer, name: name, prefix: prefix,
                 entry: .totp(key: Data("12345678901234567890".utf8), digits: 6, interval: 30))
    }
}
