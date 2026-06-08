//
//  MenuBarView.swift
//  TOTP
//
//  macOS menu bar popover showing all TOTP entries with one-click copy.
//

#if os(macOS)
import SwiftUI
import AppKit

@available(macOS 26.0, *)
struct MenuBarView: View {
    @EnvironmentObject private var syncManager: SyncManager
    @Environment(\.openWindow) private var openWindow
    @State private var searchText = ""
    @State private var copiedAccountId: UUID?
    @State private var tickCounter = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Fixed height per account row, so the overall list height is deterministic.
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
        let accounts = syncManager.accounts
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if search.isEmpty { return accounts }
        return accounts.filter {
            $0.issuer?.localizedCaseInsensitiveContains(search) ?? false
            || $0.name?.localizedCaseInsensitiveContains(search) ?? false
        }
    }

    /// The account rows as a plain `VStack`. A `VStack` always reports a definite
    /// height, so it renders reliably inside the `.window`-style MenuBarExtra —
    /// unlike a `ScrollView`, whose ideal height along its scroll axis is ~0, which
    /// makes it collapse to nothing when the popover sizes itself to fit its content.
    @ViewBuilder
    private var accountRows: some View {
        VStack(spacing: rowSpacing) {
            ForEach(filteredAccounts) { account in
                MenuBarAccountRow(
                    account: account,
                    isCopied: copiedAccountId == account.id,
                    tickCounter: tickCounter
                ) {
                    copyCode(for: account)
                }
                .frame(height: rowHeight)
            }
        }
        .padding(.vertical, 4)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "lock.shield.fill")
                    .font(.title3)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("TOTP Authenticator")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            // Search field
            if syncManager.accounts.count > 3 {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("Search accounts...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            
            Divider()
            
            // Account list
            if filteredAccounts.isEmpty {
                VStack(spacing: 12) {
                    if syncManager.accounts.isEmpty {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("No accounts")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Open the app to add accounts")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                        Text("No results")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else if naturalListHeight <= maxListHeight {
                // Everything fits — render the rows directly (no ScrollView), exactly
                // like the footer below, which is why it renders reliably here.
                accountRows
            } else {
                // Too many accounts to fit — scroll, with an explicit height so the
                // ScrollView has a concrete size instead of collapsing.
                ScrollView {
                    accountRows
                }
                .frame(height: maxListHeight)
            }
            
            Divider()
            
            // Footer actions
            VStack(spacing: 0) {
                Button(action: {
                    MacOSAppSettings.shared.showMainWindow(openWindow: openWindow)
                }) {
                    HStack {
                        Image(systemName: "macwindow")
                            .font(.subheadline)
                        Text("Open Main Window")
                            .font(.subheadline)
                        Spacer()
                        Text("⌘O")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    if isHovered {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                
                Divider()
                    .padding(.horizontal, 12)
                
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack {
                        Image(systemName: "power")
                            .font(.subheadline)
                        Text("Quit TOTP")
                            .font(.subheadline)
                        Spacer()
                        Text("⌘Q")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    if isHovered {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 320)
        .onReceive(timer) { _ in
            tickCounter += 1
        }
        .task {
            // The main window is suppressed at launch (`.defaultLaunchBehavior(.suppressed)`),
            // so `initializeSync()` may not have run yet when the app starts straight into the
            // menu bar. Load locally-stored accounts so the list is populated without first
            // having to open the main window.
            if syncManager.accounts.isEmpty {
                SharedDataManager.shared.loadAccounts()
            }
        }
    }
    
    private func copyCode(for account: OtpModel) {
        let value = account.generateAutoFillValue()
        PlatformPasteboard.copyToClipboard(value)
        
        withAnimation(.smooth(duration: 0.2)) {
            copiedAccountId = account.id
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.smooth(duration: 0.3)) {
                if copiedAccountId == account.id {
                    copiedAccountId = nil
                }
            }
        }
    }
}

// MARK: - Account Row

@available(macOS 26.0, *)
struct MenuBarAccountRow: View {
    let account: OtpModel
    let isCopied: Bool
    let tickCounter: Int
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    private var currentCode: String {
        // Recalculates every time tickCounter changes (every second)
        _ = tickCounter
        return account.generateCode()
    }
    
    private var displayCode: String {
        let code = currentCode
        // Insert a space in the middle for readability (e.g., "123 456")
        if code.count == 6 {
            let mid = code.index(code.startIndex, offsetBy: 3)
            return "\(code[code.startIndex..<mid]) \(code[mid...])"
        }
        return code
    }
    
    private var countdown: Int {
        _ = tickCounter
        return account.entry.get_display_value()
    }
    
    private var progress: Double {
        _ = tickCounter
        if case let .totp(_, _, interval) = account.entry {
            let time = Date().timeIntervalSince1970
            let nextUpdate = Double(ceil(time / interval) * interval)
            return 1.0 - ((nextUpdate - time) / interval)
        }
        return 0
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Countdown circle
                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 2)
                        .frame(width: 32, height: 32)
                    
                    Circle()
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .frame(width: 32, height: 32)
                        .rotationEffect(.degrees(-90))
                    
                    Text("\(countdown)")
                        .font(.system(.caption2, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
                
                // Account info
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.issuer ?? "Unknown")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    if let name = account.name, !name.isEmpty {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Code or copied indicator
                if isCopied {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text("Copied")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.green)
                    }
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Text(displayCode)
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
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
    }
}
#endif
