//
//  LiveCodes.swift
//  TOTP
//
//  Stops live codes from redrawing while nobody can see them. A Mac keeps the app running for
//  days in the menu bar, so a once-a-second redraw in a hidden window adds up to real CPU.
//

import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

extension View {
    /// Pauses every live code below this view while the app lock is up or — on macOS — while the
    /// window is closed, minimised, on another Space or fully covered. iOS suspends hidden scenes
    /// by itself.
    func pausesLiveCodesWhenHidden() -> some View {
        modifier(LiveCodesModifier())
    }
}

private struct LiveCodesModifier: ViewModifier {
    @ObservedObject private var lock = AppLockManager.shared
    @State private var isWindowVisible = true

    func body(content: Content) -> some View {
        content
            .environment(\.liveCodesEnabled, isWindowVisible && !lock.isLocked)
            #if os(macOS)
            .background { WindowVisibilityReader(isVisible: $isWindowVisible) }
            #endif
    }
}

#if os(macOS)
/// Reports whether the hosting window is on screen: ordered in, not minimised, on the active
/// Space and not completely covered by other windows.
struct WindowVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.onChange = { [$isVisible] visible in
            if $isVisible.wrappedValue != visible { $isVisible.wrappedValue = visible }
        }
    }

    final class ReaderView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observation: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observation { NotificationCenter.default.removeObserver(observation) }
            observation = nil
            if let window {
                observation = NotificationCenter.default.addObserver(
                    forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.report() }
                }
            }
            // Attached counts as visible, deliberately: SwiftUI attaches content around the moment
            // it orders the window in, before AppKit has computed its occlusion — which then reads
            // "not visible" — and AppKit posts no change for that first appearance. Every later
            // change (closing, minimising, covering, switching Space) does post one. This runs
            // during a SwiftUI update, so report on the next turn of the run loop.
            let isAttached = window != nil
            DispatchQueue.main.async { [weak self] in self?.onChange?(isAttached) }
        }

        private func report() {
            onChange?(window?.occlusionState.contains(.visible) ?? false)
        }
    }
}
#endif
