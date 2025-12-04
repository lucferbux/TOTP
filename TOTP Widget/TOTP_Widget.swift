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
struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "TOTP Account Configuration" }
    static var description: IntentDescription { "Choose which TOTP account to display in the widget." }

    // Allow selecting the account to display in the widget
    @Parameter(title: "Account", default: "Red Hat")
    var account: String
    
    // For multiple account support in medium and large widgets
    @Parameter(title: "Show Multiple Accounts", default: false)
    var showMultipleAccounts: Bool
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

struct WidgetPlatformPasteboard {
    static func copyToClipboard(_ text: String) {
        // Widgets cannot directly access the pasteboard
        // This functionality is handled by the App Intent instead
        #if canImport(UIKit)
        // For widgets, we'll use a URL scheme to trigger the main app
        // The actual copying will be handled in the app intent
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
    
    func get_display_value() -> Int {
        switch self {
        case let .totp(_, _, interval):
            let time = Date().timeIntervalSince1970
            let nextUpdate = Double(ceil(time / interval) * interval)
            return Int((nextUpdate - time).rounded())
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
struct Provider: AppIntentTimelineProvider {
    typealias Entry = TOTPEntry
    typealias Intent = ConfigurationAppIntent
    
    // Load accounts from shared UserDefaults with proper decryption
    private func loadAccounts() -> [WidgetOtpModel] {
        let suiteName = "group.com.lucferbux.TOTP"
        let userDefaults = UserDefaults(suiteName: suiteName) ?? UserDefaults.standard
        let accountsKey = "stored_totp_accounts"
        
        guard let data = userDefaults.data(forKey: accountsKey) else {
            return sampleAccounts // Fallback to sample data
        }
        
        // Get the shared encryption key
        guard let encryptionKey = getSharedEncryptionKey() else {
            print("Widget: Unable to access encryption key")
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
                        print("Widget: Failed to decrypt account \(storedAccount.issuer ?? "Unknown"): \(error)")
                        // Skip corrupted accounts
                    }
                }
            }
            
            return loadedAccounts.isEmpty ? sampleAccounts : loadedAccounts
            
        } catch {
            print("Widget: Failed to decode accounts: \(error)")
            return sampleAccounts // Fallback to sample data if loading fails
        }
    }
    
    // Helper function to get shared encryption key
    private func getSharedEncryptionKey() -> SymmetricKey? {
        let service = "TOTP-SharedData-Encryption"
        let account = "master-key"
        let accessGroup = "group.com.lucferbux.TOTP"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let keyData = result as? Data {
            return SymmetricKey(data: keyData)
        }
        
        return nil
    }
    
    // Helper function to decrypt data
    private func decryptData(_ encryptedData: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try ChaChaPoly.SealedBox(combined: encryptedData)
        return try ChaChaPoly.open(sealedBox, using: key)
    }
    
    // Sample data for previews and fallback
    let sampleAccounts = [
        WidgetOtpModel(
            issuer: "Red Hat",
            name: "lferrnan",
            prefix: "34asdfQ!a",
            entry: .totp(key: Data(base64Encoded: "12312asdfqewrasdfasdfasdf==")!, digits: 6, interval: 30.0)
        ),
        WidgetOtpModel(
            issuer: "GitHub",
            name: "dev@example.com",
            prefix: nil,
            entry: .totp(key: Data(base64Encoded: "12312asdfqewrasdfasdfasdf==")!, digits: 6, interval: 30.0)
        ),
        WidgetOtpModel(
            issuer: "AWS",
            name: "admin",
            prefix: "AWS:",
            entry: .totp(key: Data(base64Encoded: "12312asdfqewrasdfasdfasdf==")!, digits: 6, interval: 30.0)
        )
    ]
    
    func placeholder(in context: Context) -> TOTPEntry {
        TOTPEntry(date: Date(), accounts: [sampleAccounts[0]], configuration: ConfigurationAppIntent())
    }
    
    func snapshot(for configuration: Intent, in context: Context) async -> TOTPEntry {
        let allAccounts = loadAccounts()
        let displayAccounts: [WidgetOtpModel]
        
        if configuration.showMultipleAccounts {
            displayAccounts = Array(allAccounts.prefix(context.family.compactSize()))
        } else {
            let selectedAccount = allAccounts.first { $0.issuer == configuration.account } ?? allAccounts.first ?? sampleAccounts[0]
            displayAccounts = [selectedAccount]
        }
        
        return TOTPEntry(
            date: Date(),
            accounts: displayAccounts,
            configuration: configuration
        )
    }
    
    func timeline(for configuration: Intent, in context: Context) async -> Timeline<TOTPEntry> {
        var entries: [TOTPEntry] = []
        let currentDate = Date()
        
        // Load actual account data from shared UserDefaults
        let allAccounts = loadAccounts()
        let displayAccounts: [WidgetOtpModel]
        
        if configuration.showMultipleAccounts {
            displayAccounts = Array(allAccounts.prefix(context.family.compactSize()))
        } else {
            let selectedAccount = allAccounts.first { $0.issuer == configuration.account } ?? allAccounts.first ?? sampleAccounts[0]
            displayAccounts = [selectedAccount]
        }
        
        // Generate timeline entries for the next few TOTP updates (every 30 seconds)
        for secondOffset in stride(from: 0, to: 300, by: 30) {
            let entryDate = Calendar.current.date(byAdding: .second, value: secondOffset, to: currentDate)!
            let entry = TOTPEntry(
                date: entryDate,
                accounts: displayAccounts,
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
    let accounts: [WidgetOtpModel]
    let configuration: ConfigurationAppIntent
}

// Extension to determine how many accounts to show based on widget size
extension WidgetFamily {
    func compactSize() -> Int {
        switch self {
        case .systemSmall:
            return 1
        case .systemMedium:
            return 2
        case .systemLarge, .systemExtraLarge:
            return 4
        case .accessoryCircular:
            return 1
        case .accessoryRectangular:
            return 1
        case .accessoryInline:
            return 1
        @unknown default:
            return 1
        }
    }
}

// Single TOTP View for small widgets or individual items in larger widgets
@available(iOS 26.0, macOS 26.0, *)
struct SingleTOTPView: View {
    @Environment(\.widgetFamily) private var family
    let account: WidgetOtpModel
    let date: Date
    @State private var progress: Double = 1.0
    @State private var timeRemaining: Int = 30
    
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
        let codeString = String(format: "%06d", code) // Format as 6-digit string for URL
        let prefix = account.prefix ?? ""
        
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedCode)
                    .font(.system(family == .systemSmall ? .headline : .title3, design: .monospaced))
                    .fontWeight(.bold)
                    .contentTransition(.numericText())
                
                if let name = account.name, family != .systemSmall {
                    Text(account.issuer)
                        .font(.system(family == .systemSmall ? .caption : .body))
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Progress ring with gradient
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 3)
                    .frame(width: 28, height: 28)
                Circle()
                    .trim(from: 0, to: calculateProgress())
                    .stroke(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 28, height: 28)
                    .rotationEffect(.degrees(-90))
            }
            
            Button {
                // This button will open the URL scheme to communicate with the main app
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.tint)
                    .padding(10)
                    .glassEffect(.regular)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .widgetURL(URL(string: "totp://copy?code=\(prefix)\(codeString)"))
        }
        .padding(.horizontal, family == .systemSmall ? 8 : 12)
        .padding(.vertical, family == .systemSmall ? 6 : 10)
        .glassEffect(.regular.interactive())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    func calculateProgress() -> CGFloat {
        switch account.entry {
        case let .totp(_, _, interval):
            let time = date.timeIntervalSince1970
            let intervalTime = time.truncatingRemainder(dividingBy: interval)
            return CGFloat(intervalTime / interval)
        }
    }
    
    func calculateTimeRemaining() -> Int {
        switch account.entry {
        case let .totp(_, _, interval):
            let time = date.timeIntervalSince1970
            let nextUpdate = Double(ceil(time / interval) * interval)
            return Int((nextUpdate - time).rounded())
        }
    }
}

// Main widget view that adapts to different sizes
@available(iOS 26.0, macOS 26.0, *)
struct TOTP_WidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: Provider.Entry
    
    var body: some View {
        VStack(spacing: 10) {
            switch family {
            case .systemSmall:
                let accountsToShow = min(2, entry.accounts.count)
                ForEach(0..<accountsToShow, id: \.self) { index in
                    SingleTOTPView(account: entry.accounts[index], date: entry.date)
                }
            case .systemMedium:
                let accountsToShow = min(2, entry.accounts.count)
                HStack {
                    ForEach(0..<accountsToShow, id: \.self) { index in
                        SingleTOTPView(account: entry.accounts[index], date: entry.date)
                    }
                }
            case .systemLarge, .systemExtraLarge:
                let accountsToShow = min(4, entry.accounts.count)
                ForEach(0..<accountsToShow, id: \.self) { index in
                    SingleTOTPView(account: entry.accounts[index], date: entry.date)
                }
            case .accessoryCircular:
                if let account = entry.accounts.first {
                    VStack {
                        Text("\(account.entry.code())")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText())
                    }
                }
            case .accessoryRectangular:
                if let account = entry.accounts.first {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.issuer)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(account.entry.code())")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .contentTransition(.numericText())
                    }
                }
            case .accessoryInline:
                if let account = entry.accounts.first {
                    Text("\(account.issuer): \(account.entry.code())")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
            @unknown default:
                let accountsToShow = min(2, entry.accounts.count)
                ForEach(0..<accountsToShow, id: \.self) { index in
                    SingleTOTPView(account: entry.accounts[index], date: entry.date)
                }
            }
        }
        .padding(family == .systemSmall ? 8 : 12)
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .configurationDisplayName("TOTP Codes")
        .description("Display your TOTP authentication codes.")
    }
}

// Previews for the widget
#Preview(as: .systemSmall) {
    TOTP_Widget()
} timeline: {
    let accounts = [
        WidgetOtpModel(
            issuer: "Red Hat",
            name: "lferrnan",
            prefix: "34asdfQ!a",
            entry: .totp(key: Data(base64Encoded: "12312asdfqewrasdfasdfasdf==")!, digits: 6, interval: 30.0)
        ),
        WidgetOtpModel(
            issuer: "GitHub",
            name: "dev@example.com",
            prefix: nil,
            entry: .totp(key: Data(base64Encoded: "12312asdfqewrasdfasdfasdf==")!, digits: 6, interval: 30.0)
        )
    ]
    
    let intent = ConfigurationAppIntent()
    //intent.showMultipleAccounts = true
    
    TOTPEntry(date: .now, accounts: accounts, configuration: intent)
}

#Preview(as: .systemMedium) {
    TOTP_Widget()
} timeline: {
    let accounts = [
        WidgetOtpModel(
            issuer: "Red Hat",
            name: "lferrnan",
            prefix: "34asdfQ!a",
            entry: .totp(key: Data(base64Encoded: "12312asdfqewrasdfasdfasdf==")!, digits: 6, interval: 30.0)
        ),
        WidgetOtpModel(
            issuer: "GitHub",
            name: "dev@example.com",
            prefix: nil,
            entry: .totp(key: Data(base64Encoded: "12312asdfqewrasdfasdfasdf==")!, digits: 6, interval: 30.0)
        )
    ]
    
    let intent = ConfigurationAppIntent()
    //intent.showMultipleAccounts = true
    
    TOTPEntry(date: .now, accounts: accounts, configuration: intent)
}

#Preview(as: .systemLarge) {
    TOTP_Widget()
} timeline: {
    let accounts = [
        WidgetOtpModel(
            issuer: "Red Hat",
            name: "lferrnan",
            prefix: "34asdfQ!a",
            entry: .totp(key: Data(base64Encoded: "12312asdfqewrasdfasdfasdf==")!, digits: 6, interval: 30.0)
        ),
        WidgetOtpModel(
            issuer: "GitHub",
            name: "dev@example.com",
            prefix: nil,
            entry: .totp(key: Data(base64Encoded: "12312asdfqewrasdfasdfasdf==")!, digits: 6, interval: 30.0)
        ),
        WidgetOtpModel(
            issuer: "AWS",
            name: "admin",
            prefix: "AWS:",
            entry: .totp(key: Data(base64Encoded: "12312asdfqewrasdfasdfasdf==")!, digits: 6, interval: 30.0)
        ),
        WidgetOtpModel(
            issuer: "Microsoft",
            name: "work@company.com",
            prefix: "MS-",
            entry: .totp(key: Data(base64Encoded: "12312asdfqewrasdfasdfasdf==")!, digits: 6, interval: 30.0)
        )
    ]
    
    let intent = ConfigurationAppIntent()
    //intent.showMultipleAccounts = true
    
    TOTPEntry(date: .now, accounts: accounts, configuration: intent)
}
