//
//  TOTPApp.swift
//  TOTP
//
//  Created by Lucas Fernández Aragón on 4/3/25.
//

import SwiftUI

@main
struct TOTPApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
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
}

extension Notification.Name {
    static let addAccount = Notification.Name("addAccount")
}

struct TOTPApp_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
