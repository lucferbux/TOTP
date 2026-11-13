//
//  CodeComplication.swift
//  TOTP Watch Widget
//
//  A complication showing one account's code. It reads the watch's sealed copy of the accounts
//  (written by the watch app) with the watch's device-only key, and never creates that key.
//  With the app lock on, nothing is decrypted: the iPhone didn't even send the accounts.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Configuration

struct WatchAccountEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    static let defaultQuery = WatchAccountQuery()

    let id: UUID
    let title: String
    let subtitle: String?

    var displayRepresentation: DisplayRepresentation {
        if let subtitle {
            DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
        } else {
            DisplayRepresentation(title: "\(title)")
        }
    }
}

struct WatchAccountQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [WatchAccountEntity] {
        Self.all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WatchAccountEntity] {
        Self.all()
    }

    /// Issuer and name only, read from the records' metadata — no secret is opened to list them.
    static func all() -> [WatchAccountEntity] {
        guard case .ready = WatchAccountCache.status() else { return [] }
        return AccountStore.storedRecords().filter { !$0.isHotp }.compactMap { record in
            guard let id = UUID(uuidString: record.id) else { return nil }
            let model = OtpModel(id: id, issuer: record.issuer, name: record.name,
                                 entry: .totp(key: Data(), digits: record.digits, interval: record.interval))
            return WatchAccountEntity(id: id, title: model.displayTitle, subtitle: model.displaySubtitle)
        }
    }
}

struct WatchCodeConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Account"
    static let description = IntentDescription("Choose the account to show.")

    @Parameter(title: "Account")
    var account: WatchAccountEntity?

    init() {}

    init(account: WatchAccountEntity?) {
        self.account = account
    }
}

// MARK: - Timeline

struct ComplicationEntry: TimelineEntry {
    enum State: Equatable {
        case ready
        case noAccounts
        /// Before the first unlock after a restart the key can't be read.
        case unavailable
        /// The app lock is on on the iPhone.
        case locked
    }

    let date: Date
    let account: OtpModel?
    let state: State

    static let placeholder = ComplicationEntry(
        date: .now,
        account: OtpModel(issuer: "Example Corp", name: "user@example.com",
                          entry: .totp(key: Data("12345678901234567890".utf8), digits: 6, interval: 30)),
        state: .ready
    )
}

struct ComplicationProvider: AppIntentTimelineProvider {
    /// Code periods rendered ahead; WidgetKit asks again at the end.
    static let periods = 10

    func placeholder(in context: Context) -> ComplicationEntry {
        .placeholder
    }

    func snapshot(for configuration: WatchCodeConfigurationIntent, in context: Context) async -> ComplicationEntry {
        if context.isPreview { return .placeholder }
        let (account, state) = load(configuration)
        return ComplicationEntry(date: .now, account: account, state: state)
    }

    func timeline(for configuration: WatchCodeConfigurationIntent, in context: Context) async -> Timeline<ComplicationEntry> {
        let now = Date.now
        let (account, state) = load(configuration)
        guard state == .ready, let account else {
            // Locked and empty only change when the watch app receives new data, and it reloads
            // every timeline when it does.
            let policy: TimelineReloadPolicy = state == .unavailable ? .after(now.addingTimeInterval(15 * 60)) : .never
            return Timeline(entries: [ComplicationEntry(date: now, account: nil, state: state)], policy: policy)
        }
        let entries = CodeTimeline.refreshDates(for: [account.entry], now: now, count: Self.periods).map {
            ComplicationEntry(date: $0, account: account, state: .ready)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    func recommendations() -> [AppIntentRecommendation<WatchCodeConfigurationIntent>] {
        let accounts = WatchAccountQuery.all()
        guard !accounts.isEmpty else {
            return [AppIntentRecommendation(intent: WatchCodeConfigurationIntent(), description: "TOTP Code")]
        }
        return accounts.prefix(10).map { account in
            AppIntentRecommendation(intent: WatchCodeConfigurationIntent(account: account),
                                    description: "\(account.title)")
        }
    }

    private func load(_ configuration: WatchCodeConfigurationIntent) -> (OtpModel?, ComplicationEntry.State) {
        // Checked before any key is read, so a locked app's data is never even looked at.
        switch WatchAccountCache.status() {
        case .locked: return (nil, .locked)
        case .neverSynced: return (nil, .noAccounts)
        case .ready: break
        }
        guard let key = WatchKeyStore.existingKey() else { return (nil, .unavailable) }
        guard case let .ready(accounts) = WatchAccountCache.load(key: key), !accounts.isEmpty else {
            return (nil, .noAccounts)
        }
        let chosen = configuration.account.flatMap { entity in accounts.first { $0.id == entity.id } }
        return (chosen ?? accounts.first, .ready)
    }
}

// MARK: - Views

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    let entry: ComplicationEntry

    var body: some View {
        Group {
            if let account = entry.account, entry.state == .ready {
                codeView(account)
            } else {
                messageView
            }
        }
        .containerBackground(for: .widget) {
            if family == .accessoryCircular {
                AccessoryWidgetBackground()
            }
        }
    }

    private func code(for account: OtpModel) -> String {
        let code = account.code(at: entry.date)
        return isLuminanceReduced ? code.maskedOTP : code.groupedOTP
    }

    @ViewBuilder
    private func codeView(_ account: OtpModel) -> some View {
        let code = code(for: account)
        switch family {
        case .accessoryInline:
            Text(verbatim: "\(account.displayTitle) \(code)")
                .privacySensitive()
        case .accessoryCircular:
            ZStack {
                countdown(account)
                    .progressViewStyle(.circular)
                VStack(spacing: -2) {
                    // Two short lines read better in the circle than one tiny one.
                    ForEach(Array(code.split(separator: " ").enumerated()), id: \.offset) { _, group in
                        Text(group)
                    }
                }
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .minimumScaleFactor(0.5)
                .padding(5)
                .privacySensitive()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(account))
        case .accessoryCorner:
            Text(code.replacingOccurrences(of: " ", with: ""))
                .font(.system(.body, design: .monospaced, weight: .bold))
                .minimumScaleFactor(0.5)
                .privacySensitive()
                .widgetCurvesContent()
                .widgetLabel {
                    countdown(account)
                }
                .accessibilityLabel(accessibilityLabel(account))
        default:
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(account.displayTitle)
                        .font(.headline)
                        .widgetAccentable()
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let end = account.entry.nextRefresh(after: entry.date), !isLuminanceReduced {
                        Text(timerInterval: entry.date...end, countsDown: true, showsHours: false)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 40, alignment: .trailing)
                    }
                }
                Text(code)
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .privacySensitive()
                if let subtitle = account.displaySubtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(account))
        }
    }

    @ViewBuilder
    private func countdown(_ account: OtpModel) -> some View {
        if let end = account.entry.nextRefresh(after: entry.date),
           let start = account.entry.periodStart(containing: entry.date) {
            ProgressView(timerInterval: start...end, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(.accentColor)
        }
    }

    private func accessibilityLabel(_ account: OtpModel) -> String {
        guard !isLuminanceReduced else { return account.displayTitle }
        return [account.displayTitle, account.code(at: entry.date).spokenOTP].joined(separator: ", ")
    }

    @ViewBuilder
    private var messageView: some View {
        let isLocked = entry.state == .locked
        let symbol = isLocked ? "lock.fill" : "key.fill"
        switch family {
        case .accessoryInline:
            Label(isLocked ? "Locked on iPhone" : "TOTP", systemImage: symbol)
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Label("TOTP", systemImage: symbol)
                    .font(.headline)
                    .widgetAccentable()
                Text(isLocked ? "Unlock TOTP on your iPhone" : entry.state == .unavailable ? "Unlock your watch" : "Open TOTP on your iPhone to add accounts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryCorner:
            Image(systemName: symbol)
                .font(.title3)
                .widgetLabel(isLocked ? "Locked" : "TOTP")
        default:
            Image(systemName: symbol)
                .font(.title3)
                .accessibilityLabel(isLocked ? "Locked on iPhone" : "No accounts")
        }
    }
}

// MARK: - Widget

struct CodeComplication: Widget {
    let kind = "TOTPWatchCodeComplication"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WatchCodeConfigurationIntent.self, provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry)
        }
        .configurationDisplayName("TOTP Code")
        .description("A live code for one of your accounts.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

#Preview("Rectangular", as: .accessoryRectangular) {
    CodeComplication()
} timeline: {
    ComplicationEntry.placeholder
    ComplicationEntry(date: .now, account: nil, state: .locked)
}

#Preview("Circular", as: .accessoryCircular) {
    CodeComplication()
} timeline: {
    ComplicationEntry.placeholder
}

#Preview("Corner", as: .accessoryCorner) {
    CodeComplication()
} timeline: {
    ComplicationEntry.placeholder
}
