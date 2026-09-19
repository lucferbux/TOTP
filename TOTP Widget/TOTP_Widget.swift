//
//  TOTP_Widget.swift
//  TOTP Widget
//
//  Created by Lucas Fernández Aragón on 4/3/25.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Configuration

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Account"
    static let description = IntentDescription("Choose the account to show.")

    @Parameter(title: "Account")
    var account: AccountEntity?
}

struct MultiAccountConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Accounts"
    static let description = IntentDescription("Choose the accounts to show.")

    @Parameter(title: "Accounts", size: [.systemMedium: 3, .systemLarge: 6])
    var accounts: [AccountEntity]?
}

// MARK: - Timeline

struct CodesEntry: TimelineEntry {
    enum State {
        case ready
        case noAccounts
        /// Data is protected until the device is unlocked once after a restart.
        case unavailable
    }

    let date: Date
    let accounts: [OtpModel]
    let state: State

    var account: OtpModel? { accounts.first }

    static let placeholder = CodesEntry(date: .now, accounts: [WidgetSamples.primary, WidgetSamples.secondary, WidgetSamples.tertiary], state: .ready)
}

enum WidgetSamples {
    private static let secret = Data("12345678901234567890".utf8)
    static let primary = OtpModel(issuer: "Example Corp", name: "user@example.com", prefix: "1234",
                                  entry: .totp(key: secret, digits: 6, interval: 30))
    static let secondary = OtpModel(issuer: "GitHub", name: "octocat", entry: .totp(key: secret, digits: 6, interval: 30))
    static let tertiary = OtpModel(issuer: "AWS", name: "admin", entry: .totp(key: secret, digits: 6, interval: 30))
}

enum CodesTimeline {
    /// Number of code periods rendered ahead; WidgetKit reloads at the end.
    static let periods = 10

    /// Entries aligned to period boundaries so every entry shows the code valid for its whole lifetime.
    static func entries(for accounts: [OtpModel], state: CodesEntry.State, now: Date = .now) -> [CodesEntry] {
        guard state == .ready, !accounts.isEmpty else {
            return [CodesEntry(date: now, accounts: accounts, state: state)]
        }
        return CodeTimeline.refreshDates(for: accounts.map(\.entry), now: now, count: periods).map { date in
            CodesEntry(date: date, accounts: accounts, state: state)
        }
    }

    static func load() -> (accounts: [OtpModel], state: CodesEntry.State) {
        guard EncryptionKeyManager.existingKey() != nil else { return ([], .unavailable) }
        let accounts = AccountQuery.models()
        return (accounts, accounts.isEmpty ? .noAccounts : .ready)
    }
}

struct SingleAccountProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CodesEntry {
        CodesEntry(date: .now, accounts: [WidgetSamples.primary], state: .ready)
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> CodesEntry {
        if context.isPreview { return placeholder(in: context) }
        let (accounts, state) = CodesTimeline.load()
        return CodesEntry(date: .now, accounts: select(configuration, from: accounts), state: state)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<CodesEntry> {
        let (accounts, state) = CodesTimeline.load()
        let entries = CodesTimeline.entries(for: select(configuration, from: accounts), state: state)
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func select(_ configuration: ConfigurationAppIntent, from accounts: [OtpModel]) -> [OtpModel] {
        if let id = configuration.account?.id, let match = accounts.first(where: { $0.id == id }) {
            return [match]
        }
        return Array(accounts.prefix(1))
    }
}

struct MultiAccountProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CodesEntry {
        .placeholder
    }

    func snapshot(for configuration: MultiAccountConfigurationIntent, in context: Context) async -> CodesEntry {
        if context.isPreview { return .placeholder }
        let (accounts, state) = CodesTimeline.load()
        return CodesEntry(date: .now, accounts: select(configuration, from: accounts, family: context.family), state: state)
    }

    func timeline(for configuration: MultiAccountConfigurationIntent, in context: Context) async -> Timeline<CodesEntry> {
        let (accounts, state) = CodesTimeline.load()
        let entries = CodesTimeline.entries(for: select(configuration, from: accounts, family: context.family), state: state)
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func select(_ configuration: MultiAccountConfigurationIntent, from accounts: [OtpModel], family: WidgetFamily) -> [OtpModel] {
        let limit = family == .systemLarge ? 6 : 3
        if let chosen = configuration.accounts, !chosen.isEmpty {
            let byID = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return chosen.compactMap { byID[$0.id] }.prefix(limit).map { $0 }
        }
        return Array(accounts.prefix(limit))
    }
}

// MARK: - Views

/// Wraps content in a tap-to-copy button when an account is available.
struct CopyButton<Label: View>: View {
    let account: OtpModel
    @ViewBuilder let label: Label

    var body: some View {
        Button(intent: CopyCodeIntent(account: AccountEntity(model: account))) {
            label
        }
        .buttonStyle(.plain)
    }
}

struct CodeCountdown: View {
    let account: OtpModel
    let date: Date

    var body: some View {
        if let end = account.entry.nextRefresh(after: date), let start = account.entry.periodStart(containing: date) {
            ProgressView(timerInterval: start...end, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(.accentColor)
        }
    }
}

struct SingleAccountWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CodesEntry

    var body: some View {
        Group {
            if let account = entry.account, entry.state == .ready {
                switch family {
                case .accessoryInline:
                    CopyButton(account: account) {
                        Text("\(account.displayTitle) \(account.code(at: entry.date).groupedOTP)")
                            .privacySensitive()
                    }
                case .accessoryCircular:
                    CopyButton(account: account) {
                        ZStack {
                            CodeCountdown(account: account, date: entry.date)
                            Text(account.code(at: entry.date))
                                .font(.system(.caption2, design: .monospaced, weight: .bold))
                                .minimumScaleFactor(0.5)
                                .padding(6)
                                .privacySensitive()
                        }
                    }
                case .accessoryRectangular:
                    CopyButton(account: account) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(account.displayTitle)
                                .font(.headline)
                                .widgetAccentable()
                                .lineLimit(1)
                            Text(account.code(at: entry.date).groupedOTP)
                                .font(.system(.title2, design: .monospaced, weight: .bold))
                                .minimumScaleFactor(0.6)
                                .privacySensitive()
                            if let end = account.entry.nextRefresh(after: entry.date) {
                                Text(timerInterval: entry.date...end, countsDown: true)
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                default:
                    CopyButton(account: account) {
                        SmallCodeView(account: account, date: entry.date)
                    }
                }
            } else {
                WidgetMessageView(state: entry.state)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct SmallCodeView: View {
    let account: OtpModel
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
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
                Spacer(minLength: 4)
                CodeCountdown(account: account, date: date)
                    .frame(width: 22, height: 22)
            }

            Spacer(minLength: 0)

            Text(account.code(at: date).groupedOTP)
                .font(.system(.title, design: .monospaced, weight: .bold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
                .privacySensitive()

            Spacer(minLength: 0)

            Label(account.hasPrefix ? "Tap to copy PIN + code" : "Tap to copy", systemImage: "doc.on.doc")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct MultiAccountWidgetView: View {
    let entry: CodesEntry

    var body: some View {
        Group {
            if entry.state == .ready, !entry.accounts.isEmpty {
                VStack(spacing: 6) {
                    ForEach(entry.accounts) { account in
                        CopyButton(account: account) {
                            HStack(spacing: 10) {
                                CodeCountdown(account: account, date: entry.date)
                                    .frame(width: 20, height: 20)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(account.displayTitle)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    if let subtitle = account.displaySubtitle {
                                        Text(subtitle)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 6)
                                Text(account.code(at: entry.date).groupedOTP)
                                    .font(.system(.title3, design: .monospaced, weight: .bold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                    .privacySensitive()
                            }
                            .frame(maxHeight: .infinity)
                        }
                        if account.id != entry.accounts.last?.id {
                            Divider()
                        }
                    }
                }
            } else {
                WidgetMessageView(state: entry.state == .ready ? .noAccounts : entry.state)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct WidgetMessageView: View {
    @Environment(\.widgetFamily) private var family
    let state: CodesEntry.State

    var body: some View {
        switch family {
        case .accessoryInline, .accessoryCircular:
            Image(systemName: "lock.shield")
        default:
            VStack(spacing: 6) {
                Image(systemName: state == .unavailable ? "lock.fill" : "lock.shield")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(state == .unavailable ? "Unlock your device to see codes" : "Add an account in TOTP")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Widgets

struct TOTP_Widget: Widget {
    let kind: String = "TOTP_Widget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: SingleAccountProvider()) { entry in
            SingleAccountWidgetView(entry: entry)
        }
        .configurationDisplayName("Code")
        .description("Shows one account's code. Tap to copy it, including any fixed prefix.")
        #if os(iOS)
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline, .accessoryCircular])
        #else
        .supportedFamilies([.systemSmall])
        #endif
    }
}

struct TOTP_MultiWidget: Widget {
    let kind: String = "TOTP_MultiWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: MultiAccountConfigurationIntent.self, provider: MultiAccountProvider()) { entry in
            MultiAccountWidgetView(entry: entry)
        }
        .configurationDisplayName("Codes")
        .description("Shows several accounts. Tap one to copy its code.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    TOTP_Widget()
} timeline: {
    CodesEntry(date: .now, accounts: [WidgetSamples.primary], state: .ready)
    CodesEntry(date: .now, accounts: [], state: .noAccounts)
}

#Preview("Medium", as: .systemMedium) {
    TOTP_MultiWidget()
} timeline: {
    CodesEntry.placeholder
}
