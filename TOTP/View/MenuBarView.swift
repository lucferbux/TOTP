//
//  MenuBarView.swift
//  TOTP
//
//  macOS menu bar popover showing all TOTP entries with one-click copy.
//

#if os(macOS)
import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject private var syncManager: SyncManager
    @ObservedObject private var lock = AppLockManager.shared
    @Environment(\.openWindow) private var openWindow
    @State private var searchText = ""
    @State private var copiedAccountId: UUID?

    /// Height per account row, so the overall list height is deterministic.
    private let rowHeight: CGFloat = 52
    private let rowSpacing: CGFloat = 2

    /// Maximum list height before the list becomes scrollable.
    private let maxListHeight: CGFloat = 320

    /// Natural (unclamped) height the account rows want to occupy.
    private var naturalListHeight: CGFloat {
        let count = CGFloat(filteredAccounts.count)
        return count * rowHeight + max(0, count - 1) * rowSpacing + 8 // + vertical padding
    }

    private var filteredAccounts: [OtpModel] {
        syncManager.accounts.filter { $0.matches(search: searchText) }
    }

    /// The account rows as a plain `VStack`. A `VStack` always reports a definite
    /// height, so it renders reliably inside the `.window`-style MenuBarExtra —
    /// unlike a `ScrollView`, whose ideal height along its scroll axis is ~0, which
    /// makes it collapse to nothing when the popover sizes itself to fit its content.
    private var accountRows: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: rowSpacing) {
                ForEach(filteredAccounts) { account in
                    MenuBarAccountRow(
                        account: account,
                        date: context.date,
                        isCopied: copiedAccountId == account.id
                    ) {
                        copyCode(for: account)
                    }
                    .frame(height: rowHeight)
                }
            }
            .padding(.vertical, 4)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "lock.shield.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                Text("TOTP Authenticator")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if lock.isLocked {
                lockedContent
            } else {
                // Search field
                if syncManager.accounts.count > 3 {
                    TextField("Search accounts", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }

                Divider()

                // Account list
                if filteredAccounts.isEmpty {
                    emptyContent
                } else if naturalListHeight <= maxListHeight {
                    // Everything fits — render the rows directly (no ScrollView).
                    accountRows
                } else {
                    // Too many accounts to fit — scroll, with an explicit height so the
                    // ScrollView has a concrete size instead of collapsing.
                    ScrollView {
                        accountRows
                    }
                    .frame(height: maxListHeight)
                }
            }

            Divider()

            // Footer actions
            VStack(spacing: 0) {
                footerButton("Open TOTP", systemImage: "macwindow", shortcut: "o") {
                    MacOSAppSettings.shared.showMainWindow(openWindow: openWindow)
                }
                SettingsLink {
                    footerLabel("Settings…", systemImage: "gearshape", shortcut: ",")
                }
                .buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: .command)
                Divider()
                    .padding(.horizontal, 12)
                footerButton("Quit TOTP", systemImage: "power", shortcut: "q") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 320)
        .task {
            // The main window is suppressed at launch (`.defaultLaunchBehavior(.suppressed)`),
            // so `initializeSync()` may not have run yet when the app starts straight into the
            // menu bar. Load locally-stored accounts so the list is populated without first
            // having to open the main window.
            if syncManager.accounts.isEmpty {
                SharedDataManager.shared.loadAccounts()
            }
            syncManager.startIfNeeded()
        }
    }

    // MARK: - Subviews

    private var lockedContent: some View {
        VStack(spacing: 10) {
            Divider()
            Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            Text("Codes are locked")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                Task { await lock.unlock() }
            } label: {
                Label("Unlock with \(lock.methodName)", systemImage: lock.methodSymbol)
            }
            .prominentActionStyle()
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyContent: some View {
        VStack(spacing: 8) {
            Image(systemName: syncManager.accounts.isEmpty ? "lock.shield" : "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(syncManager.accounts.isEmpty ? "No accounts" : "No results")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if syncManager.accounts.isEmpty {
                Text("Open TOTP to add accounts")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func footerButton(_ title: LocalizedStringKey, systemImage: String, shortcut: Character, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            footerLabel(title, systemImage: systemImage, shortcut: shortcut)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(shortcut), modifiers: .command)
    }

    private func footerLabel(_ title: LocalizedStringKey, systemImage: String, shortcut: Character) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
            Spacer()
            Text("⌘\(String(shortcut).uppercased())")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: - Actions

    private func copyCode(for account: OtpModel) {
        Task {
            let value = await syncManager.useCode(for: account)
            ClipboardManager.copy(value)
            withAnimation(.smooth(duration: 0.2)) {
                copiedAccountId = account.id
            }
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.smooth(duration: 0.3)) {
                if copiedAccountId == account.id {
                    copiedAccountId = nil
                }
            }
        }
    }
}

// MARK: - Account Row

struct MenuBarAccountRow: View {
    let account: OtpModel
    let date: Date
    let isCopied: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                CountdownIndicator(entry: account.entry, date: date)
                    .frame(width: 32, height: 32)
                    .scaleEffect(32 / 44)

                // Account info
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(account.displayTitle)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        if account.hasPrefix {
                            Image(systemName: "key.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .help("A fixed prefix is added before the code when copying")
                        }
                    }
                    if let subtitle = account.displaySubtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Code or copied indicator
                if isCopied {
                    Label("Copied", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text(account.code(at: date).groupedOTP)
                        .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.15) : .clear)
            }
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .accessibilityLabel("\(account.displayTitle), \(account.code(at: date))")
        .accessibilityHint("Copies the code")
    }
}
#endif
