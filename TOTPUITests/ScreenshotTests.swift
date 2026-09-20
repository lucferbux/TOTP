//
//  ScreenshotTests.swift
//  TOTPUITests
//
//  Produces the App Store screenshots. Run with the `screenshots` lane or:
//    xcodebuild test -scheme TOTP -only-testing:TOTPUITests/ScreenshotTests \
//      -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max'
//  then `scripts/export-screenshots.sh <result bundle>` to write the PNGs out.
//
//  The app runs with `-ScreenshotMode`, which seeds fictional demo accounts — never real ones.
//

import XCTest

final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ScreenshotMode"]
        app.launch()
    }

    /// Screenshots are only useful if they survive a passing run, so keep them explicitly.
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func account(_ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "account-\(title)").firstMatch
    }

    func testCaptureScreenshots() throws {
        XCTAssertTrue(account("Northwind Corp").waitForExistence(timeout: 10))
        capture("01-codes")

        // A copy in progress: the confirmation and the green copied marker
        account("Contoso Cloud").tap()
        capture("02-copied")

        // Select mode with a couple of accounts ticked
        if app.buttons["selectButton"].exists {
            app.buttons["selectButton"].tap()
            account("Fabrikam Mail").tap()
            account("Acme Bank").tap()
            capture("03-select")
            app.buttons["doneSelectingButton"].tap()
        }

        // Adding an account
        app.buttons["addAccountButton"].tap()
        XCTAssertTrue(app.textFields["issuerField"].waitForExistence(timeout: 5))
        capture("04-add")
        app.buttons["cancelButton"].tap()

        // Settings, showing iCloud status and the security options
        if app.buttons["settingsButton"].exists {
            app.buttons["settingsButton"].tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "appLockToggle").firstMatch.waitForExistence(timeout: 5))
            capture("05-settings")
            app.buttons["Done"].tap()
        }
    }
}
