//
//  AppLockManager.swift
//  TOTP
//
//  Optional biometric / passcode lock for the app UI (iOS, iPadOS, macOS menu bar and window).
//

import Foundation
import Combine
import LocalAuthentication
import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class AppLockManager: ObservableObject {
    static let shared = AppLockManager()

    /// User preference, stored in the App Group.
    @Published private(set) var isEnabled: Bool
    /// Whether codes are currently hidden behind authentication.
    @Published private(set) var isLocked: Bool
    @Published var errorMessage: String?

    private var isAuthenticating = false
    private var observers: [NSObjectProtocol] = []

    private init() {
        let enabled = AppPreferences.appLockEnabled && !AppEnvironment.isUITesting
        isEnabled = enabled
        isLocked = enabled
        #if os(macOS)
        // Re-lock when the Mac locks or sleeps; the menu bar app otherwise stays alive for days.
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.lock() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.lock() }
        })
        #endif
    }

    // MARK: - Capabilities

    enum Biometry {
        case faceID, touchID, opticID, none
    }

    var biometry: Biometry {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .none
        }
    }

    var canAuthenticate: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    var methodName: String {
        switch biometry {
        case .faceID: String(localized: "Face ID")
        case .touchID: String(localized: "Touch ID")
        case .opticID: String(localized: "Optic ID")
        case .none: String(localized: "Passcode")
        }
    }

    var methodSymbol: String {
        switch biometry {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        case .none: "lock.fill"
        }
    }

    // MARK: - Actions

    func lock() {
        guard isEnabled, !isLocked else { return }
        isLocked = true
        // Views observe this to dismiss sheets: the lock is drawn as an overlay, and a presented
        // sheet sits above it — including the Add/Edit sheet, which can show a revealed secret.
        NotificationCenter.default.post(name: .totpDidLock, object: nil)
    }

    /// Prompts for Face ID / Touch ID / Optic ID with passcode fallback.
    @discardableResult
    func unlock() async -> Bool {
        guard isLocked else { return true }
        guard await authenticate(reason: String(localized: "Unlock your authentication codes")) else { return false }
        isLocked = false
        return true
    }

    /// Turning the lock on or off always requires authenticating first.
    func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled else { return }
        let reason = enabled
            ? String(localized: "Turn on the app lock")
            : String(localized: "Turn off the app lock")
        guard await authenticate(reason: reason) else { return }
        isEnabled = enabled
        AppPreferences.appLockEnabled = enabled
        isLocked = false
    }

    private func authenticate(reason: String) async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            errorMessage = policyError?.localizedDescription ?? String(localized: "Authentication isn't available on this device.")
            return false
        }
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            errorMessage = nil
            return true
        } catch let error as LAError where error.code == .userCancel || error.code == .appCancel || error.code == .systemCancel {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

// MARK: - Views

/// Full-screen cover shown while the app is locked.
struct LockedView: View {
    @ObservedObject var lock: AppLockManager

    var body: some View {
        ContentUnavailableView {
            Label("TOTP Is Locked", systemImage: "lock.shield.fill")
        } description: {
            Text("Unlock to see your codes.")
            if let message = lock.errorMessage {
                Text(message).foregroundStyle(.red)
            }
        } actions: {
            Button {
                Task { await lock.unlock() }
            } label: {
                Label("Unlock with \(lock.methodName)", systemImage: lock.methodSymbol)
                    .padding(.horizontal, 8)
            }
            .prominentActionStyle()
            .controlSize(.large)
            .accessibilityIdentifier("unlockButton")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

/// Hides content in the app switcher and behind the lock.
struct AppLockModifier: ViewModifier {
    @ObservedObject var lock: AppLockManager
    @Environment(\.scenePhase) private var scenePhase

    /// Cover shown in the app switcher so codes aren't in the snapshot.
    @ViewBuilder
    private var privacyCover: some View {
        if lock.isEnabled && !lock.isLocked && scenePhase != .active {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
        }
    }

    func body(content: Content) -> some View {
        lockedContent(content)
            .overlay { privacyCover }
            .animation(.smooth(duration: 0.25), value: lock.isLocked)
            .onChange(of: scenePhase) { _, phase in
                #if os(iOS)
                if phase == .background { lock.lock() }
                #endif
                if phase == .active && lock.isLocked {
                    Task { await lock.unlock() }
                }
            }
            .task {
                if lock.isLocked { await lock.unlock() }
            }
    }

    // On iOS the lock is presented, not overlaid: an overlay sits *below* a presented sheet, so an
    // open Add/Edit sheet would stay visible (and readable) behind it.
    @ViewBuilder
    private func lockedContent(_ content: Content) -> some View {
        #if os(iOS)
        content
            .fullScreenCover(isPresented: Binding(get: { lock.isLocked }, set: { _ in })) {
                LockedView(lock: lock)
            }
        #else
        content
            .overlay {
                if lock.isLocked {
                    LockedView(lock: lock)
                        .transition(.opacity)
                }
            }
        #endif
    }
}

extension Notification.Name {
    /// Posted when the app locks, so presented sheets can be dismissed.
    static let totpDidLock = Notification.Name("com.lucferbux.TOTP.didLock")
}

extension View {
    func appLock(_ lock: AppLockManager) -> some View {
        modifier(AppLockModifier(lock: lock))
    }
}
