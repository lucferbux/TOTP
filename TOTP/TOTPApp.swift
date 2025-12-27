//
//  TOTPApp.swift
//  TOTP
//
//  Created by Lucas Fernández Aragón on 4/3/25.
//

import SwiftUI
import WidgetKit
import CloudKit

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

@available(iOS 26.0, macOS 26.0, *)
@main
struct TOTPApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    
    @StateObject private var syncManager = SyncManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(syncManager)
                .onOpenURL { url in
                    handleURL(url)
                }
                .task {
                    await syncManager.initializeSync()
                }
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 800, height: 600)
        #endif
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("Add Account") {
                    NotificationCenter.default.post(name: .addAccount, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
    
    private func handleURL(_ url: URL) {
        guard url.scheme == "totp" else { return }
        
        if url.host == "copy" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let code = components?.queryItems?.first(where: { $0.name == "code" })?.value ?? ""
                        
            // Copy to clipboard
            #if canImport(UIKit)
            UIPasteboard.general.string = code
            #elseif canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
            #endif
            
            // Refresh widget timeline so it shows updated code when user returns
            WidgetCenter.shared.reloadTimelines(ofKind: "TOTP_Widget")
            
            // Show notification or feedback
            print("Copied TOTP code to clipboard: \(code)")
        }
    }
}

// MARK: - App Delegate for Remote Notifications

#if os(iOS)
@available(iOS 26.0, *)
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Register for remote notifications (CloudKit silent push)
        application.registerForRemoteNotifications()
        return true
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("CloudKit: Registered for remote notifications with token")
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("CloudKit: Failed to register for remote notifications: \(error)")
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task {
            let handled = await SyncManager.shared.handleRemoteNotification(userInfo: userInfo)
            completionHandler(handled ? .newData : .noData)
        }
    }
}
#endif

extension Notification.Name {
    static let addAccount = Notification.Name("addAccount")
}

struct TOTPApp_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Empty state preview
            EmptyStatePreview()
                .previewDisplayName("Empty State")
                .preferredColorScheme(.light)
            
            EmptyStatePreview()
                .previewDisplayName("Empty State - Dark")
                .preferredColorScheme(.dark)
            
            // With TOTP data preview
            WithDataPreview()
                .previewDisplayName("With TOTP Data")
                .preferredColorScheme(.light)
            
            WithDataPreview()
                .previewDisplayName("With TOTP Data - Dark")
                .preferredColorScheme(.dark)
            
            // Loading state preview
            LoadingStatePreview()
                .previewDisplayName("Loading State")
                .preferredColorScheme(.light)
            
            // iPad preview with data
            WithDataPreview()
                .previewDisplayName("iPad - TOTP Data")
                .previewDevice("iPad Pro (12.9-inch) (6th generation)")
                .preferredColorScheme(.light)
        }
    }
}

// Empty state preview
@available(iOS 26.0, macOS 26.0, *)
struct EmptyStatePreview: View {
    var body: some View {
        NavigationStack {
            ZStack {
                // GitHub-style gray background
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack {
                    GeometryReader { geometry in
                        ScrollView {
                            VStack(spacing: 20) {
                                Image(systemName: "lock.shield")
                                    .font(.system(size: 60))
                                    .foregroundColor(.secondary)
                                VStack(spacing: 8) {
                                    Text("No TOTP accounts")
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                    Text("Add your first account to get started")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                        }
                        .refreshable {
                            // Mock refresh
                        }
                    }
                }
                
                // Floating Action Button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {}) {
                            Image(systemName: "plus")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .frame(width: 52, height: 52)
                        }
                        .buttonStyle(.plain)
                        .background {
                            Circle()
                                .fill(.background)
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.8),
                                            .white.opacity(0.2)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.5
                                )
                        }
                        .glassEffect(.regular.interactive())
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
                        .padding(.trailing, 24)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("TOTP Passwords")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// With data preview
@available(iOS 26.0, macOS 26.0, *)
struct WithDataPreview: View {
    private let sampleAccounts = [
        ("Google", "john.doe@gmail.com", "123456"),
        ("GitHub", "GitHub", "789012"),
        ("Amazon", "AWS Console", "345678"),
        ("Microsoft", "work@company.com", "901234"),
        ("Discord", "Discord", "567890")
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                // GitHub-style gray background
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack {
                    GeometryReader { geometry in
                        ScrollView {
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: geometry.size.width > 768 ? 3 : 1),
                                alignment: .center,
                                spacing: 12
                            ) {
                                ForEach(Array(sampleAccounts.enumerated()), id: \.offset) { index, account in
                                    MockTOTPCard(
                                        issuer: account.0,
                                        name: account.1,
                                        code: account.2
                                    )
                                }
                            }
                            .padding(.top)
                            .padding(.horizontal, geometry.size.width > 768 ? 40 : 20)
                            
                            Spacer()
                                .frame(height: 20)
                        }
                        .refreshable {
                            // Mock refresh
                        }
                    }
                }
                
                // Floating Action Button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {}) {
                            Image(systemName: "plus")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .frame(width: 52, height: 52)
                        }
                        .buttonStyle(.plain)
                        .background {
                            Circle()
                                .fill(.background)
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.8),
                                            .white.opacity(0.2)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.5
                                )
                        }
                        .glassEffect(.regular.interactive())
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
                        .padding(.trailing, 24)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("TOTP Passwords")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// Loading state preview
@available(iOS 26.0, macOS 26.0, *)
struct LoadingStatePreview: View {
    var body: some View {
        NavigationStack {
            ZStack {
                // GitHub-style gray background
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack {
                    GeometryReader { geometry in
                        ScrollView {
                            VStack {
                                Spacer()
                                    .frame(height: 100)
                                
                                VStack {
                                    ProgressView()
                                        .scaleEffect(1.2)
                                    Text("Loading accounts...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.top, 8)
                                }
                                .frame(maxWidth: .infinity)
                                
                                Spacer()
                            }
                        }
                        .refreshable {
                            // Mock refresh
                        }
                    }
                }
                
                // Floating Action Button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {}) {
                            Image(systemName: "plus")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .frame(width: 52, height: 52)
                        }
                        .buttonStyle(.plain)
                        .background {
                            Circle()
                                .fill(.background)
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.8),
                                            .white.opacity(0.2)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.5
                                )
                        }
                        .glassEffect(.regular.interactive())
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
                        .padding(.trailing, 24)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("TOTP Passwords")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// Mock TOTP card component
@available(iOS 26.0, macOS 26.0, *)
struct MockTOTPCard: View {
    let issuer: String
    let name: String
    let code: String
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(issuer)
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text(name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Circle()
                    .fill(Color.blue)
                    .frame(width: 12, height: 12)
            }
            
            HStack {
                Text(code)
                    .font(.title)
                    .fontWeight(.bold)
                    .tracking(2)
                Spacer()
                ProgressView(value: 0.7)
                    .progressViewStyle(CircularProgressViewStyle())
                    .frame(width: 24, height: 24)
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
        }
        .glassEffect(.regular.interactive())
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
