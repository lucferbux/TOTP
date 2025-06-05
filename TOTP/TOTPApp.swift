//
//  TOTPApp.swift
//  TOTP
//
//  Created by Lucas Fernández Aragón on 4/3/25.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

@main
struct TOTPApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    handleURL(url)
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
            
            // Show notification or feedback
            print("Copied TOTP code to clipboard: \(code)")
        }
    }
}

extension Notification.Name {
    static let addAccount = Notification.Name("addAccount")
}

struct TOTPApp_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
