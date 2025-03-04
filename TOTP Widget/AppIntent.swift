//
//  AppIntent.swift
//  TOTP Widget
//
//  Created by Lucas Fernández Aragón on 4/3/25.
//

import WidgetKit
import AppIntents

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
