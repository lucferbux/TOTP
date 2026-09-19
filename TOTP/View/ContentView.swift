//
//  ContentView.swift
//  TOTP
//
//  Main list of codes. Adapts to the available width through size classes only, so it
//  works the same on iPhone, iPhone Duo (folded / unfolded), iPad split views and Mac.
//

import SwiftUI
import Combine

/// Routes deep links (otpauth://) and menu commands into the main window.
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published var pendingImport: OtpAuthURL?
    @Published var importError: String?
}

/// Lets ⌘N (File ▸ Add Account) reach the focused window.
struct AddAccountAction: Equatable {
    let perform: () -> Void

    func callAsFunction() { perform() }

    // The action always does the same thing for a given window; don't invalidate on identity.
    static func == (lhs: AddAccountAction, rhs: AddAccountAction) -> Bool { true }
}

extension FocusedValues {
    @Entry var addAccountAction: AddAccountAction?
}

enum AccountSheet: Identifiable {
    case add(OtpAuthURL?)
    case edit(OtpModel)
    case settings

    var id: String {
        switch self {
        case .add: "add"
        case .edit(let account): "edit-\(account.id)"
        case .settings: "settings"
        }
    }
}

public struct ContentView: View {
    @EnvironmentObject private var syncManager: SyncManager
    @ObservedObject private var dataManager = SharedDataManager.shared
    @ObservedObject private var router = AppRouter.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var search = ""
    @State private var sheet: AccountSheet?
    @State private var deleting: OtpModel?
    @State private var copiedAccountID: UUID?
    @State private var copyCount = 0

    public init() {}

    private var filteredAccounts: [OtpModel] {
        syncManager.accounts.filter { $0.matches(search: search) }
    }

    private var usesCompactList: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Codes")
                .searchable(text: $search, prompt: "Search accounts")
                .toolbar { toolbarContent }
                .safeAreaInset(edge: .top) { syncBanner }
                .overlay(alignment: .bottom) { copiedToast }
                .refreshable { await syncManager.refresh() }
        }
        .focusedSceneValue(\.addAccountAction, AddAccountAction { sheet = .add(nil) })
        .sensoryFeedback(.success, trigger: copyCount)
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { account in
            Button("Delete Account", role: .destructive) {
                Task { await syncManager.deleteAccount(account) }
            }
            .accessibilityIdentifier("confirmDeleteButton")
        } message: { _ in
            Text("You won't be able to generate codes for this account unless you add it again.")
        }
        .alert("Data Error", isPresented: Binding(get: { dataManager.error != nil }, set: { if !$0 { dataManager.error = nil } })) {
            Button("OK", role: .cancel) { dataManager.error = nil }
        } message: {
            Text(dataManager.error?.localizedDescription ?? "")
        }
        .alert("Can't Add Account", isPresented: Binding(get: { router.importError != nil }, set: { if !$0 { router.importError = nil } })) {
            Button("OK", role: .cancel) { router.importError = nil }
        } message: {
            Text(router.importError ?? "")
        }
        .onChange(of: router.pendingImport) { _, pending in
            guard let pending else { return }
            sheet = .add(pending)
            router.pendingImport = nil
        }
        .onAppear {
            if let pending = router.pendingImport {
                sheet = .add(pending)
                router.pendingImport = nil
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 320)
        #endif
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if syncManager.accounts.isEmpty {
            if syncManager.isLoading {
                ProgressView("Loading accounts…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState
            }
        } else if filteredAccounts.isEmpty {
            ContentUnavailableView.search(text: search)
        } else if usesCompactList {
            compactList
        } else {
            regularGrid
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Accounts", systemImage: "lock.shield")
        } description: {
            Text("Add an account by scanning its setup QR code or entering the secret key.")
        } actions: {
            Button("Add Account") { sheet = .add(nil) }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("emptyStateAddButton")
        }
    }

    /// iPhone, iPhone Duo folded, iPad slide-over / narrow splits.
    private var compactList: some View {
        List {
            ForEach(filteredAccounts) { account in
                Button {
                    copy(account)
                } label: {
                    AccountCodeView(account: account, style: .row, isCopied: copiedAccountID == account.id)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("account-\(account.displayTitle)")
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { deleting = account } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button { sheet = .edit(account) } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
                .swipeActions(edge: .leading) {
                    Button { copy(account) } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .tint(.green)
                }
                .contextMenu { accountMenu(account) }
            }
            .onMove(perform: search.isEmpty ? { source, destination in
                syncManager.moveAccounts(fromOffsets: source, toOffset: destination)
            } : nil)
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    /// iPad, iPhone Duo unfolded, Mac: adaptive columns that reflow continuously with width.
    private var regularGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 480), spacing: 16)], spacing: 16) {
                ForEach(filteredAccounts) { account in
                    Button {
                        copy(account)
                    } label: {
                        AccountCodeView(account: account, style: .card, isCopied: copiedAccountID == account.id)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("account-\(account.displayTitle)")
                    .contextMenu { accountMenu(account) }
                }
            }
            .padding()
        }
        .background(PlatformColors.systemGroupedBackground)
    }

    @ViewBuilder
    private func accountMenu(_ account: OtpModel) -> some View {
        Button { copy(account) } label: {
            Label("Copy Code", systemImage: "doc.on.doc")
        }
        .accessibilityIdentifier("copyAction")
        Button { sheet = .edit(account) } label: {
            Label("Edit", systemImage: "pencil")
        }
        .accessibilityIdentifier("editAction")
        Divider()
        Button(role: .destructive) { deleting = account } label: {
            Label("Delete", systemImage: "trash")
        }
        .accessibilityIdentifier("deleteAction")
    }

    // MARK: - Chrome

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .topBarLeading) {
            Button { sheet = .settings } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .accessibilityIdentifier("settingsButton")
        }
        if usesCompactList && search.isEmpty && syncManager.accounts.count > 1 {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        #endif
        ToolbarItem(placement: .primaryAction) {
            Button { sheet = .add(nil) } label: {
                Label("Add Account", systemImage: "plus")
            }
            .accessibilityIdentifier("addAccountButton")
            .help("Add a new account")
        }
    }

    @ViewBuilder
    private var syncBanner: some View {
        if syncManager.syncState.isError || syncManager.syncState == .offline {
            SyncStatusBanner(syncState: syncManager.syncState) {
                Task { await syncManager.refresh() }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var copiedToast: some View {
        if copiedAccountID != nil {
            Label("Copied", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.multicolor)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("copiedToast")
                .task(id: copyCount) {
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation(.smooth(duration: 0.3)) { copiedAccountID = nil }
                }
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: AccountSheet) -> some View {
        switch sheet {
        case .add(let prefill):
            AddingPageView(prefill: prefill)
                .environmentObject(syncManager)
        case .edit(let account):
            AddingPageView(editingAccount: account)
                .environmentObject(syncManager)
        case .settings:
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { self.sheet = nil }
                        }
                    }
            }
        }
    }

    private var deleteTitle: String {
        guard let deleting else { return "" }
        return String(localized: "Delete \(deleting.displayTitle)?")
    }

    // MARK: - Actions

    private func copy(_ account: OtpModel) {
        Task {
            let value = await syncManager.useCode(for: account)
            ClipboardManager.copy(value)
            withAnimation(.smooth(duration: 0.25)) {
                copiedAccountID = account.id
            }
            copyCount += 1
            AccessibilityNotification.Announcement("Code copied").post()
        }
    }
}

// MARK: - Sync Status

struct SyncStatusBanner: View {
    let syncState: SyncState
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: syncState.systemImage)
                .foregroundStyle(.orange)
            Text(bannerMessage)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            if syncState == .iCloudDisabled {
                Button("Settings") { SystemSettings.openAppSettings() }
                    .font(.subheadline.weight(.medium))
            } else {
                Button("Retry") { onRetry?() }
                    .font(.subheadline.weight(.medium))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.15), in: .rect(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private var bannerMessage: String {
        switch syncState {
        case .iCloudDisabled:
            String(localized: "iCloud sync is off. Sign in to iCloud to sync across devices.")
        case .error(let message):
            message
        case .offline:
            String(localized: "You're offline. Changes will sync when you reconnect.")
        default:
            ""
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SyncManager.shared)
}
