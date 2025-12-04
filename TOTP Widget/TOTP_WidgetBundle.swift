//
//  TOTP_WidgetBundle.swift
//  TOTP Widget
//
//  Created by Lucas Fernández Aragón on 4/3/25.
//

import WidgetKit
import SwiftUI

@main
@available(iOS 26.0, macOS 26.0, *)
struct TOTP_WidgetBundle: WidgetBundle {
    var body: some Widget {
        TOTP_Widget()
    }
}
