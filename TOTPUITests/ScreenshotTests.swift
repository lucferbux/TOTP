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
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.appearance = .light
        launch()
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.appearance = .light
    }

    /// Launches in screenshot mode, optionally straight into a `-ScreenshotScene`. Scenes that
    /// would need a localized label to reach (the iPad overflow menu) open this way instead.
    private func launch(scene: String? = nil) {
        app = XCUIApplication()
        app.launchArguments = ["-ScreenshotMode"]
        if let scene {
            app.launchArguments += ["-ScreenshotScene", scene]
        }
        // scripts/export-screenshots.sh --locales passes these as TEST_RUNNER_SCREENSHOT_LANG / _LOCALE
        // (xcodebuild strips the prefix), so each run shoots the app in that language.
        let environment = ProcessInfo.processInfo.environment
        if let language = environment["SCREENSHOT_LANG"], !language.isEmpty {
            app.launchArguments += ["-AppleLanguages", "(\(language))"]
        }
        if let locale = environment["SCREENSHOT_LOCALE"], !locale.isEmpty {
            app.launchArguments += ["-AppleLocale", locale]
        }
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

    /// Waits for a new 30-second period, so the rings show plenty of time left instead of a red sliver.
    private func waitForFreshCodes() {
        let elapsed = Int(Date().timeIntervalSince1970) % 30
        if elapsed > 2 {
            Thread.sleep(forTimeInterval: TimeInterval(32 - elapsed))
        }
    }

    func testCaptureScreenshots() throws {
        XCTAssertTrue(account("Northwind Corp").waitForExistence(timeout: 10))
        waitForFreshCodes()
        capture("01-codes")

        // A copy in progress: the confirmation and the green copied marker
        account("Contoso Cloud").tap()
        capture("02-copied")

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
            app.buttons["settingsDoneButton"].tap()
        }

        // Select mode with the first accounts ticked
        app.terminate()
        launch(scene: "select")
        XCTAssertTrue(app.buttons["doneSelectingButton"].waitForExistence(timeout: 10))
        capture("03-select")

        // The list in Dark Mode (Apple recommends showing it)
        app.terminate()
        XCUIDevice.shared.appearance = .dark
        launch()
        XCTAssertTrue(account("Northwind Corp").waitForExistence(timeout: 10))
        waitForFreshCodes()
        capture("06-dark")
    }
}
