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
        #if canImport(UIKit)
        UIPasteboard.general.string = text
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
    var entry: WidgetOtpEntry
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
    // Sample data for previews
    let sampleAccounts = [
        WidgetOtpModel(
            issuer: "Red Hat",
            name: "lferrnan",
            entry: .totp(key: Data(base64Encoded: "qo5y1y7LIewn/CFrv7AOPn+UjjQ=")!, digits: 6, interval: 30.0)
        ),
        WidgetOtpModel(
            issuer: "GitHub",
            name: "dev@example.com",
            entry: .totp(key: Data(base64Encoded: "qo5y1y7LIewn/CFrv7AOPn+UjjQ=")!, digits: 6, interval: 30.0)
        ),
        WidgetOtpModel(
            issuer: "AWS",
            name: "admin",
            entry: .totp(key: Data(base64Encoded: "qo5y1y7LIewn/CFrv7AOPn+UjjQ=")!, digits: 6, interval: 30.0)
        )
    ]
    
    func placeholder(in context: Context) -> TOTPEntry {
        TOTPEntry(date: Date(), accounts: [sampleAccounts[0]], configuration: ConfigurationAppIntent())
    }
    
    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> TOTPEntry {
        // For snapshot, we'll just use sample data
        let displayAccounts: [WidgetOtpModel]
        
        if configuration.showMultipleAccounts {
            displayAccounts = Array(sampleAccounts.prefix(context.family.compactSize()))
        } else {
            let selectedAccount = sampleAccounts.first { $0.issuer == configuration.account } ?? sampleAccounts[0]
            displayAccounts = [selectedAccount]
        }
        
        return TOTPEntry(
            date: Date(),
            accounts: displayAccounts,
            configuration: configuration
        )
    }
    
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<TOTPEntry> {
        var entries: [TOTPEntry] = []
        let currentDate = Date()
        
        // In a real app, you'd fetch actual account data from shared UserDefaults or an App Group
        let displayAccounts: [WidgetOtpModel]
        
        if configuration.showMultipleAccounts {
            displayAccounts = Array(sampleAccounts.prefix(context.family.compactSize()))
        } else {
            let selectedAccount = sampleAccounts.first { $0.issuer == configuration.account } ?? sampleAccounts[0]
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
        
        HStack {
            // Progress circle
//            ZStack {
//                Circle()
//                    .fill(LinearGradient(
//                        gradient: Gradient(colors: [Color.blue, Color.green]),
//                        startPoint: .topLeading,
//                        endPoint: .bottomTrailing
//                    ))
//                    .frame(width: family == .systemSmall ? 60 : 70, height: family == .systemSmall ? 60 : 70)
//                
//                Circle()
//                    .trim(from: 0, to: calculateProgress())
//                    .stroke(style: StrokeStyle(lineWidth: 4.0, lineCap: .round, lineJoin: .round))
//                    .frame(width: family == .systemSmall ? 56 : 66, height: family == .systemSmall ? 56 : 66)
//                    .foregroundColor(.white)
//                    .brightness(0.2)
//                    .rotationEffect(.degrees(-90))
//                
//                Text("\(calculateTimeRemaining())")
//                    .foregroundColor(.white)
//                    .font(.system(.headline, design: .monospaced))
//            }
            
            VStack(alignment: .leading) {
                Text(formattedCode)
                    .font(.system(family == .systemSmall ? .headline : .title3, design: .monospaced))
                    .fontWeight(.bold)
                
                if let name = account.name, family != .systemSmall {
                    Text(account.issuer)
                        .font(.system(family == .systemSmall ? .caption : .body))
                        .lineLimit(1)
                    Text(name)
                        .font(.caption)
                        .opacity(0.7)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Button(intent: CopyTOTPCodeIntent(code: "3bB!Qhxo\(code)")) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(10)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, family == .systemSmall ? 8 : 12)
        .padding(.vertical, family == .systemSmall ? 6 : 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(WidgetPlatformColors.systemBackground)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
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
struct TOTP_WidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: Provider.Entry
    
    var body: some View {
        VStack(spacing: 10) {
            switch family {
            case .systemSmall:
                let accountsToShow = min(2, entry.accounts.count)
//                if let account = entry.accounts.first {
//                    SingleTOTPView(account: account, date: entry.date)
//                }
                ForEach(0..<accountsToShow, id: \.self) { index in
                    SingleTOTPView(account: entry.accounts[index], date: entry.date)
                }
            case .systemMedium:
                let accountsToShow = min(2, entry.accounts.count)
                HStack() {
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
                    }
                }
            case .accessoryRectangular:
                if let account = entry.accounts.first {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.issuer)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(account.entry.code())")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                    }
                }
            case .accessoryInline:
                if let account = entry.accounts.first {
                    Text("\(account.issuer): \(account.entry.code())")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
            @unknown default:
//                if let account = entry.accounts.first {
//                    SingleTOTPView(account: account, date: entry.date)
//                }
                let accountsToShow = min(2, entry.accounts.count)
                ForEach(0..<accountsToShow, id: \.self) { index in
                    SingleTOTPView(account: entry.accounts[index], date: entry.date)
                }
            }
        }
        .padding(family == .systemSmall ? 8 : 10)
    }
}

// Intent for copy button
struct CopyTOTPCodeIntent: AppIntent {
    static var title: LocalizedStringResource = "Copy TOTP Code"
    static var description = IntentDescription("Copy the TOTP code to clipboard")
    
    @Parameter(title: "TOTP Code")
    var code: String
    
    init() {
        self.code = ""
    }
    
    init(code: String) {
        self.code = code
    }
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // The real copy happens via pasteboard
        WidgetPlatformPasteboard.copyToClipboard(self.code)
        return .result(dialog: "Copied to clipboard")
    }
}

// The widget configuration
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
            entry: .totp(key: Data(base64Encoded: "qo5y1y7LIewn/CFrv7AOPn+UjjQ=")!, digits: 6, interval: 30.0)
        ),
        WidgetOtpModel(
            issuer: "GitHub",
            name: "dev@example.com",
            entry: .totp(key: Data(base64Encoded: "qo5y1y7LIewn/CFrv7AOPn+UjjQ=")!, digits: 6, interval: 30.0)
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
            entry: .totp(key: Data(base64Encoded: "qo5y1y7LIewn/CFrv7AOPn+UjjQ=")!, digits: 6, interval: 30.0)
        ),
        WidgetOtpModel(
            issuer: "GitHub",
            name: "dev@example.com",
            entry: .totp(key: Data(base64Encoded: "qo5y1y7LIewn/CFrv7AOPn+UjjQ=")!, digits: 6, interval: 30.0)
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
            entry: .totp(key: Data(base64Encoded: "qo5y1y7LIewn/CFrv7AOPn+UjjQ=")!, digits: 6, interval: 30.0)
        ),
        WidgetOtpModel(
            issuer: "GitHub",
            name: "dev@example.com",
            entry: .totp(key: Data(base64Encoded: "qo5y1y7LIewn/CFrv7AOPn+UjjQ=")!, digits: 6, interval: 30.0)
        ),
        WidgetOtpModel(
            issuer: "AWS",
            name: "admin",
            entry: .totp(key: Data(base64Encoded: "qo5y1y7LIewn/CFrv7AOPn+UjjQ=")!, digits: 6, interval: 30.0)
        ),
        WidgetOtpModel(
            issuer: "Microsoft",
            name: "work@company.com",
            entry: .totp(key: Data(base64Encoded: "qo5y1y7LIewn/CFrv7AOPn+UjjQ=")!, digits: 6, interval: 30.0)
        )
    ]
    
    let intent = ConfigurationAppIntent()
    //intent.showMultipleAccounts = true
    
    TOTPEntry(date: .now, accounts: accounts, configuration: intent)
}
