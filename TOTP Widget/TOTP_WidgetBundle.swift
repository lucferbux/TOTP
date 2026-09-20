//
//  TOTP_WidgetBundle.swift
//  TOTP Widget
//
//  Created by Lucas Fernández Aragón on 4/3/25.
//

import WidgetKit
import SwiftUI

@main
struct TOTP_WidgetBundle: WidgetBundle {
    var body: some Widget {
        TOTP_Widget()
        TOTP_MultiWidget()
        #if !os(visionOS)
        CopyCodeControl()
        #endif
    }
}
