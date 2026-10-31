//
//  TipJarUITests.swift
//  TOTPUITests
//
//  Settings ▸ Buy Me a Coffee. Also keeps the screenshot App Review needs for each in-app purchase
//  (fastlane/screenshots_review/tips.png). `-ScreenshotTips` shows sample rows, since a UI test run
//  has no StoreKit configuration.
//

import XCTest

final class TipJarUITests: XCTestCase {
    #if os(iOS)
    func testSettingsOpensSuggestionAndCoffee() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "-ScreenshotTips", "YES"]
        app.launch()

        app.buttons["settingsButton"].tap()
        let coffee = app.descendants(matching: .any).matching(identifier: "tipJarLink").firstMatch
        // Settings is a lazy Form: rows below the fold don't exist until they're scrolled to.
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "appLockToggle").firstMatch.waitForExistence(timeout: 5))
        for _ in 0..<6 where !(coffee.exists && coffee.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "suggestionLink").firstMatch.exists)

        coffee.tap()
        XCTAssertTrue(app.staticTexts["A Week of Coffee"].waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "review-tips"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    #endif
}
