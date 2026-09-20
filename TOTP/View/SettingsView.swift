//
//  SettingsView.swift
//  TOTP
//
//  Settings: a sheet on iPhone/iPad, the ⌘, window on macOS.
//

import SwiftUI
import AuthenticationServices
import CloudKit

#if os(macOS)
import ServiceManagement
#endif

struct SettingsView: View {
    @EnvironmentObject private var syncManager: SyncManager
    @ObservedObject private var lock = AppLockManager.shared
    @State private var cloudRecordCount: Int?
    @State private var isChecking = false
    @State private var clipboardClearSeconds = AppPreferences.clipboardClearSeconds
    @State private var allowUniversalClipboard = AppPreferences.allowUniversalClipboard
    #if os(macOS)
    @ObservedObject private var macSettings = MacOSAppSettings.shared
    #endif

    var body: some View {
        Form {
            iCloudSection
            securitySection
            #if os(macOS)
            macGeneralSection
            #endif
            autoFillSection
            aboutSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 420, idealHeight: 520)
        #endif
        .onChange(of: clipboardClearSeconds) { _, seconds in
            AppPreferences.clipboardClearSeconds = seconds
        }
    }

    // MARK: - Sections

    private var iCloudSection: some View {
        Section {
            LabeledContent {
                Text(syncManager.syncState.description)
                    .foregroundStyle(syncManager.syncState.isError ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            } label: {
                Label("Status", systemImage: syncManager.syncState.systemImage)
            }
            LabeledContent("Accounts on This Device", value: "\(syncManager.accounts.count)")
            LabeledContent("Accounts in iCloud") {
                if isChecking {
                    ProgressView().controlSize(.small)
                } else {
                    Text(cloudRecordCount.map(String.init) ?? "—")
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("Encryption Key", value: EncryptionKeyManager.shared.usesSharedKey ? "Shared via iCloud Keychain" : "This device only")
            LabeledContent("Environment", value: CloudKitDataManager.shared.environmentName)
            LabeledContent("Container", value: CloudKitDataManager.shared.containerIdentifier)
                .font(.caption)
            Button {
                Task { await refreshDiagnostics() }
            } label: {
                Label("Sync Now", systemImage: "arrow.clockwise.icloud")
            }
            .accessibilityIdentifier("syncNowButton")
        } header: {
            Text("iCloud Sync")
        } footer: {
            if !EncryptionKeyManager.shared.usesSharedKey {
                Text("Turn on iCloud Keychain so this device can share its encryption key — without it, codes synced from other devices can't be read.")
            } else {
                Text("Accounts sync through your private iCloud database. Secrets stay encrypted with a key shared only through your iCloud Keychain.")
            }
        }
        .task {
            await refreshDiagnostics()
        }
    }

    @MainActor
    private func refreshDiagnostics() async {
        isChecking = true
        defer { isChecking = false }
        await syncManager.refresh()
        cloudRecordCount = syncManager.iCloudAvailable ? CloudKitDataManager.shared.accounts.count : nil
    }

    private var securitySection: some View {
        Section {
            Toggle(isOn: Binding(get: { lock.isEnabled }, set: { newValue in
                Task { await lock.setEnabled(newValue) }
            })) {
                Label("Require \(lock.methodName)", systemImage: lock.methodSymbol)
            }
            .disabled(!lock.canAuthenticate)
            .accessibilityIdentifier("appLockToggle")

            Picker(selection: $clipboardClearSeconds) {
                ForEach(AppPreferences.clipboardClearOptions, id: \.self) { seconds in
                    Text(clipboardLabel(seconds)).tag(seconds)
                }
            } label: {
                Label("Clear Copied Codes", systemImage: "clipboard")
            }
            .accessibilityIdentifier("clipboardClearPicker")

            Toggle(isOn: $allowUniversalClipboard) {
                Label("Share Clipboard With Other Devices", systemImage: "rectangle.on.rectangle")
            }
            .accessibilityIdentifier("universalClipboardToggle")
        } header: {
            Text("Security")
        } footer: {
            Text("""
            With the lock on, TOTP asks for \(lock.methodName) before showing codes — and before AutoFill,             Shortcuts or the Control Center control hand one over. Copied codes are removed from the clipboard             after the chosen time, and stay on this device unless you allow sharing with your other Apple devices.
            """)
        }
        .onChange(of: allowUniversalClipboard) { _, allow in
            AppPreferences.allowUniversalClipboard = allow
        }
    }

    #if os(macOS)
    private var macGeneralSection: some View {
        Section {
            Toggle("Launch TOTP at Login", isOn: $macSettings.launchAtLogin)
            Toggle("Show Dock Icon", isOn: $macSettings.showDockIcon)
            LabeledContent("Login Item", value: loginItemStatusText)
        } header: {
            Text("General")
        } footer: {
            Text("When the Dock icon is hidden, open TOTP from its menu bar icon. On macOS 27, menu bar icons that don't fit are in the menu bar's overflow area.")
        }
    }

    private var loginItemStatusText: String {
        switch macSettings.loginItemStatus {
        case .enabled: String(localized: "Enabled")
        case .notRegistered: String(localized: "Off")
        case .requiresApproval: String(localized: "Requires Approval")
        case .notFound: String(localized: "Not Found")
        @unknown default: String(localized: "Unknown")
        }
    }
    #endif

    private var autoFillSection: some View {
        Section {
            Button {
                ASSettingsHelper.openCredentialProviderAppSettings { _ in }
            } label: {
                Label("AutoFill Settings", systemImage: "key.viewfinder")
            }
        } header: {
            Text("AutoFill")
        } footer: {
            Text("Turn on TOTP under AutoFill & Passwords to fill codes, including any fixed prefix, on websites and in apps.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: appVersion)
            LabeledContent("Build", value: appBuild)
            // App Review 5.1.1(i): the privacy policy must be reachable from inside the app.
            Link(destination: URL(string: "https://lucferbux.github.io/TOTP/privacy.html")!) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }
            .accessibilityIdentifier("privacyPolicyLink")
            Link(destination: URL(string: "https://lucferbux.github.io/TOTP/support.html")!) {
                Label("Support", systemImage: "questionmark.circle")
            }
        } header: {
            Text("About")
        } footer: {
            Text("TOTP doesn't collect any data. Your accounts stay on your devices and in your own iCloud.")
        }
    }

    // MARK: - Helpers

    private func clipboardLabel(_ seconds: Int) -> String {
        switch seconds {
        case 0: String(localized: "Never")
        case ..<60: String(localized: "After \(seconds) seconds")
        default: String(localized: "After \(seconds / 60) min")
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
