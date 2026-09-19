//
//  TOTPUITestsLaunchTests.swift
//  TOTPUITests
//
//  Created by Lucas Fernández Aragón on 4/3/25.
//

import XCTest

final class TOTPUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode"]
        app.launch()

        XCTAssertTrue(app.buttons["account-Example Corp"].firstMatch.waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
