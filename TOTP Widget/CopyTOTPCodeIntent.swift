//
//  CopyTOTPCodeIntent.swift
//  TOTP Widget
//
//  Created by Lucas Fernández Aragón on 4/3/25.
//

import AppIntents
import WidgetKit

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

/// App Intent for copying TOTP codes to clipboard from the widget
/// This intent runs in the main app's process to access the clipboard
@available(iOS 26.0, macOS 26.0, *)
struct CopyTOTPCodeIntent: AppIntent {
    static var title: LocalizedStringResource = "Copy TOTP Code"
    static var description = IntentDescription("Copies the TOTP code to clipboard")
    
    // Run in the app's process to access clipboard (widgets are sandboxed)
    static var openAppWhenRun: Bool = true
    
    @Parameter(title: "Code")
    var code: String
    
    init() {
        self.code = ""
    }
    
    init(code: String) {
        self.code = code
    }
    
    func perform() async throws -> some IntentResult {
        // Copy to clipboard
        #if canImport(UIKit)
        await MainActor.run {
            UIPasteboard.general.string = code
        }
        #elseif canImport(AppKit)
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
        }
        #endif
        
        return .result()
    }
}
