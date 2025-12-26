//
//  TOTP_Widget.swift
//  TOTP Widget
//
//  Created by Lucas Fernández Aragón on 4/3/25.
//

import WidgetKit
import SwiftUI
import Foundation
import CryptoKit
import AppIntents

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Widget Configuration Intent
@available(iOS 26.0, macOS 26.0, *)
struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "TOTP Account Configuration" }
    static var description: IntentDescription { "Choose which TOTP account to display in the widget." }

    // Allow selecting the account to display in the widget
    @Parameter(title: "Account", default: "Red Hat")
    var account: String
}

// MARK: - Widget Platform Utilities
struct WidgetPlatformColors {
    static var systemBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemBackground)
        #else
        return Color(NSColor.windowBackgroundColor)
        #endif
    }
}

// Simplified versions of the app models for widget use
enum WidgetOtpEntry {
    case totp(key: Data, digits: Int, interval: Double)
    
    func code() -> UInt64 {
        switch self {
        case let .totp(key, digits, interval):
            let counter = UInt64(Date().timeIntervalSince1970 / interval)
            return hotpCode(key: key, digits: digits, counter: counter)
        }
    }
}

struct WidgetOtpModel: Identifiable {
    let id = UUID()
    var issuer: String
    var name: String?
    var prefix: String?
    var entry: WidgetOtpEntry
}

// Storage model for reading shared data
private struct StoredOtpAccount: Codable {
    let id: String
    let issuer: String?
    let name: String?
    let prefix: String?
    let encryptedKey: Data
    let isHotp: Bool
    let digits: Int
    let interval: Double
    let counter: Int64
    let createdDate: Date
    let modifiedDate: Date
}

// HOTP Code generation function copied from the main app
func hotpCode(key: Data, digits: Int = 6, counter: UInt64) -> UInt64 {
    let counterBytes = (0..<8).reversed().map { UInt8(counter >> (8 * $0) & 0xff) }
    let hash = HMAC<Insecure.SHA1>.authenticationCode(for: counterBytes, using: SymmetricKey(data: key))
    let offset = Int(hash.suffix(1)[0] & 0x0f)
    let hash32 = hash
        .dropFirst(offset)
        .prefix(4)
        .reduce(0, { ($0 << 8) | UInt32($1) })
    let hash31 = hash32 & 0x7FFF_FFFF
    let pad = String(repeating: "0", count: digits)
    return UInt64(String((pad + String(hash31)).suffix(digits)))!
}

// Provider that handles timeline generation
@available(iOS 26.0, macOS 26.0, *)
struct Provider: AppIntentTimelineProvider {
    typealias Entry = TOTPEntry
    typealias Intent = ConfigurationAppIntent
    
    // Load accounts from shared UserDefaults with proper decryption
    private func loadAccounts() -> [WidgetOtpModel] {
        let suiteName = "group.com.lucferbux.TOTP"
        
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            return sampleAccounts
        }
        
        let accountsKey = "stored_totp_accounts"
        
        guard let data = userDefaults.data(forKey: accountsKey) else {
            return sampleAccounts // Fallback to sample data
        }
        
        // Get the shared encryption key
        guard let encryptionKey = getSharedEncryptionKey() else {
            return sampleAccounts
        }
        
        do {
            let decoder = JSONDecoder()
            let storedAccounts = try decoder.decode([StoredOtpAccount].self, from: data)
            
            var loadedAccounts: [WidgetOtpModel] = []
            
            for storedAccount in storedAccounts {
                // Only support TOTP for widgets (not HOTP)
                if !storedAccount.isHotp {
                    do {
                        // Decrypt the key data
                        let decryptedKey = try decryptData(storedAccount.encryptedKey, using: encryptionKey)
                        
                        let widgetModel = WidgetOtpModel(
                            issuer: storedAccount.issuer ?? "Unknown",
                            name: storedAccount.name,
                            prefix: storedAccount.prefix,
                            entry: .totp(
                                key: decryptedKey,
                                digits: storedAccount.digits,
                                interval: storedAccount.interval
                            )
                        )
                        loadedAccounts.append(widgetModel)
                    } catch {
                        // Skip corrupted accounts
                    }
                }
            }
            
            if loadedAccounts.isEmpty {
                return sampleAccounts
            }
            
            return loadedAccounts
            
        } catch {
            return sampleAccounts // Fallback to sample data if loading fails
        }
    }
    
    // Helper function to get shared encryption key from App Group container file
    private static let keyFileName = ".totp-encryption-key"
    
    private func getSharedContainerURL() -> URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.lucferbux.TOTP")
    }
    
    private func getSharedEncryptionKey() -> SymmetricKey? {
        guard let containerURL = getSharedContainerURL() else {
            return nil
        }
        
        let keyFileURL = containerURL.appendingPathComponent(Self.keyFileName)
        
        do {
            let keyData = try Data(contentsOf: keyFileURL)
            return SymmetricKey(data: keyData)
        } catch {
            return nil
        }
    }
    
    // Helper function to decrypt data
    private func decryptData(_ encryptedData: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try ChaChaPoly.SealedBox(combined: encryptedData)
        return try ChaChaPoly.open(sealedBox, using: key)
    }
    
    // Sample data for previews and fallback
    // Using valid base64 encoded sample key data
    private static let sampleKeyData = Data([0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x21, 0xde, 0xad, 0xbe, 0xef])
    
    let sampleAccounts = [
        WidgetOtpModel(
            issuer: "Red Hat",
            name: "lferrnan",
            prefix: "34asdfQ!a",
            entry: .totp(key: sampleKeyData, digits: 6, interval: 30.0)
        ),
        WidgetOtpModel(
            issuer: "GitHub",
            name: "dev@example.com",
            prefix: nil,
            entry: .totp(key: sampleKeyData, digits: 6, interval: 30.0)
        ),
        WidgetOtpModel(
            issuer: "AWS",
            name: "admin",
            prefix: "AWS:",
            entry: .totp(key: sampleKeyData, digits: 6, interval: 30.0)
        )
    ]
    
    func placeholder(in context: Context) -> TOTPEntry {
        TOTPEntry(date: Date(), account: sampleAccounts[0], configuration: ConfigurationAppIntent())
    }
    
    func snapshot(for configuration: Intent, in context: Context) async -> TOTPEntry {
        let allAccounts = loadAccounts()
        let selectedAccount = allAccounts.first { $0.issuer == configuration.account } ?? allAccounts.first ?? sampleAccounts[0]
        
        return TOTPEntry(
            date: Date(),
            account: selectedAccount,
            configuration: configuration
        )
    }
    
    func timeline(for configuration: Intent, in context: Context) async -> Timeline<TOTPEntry> {
        var entries: [TOTPEntry] = []
        let currentDate = Date()
        
        // Load actual account data from shared UserDefaults
        let allAccounts = loadAccounts()
        let selectedAccount = allAccounts.first { $0.issuer == configuration.account } ?? allAccounts.first ?? sampleAccounts[0]
        
        // Generate timeline entries for the next few TOTP updates (every 30 seconds)
        for secondOffset in stride(from: 0, to: 300, by: 30) {
            let entryDate = Calendar.current.date(byAdding: .second, value: secondOffset, to: currentDate)!
            let entry = TOTPEntry(
                date: entryDate,
                account: selectedAccount,
                configuration: configuration
            )
            entries.append(entry)
        }
        
        return Timeline(entries: entries, policy: .atEnd)
    }
}

// The entry type that will be displayed in the widget
struct TOTPEntry: TimelineEntry {
    let date: Date
    let account: WidgetOtpModel
    let configuration: ConfigurationAppIntent
}

// Single TOTP View for small widgets or individual items in larger widgets
@available(iOS 26.0, macOS 26.0, *)
struct SingleTOTPView: View {
    @Environment(\.widgetFamily) private var family
    let account: WidgetOtpModel
    let date: Date
    
    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.minimumIntegerDigits = 6 // Default to 6 digits
        return formatter
    }
    
    var body: some View {
        let code = account.entry.code()
        let formattedCode = numberFormatter.string(from: NSNumber(value: code)) ?? "------"
        let codeString = String(format: "%06d", code)
        let prefix = account.prefix ?? ""
        let fullCode = "\(prefix)\(codeString)"
        
        // Make the entire card tappable with URL scheme
        Link(destination: URL(string: "totp://copy?code=\(fullCode)")!) {
            VStack(spacing: 8) {
                // Account info header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.issuer)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let name = account.name {
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                }
                
                Spacer()
                
                // TOTP Code - sized to fit widget
                Text(formattedCode)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                
                Spacer()
                
                // Tap to copy hint
                HStack(spacing: 4) {
                    Image(systemName: "hand.tap.fill")
                        .font(.caption2)
                    Text("Tap to copy")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            .padding(12)
        }
    }
}

// Main widget view for small size only
@available(iOS 26.0, macOS 26.0, *)
struct TOTP_WidgetEntryView: View {
    var entry: Provider.Entry
    
    var body: some View {
        SingleTOTPView(account: entry.account, date: entry.date)
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

// The widget configuration
@available(iOS 26.0, macOS 26.0, *)
struct TOTP_Widget: Widget {
    let kind: String = "TOTP_Widget"
    
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            TOTP_WidgetEntryView(entry: entry)
        }
        .supportedFamilies([.systemSmall])
        .configurationDisplayName("TOTP Code")
        .description("Display and copy your TOTP authentication code. Tap to copy.")
    }
}

// Preview for the widget
#Preview(as: .systemSmall) {
    TOTP_Widget()
} timeline: {
    // Using valid sample key data for preview
    let sampleKeyData = Data([0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x21, 0xde, 0xad, 0xbe, 0xef])
    let sampleAccount = WidgetOtpModel(
        issuer: "Red Hat",
        name: "lferrnan",
        prefix: "34asdfQ!a",
        entry: .totp(key: sampleKeyData, digits: 6, interval: 30.0)
    )
    
    let intent = ConfigurationAppIntent()
    
    TOTPEntry(date: .now, account: sampleAccount, configuration: intent)
}
