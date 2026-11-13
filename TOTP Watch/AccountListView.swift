//
//  AccountListView.swift
//  TOTP Watch
//

import SwiftUI

struct AccountListView: View {
    @ObservedObject var model: WatchAccountsModel
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("TOTP")
                .navigationDestination(for: UUID.self) { id in
                    if let account = model.accounts.first(where: { $0.id == id }) {
                        AccountDetailView(account: account)
                    } else {
                        // The account went away (deleted or the lock was turned on) while open.
                        MessageView(state: model.state)
                    }
                }
        }
        .onAppear(perform: openScreenshotSceneIfNeeded)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case let .ready(accounts) where !accounts.isEmpty:
            List(accounts) { account in
                NavigationLink(value: account.id) {
                    AccountRowView(account: account)
                }
                .accessibilityIdentifier("account-\(account.displayTitle)")
            }
        default:
            MessageView(state: model.state)
        }
    }

    private func openScreenshotSceneIfNeeded() {
        guard WatchEnvironment.screenshotScene == "detail", path.isEmpty,
              let first = model.accounts.first else { return }
        path = [first.id]
    }
}

/// Empty and locked states.
struct MessageView: View {
    let state: WatchAccountCache.State

    var body: some View {
        switch state {
        case .locked:
            ContentUnavailableView {
                Label("Locked on iPhone", systemImage: "lock.fill")
            } description: {
                Text("Unlock TOTP on your iPhone")
            }
        default:
            ContentUnavailableView {
                Label("No Accounts", systemImage: "key.fill")
            } description: {
                Text("Open TOTP on your iPhone to add accounts")
            }
        }
    }
}

struct AccountRowView: View {
    let account: OtpModel

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        TimelineView(.codeTicks(paused: isLuminanceReduced)) { context in
            let code = account.code(at: context.date)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(account.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                }
                HStack(spacing: 8) {
                    Text(isLuminanceReduced ? code.maskedOTP : code.groupedOTP)
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                        .contentTransition(.numericText())
                        .animation(.smooth(duration: 0.3), value: code)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .privacySensitive()
                    Spacer(minLength: 0)
                    CountdownRing(entry: account.entry, date: context.date, size: 26, lineWidth: 3)
                }
                if let subtitle = account.displaySubtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(code: code, date: context.date))
        }
        // Start the timeline afresh when the screen wakes, so it never keeps a paused schedule
        .id(isLuminanceReduced)
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

#Preview("List") {
    AccountListView(model: .shared)
}

#Preview("Row") {
    List {
        AccountRowView(account: OtpModel(issuer: "Example Corp", name: "user@example.com",
                                         entry: .totp(key: Data("12345678901234567890".utf8), digits: 6, interval: 30)))
    }
}

#Preview("Locked") {
    MessageView(state: .locked)
}

#Preview("Empty") {
    MessageView(state: .neverSynced)
}
