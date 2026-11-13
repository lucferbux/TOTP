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
    /// The panel outlives its window: closing it only orders it out, so without this the rows
    /// would keep redrawing every second for as long as the app runs.
    @State private var isPanelVisible = true
    /// The row Return copies, moved with ↑ and ↓ while typing in the search field.
    @State private var highlightedID: UUID?
    @FocusState private var searchFocused: Bool

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
        TimelineView(.codeTicks(paused: !isPanelVisible)) { context in
            VStack(spacing: rowSpacing) {
                ForEach(filteredAccounts) { account in
                    MenuBarAccountRow(
                        account: account,
                        date: context.date,
                        isCopied: copiedAccountId == account.id,
                        isHighlighted: highlightedID == account.id
                    ) {
                        copyCode(for: account)
                    }
                    .frame(height: rowHeight)
                }
            }
            .padding(.vertical, 4)
        }
        // Start the timeline afresh when the panel reopens, so it never keeps a paused schedule
        .id(isPanelVisible)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "lock.shield.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                Text("TOTP Password")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if lock.isLocked {
                lockedContent
            } else {
                // Search field: focused when the panel opens, so typing filters straight away;
                // ↑/↓ pick a row, Return copies it, Esc clears.
                if !syncManager.accounts.isEmpty {
                    searchField
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
        .background { WindowVisibilityReader(isVisible: $isPanelVisible) }
        .task {
            // The main window is suppressed when the app starts at login,
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

    private var searchField: some View {
        TextField("Search accounts", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .focused($searchFocused)
            .onSubmit {
                if let account = highlightedAccount {
                    copyCode(for: account)
                }
            }
            .onKeyPress(.downArrow) {
                moveHighlight(by: 1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                moveHighlight(by: -1)
                return .handled
            }
            .onKeyPress(.escape) {
                guard !searchText.isEmpty else { return .ignored }
                searchText = ""
                return .handled
            }
            .onChange(of: searchText) { _, _ in
                highlightedID = filteredAccounts.first?.id
            }
            .onChange(of: isPanelVisible, initial: true) { _, visible in
                guard visible else { return }
                highlightedID = filteredAccounts.first?.id
                searchFocused = true
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
    }

    private var highlightedAccount: OtpModel? {
        filteredAccounts.first { $0.id == highlightedID } ?? filteredAccounts.first
    }

    private func moveHighlight(by offset: Int) {
        let accounts = filteredAccounts
        guard !accounts.isEmpty else { return }
        let current = accounts.firstIndex { $0.id == highlightedID } ?? -offset
        let next = min(max(current + offset, 0), accounts.count - 1)
        highlightedID = accounts[next].id
    }

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
            if let message = lock.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
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
                Button("Add Account…") {
                    MacOSAppSettings.shared.showMainWindow(openWindow: openWindow)
                    AppRouter.shared.requestsNewAccount = true
                }
                .padding(.top, 4)
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
            Text(verbatim: "⌘\(String(shortcut).uppercased())")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: - Actions

    private func copyCode(for account: OtpModel) {
        ClipboardManager.copy(syncManager.useCode(for: account))
        Task {
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
    var isHighlighted = false
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        let code = account.code(at: date)
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
                                .accessibilityLabel("PIN")
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
                    Text(code.groupedOTP)
                        .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered || isHighlighted ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.15) : .clear)
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
        .accessibilityLabel(accessibilityLabel(code: code))
        .accessibilityHint("Copies the code")
    }

    /// Digits read one by one, plus the time left and whether a PIN is added.
    private func accessibilityLabel(code: String) -> String {
        var parts = [account.displayTitle]
        if let subtitle = account.displaySubtitle { parts.append(subtitle) }
        parts.append(code.map(String.init).joined(separator: " "))
        if !account.entry.isHotp {
            parts.append(String(localized: "\(account.entry.secondsRemaining(at: date)) seconds left"))
        }
        if account.hasPrefix { parts.append(String(localized: "Includes PIN")) }
        if isCopied { parts.append(String(localized: "Copied")) }
        return parts.joined(separator: ", ")
    }
}
#endif
