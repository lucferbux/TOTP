//
//  SettingsView.swift
//  TOTP
//
//  macOS Settings window (Cmd+,) with General preferences.
//

#if os(macOS)
import SwiftUI
import ServiceManagement

@available(macOS 26.0, *)
struct SettingsView: View {
    @StateObject private var settings = MacOSAppSettings.shared
    
    var body: some View {
        Form {
            // MARK: - General
            Section {
                Toggle("Launch TOTP at Login", isOn: $settings.launchAtLogin)
                
                HStack {
                    Toggle("Show Dock Icon", isOn: $settings.showDockIcon)
                    
                    Spacer()
                    
                    if !settings.showDockIcon {
                        Text("Menu bar only")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background {
                                Capsule()
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            }
                    }
                }
            } header: {
                Label("General", systemImage: "gear")
            } footer: {
                Text("When the Dock icon is hidden, access TOTP from the menu bar icon. The app will continue running in the background.")
            }
            
            // MARK: - Status
            Section {
                HStack {
                    Text("Login Item")
                    Spacer()
                    Text(loginItemStatusText)
                        .foregroundStyle(.secondary)
                    Circle()
                        .fill(loginItemStatusColor)
                        .frame(width: 8, height: 8)
                }
                
                HStack {
                    Text("Dock Visibility")
                    Spacer()
                    Text(settings.showDockIcon ? "Visible" : "Hidden")
                        .foregroundStyle(.secondary)
                    Circle()
                        .fill(settings.showDockIcon ? .green : .orange)
                        .frame(width: 8, height: 8)
                }
            } header: {
                Label("Status", systemImage: "info.circle")
            }
            
            // MARK: - About
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Build")
                    Spacer()
                    Text(appBuild)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("About", systemImage: "questionmark.circle")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 340)
        .navigationTitle("Settings")
    }
    
    // MARK: - Computed Properties
    
    private var loginItemStatusText: String {
        switch settings.loginItemStatus {
        case .enabled:
            return "Enabled"
        case .notRegistered:
            return "Disabled"
        case .requiresApproval:
            return "Requires Approval"
        case .notFound:
            return "Not Found"
        @unknown default:
            return "Unknown"
        }
    }
    
    private var loginItemStatusColor: Color {
        switch settings.loginItemStatus {
        case .enabled:
            return .green
        case .requiresApproval:
            return .orange
        default:
            return .secondary
        }
    }
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    
    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}
#endif
