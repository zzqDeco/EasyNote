//
//  EasyNoteUITests.swift
//  EasyNoteUITests
//
//  Created by 赵子谦 on 2025/3/1.
//

import XCTest

final class EasyNoteUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunches() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testPrimaryTabNavigationSmoke() throws {
        let app = XCUIApplication()
        app.launch()

        tapTab(in: app, identifier: "tab.explore", label: "探索")
        XCTAssertTrue(
            app.navigationBars["探索"].waitForExistence(timeout: 3)
                || app.otherElements["tab.explore.content"].waitForExistence(timeout: 1)
        )

        tapTab(in: app, identifier: "tab.todo", label: "待办")
        XCTAssertTrue(
            app.buttons["todo.addButton"].waitForExistence(timeout: 3)
                || app.buttons["todo.floatingAddButton"].waitForExistence(timeout: 1)
        )
        XCTAssertTrue(
            app.segmentedControls["todo.filterPicker"].waitForExistence(timeout: 3)
                || app.otherElements["todo.filterPicker"].waitForExistence(timeout: 1)
        )

        tapTab(in: app, identifier: "tab.diary", label: "日记")
        XCTAssertTrue(app.textFields["diary.searchField"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["diary.filterButton"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["diary.addButton"].waitForExistence(timeout: 3))

        tapTab(in: app, identifier: "tab.settings", label: "设置")
        XCTAssertTrue(app.secureTextFields["settings.apiKeyField"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }

    @MainActor
    private func tapTab(in app: XCUIApplication, identifier: String, label: String) {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))

        let identifiedButton = app.tabBars.buttons[identifier]
        if identifiedButton.waitForExistence(timeout: 1) {
            identifiedButton.tap()
            return
        }

        let labeledButton = app.tabBars.buttons[label]
        XCTAssertTrue(labeledButton.waitForExistence(timeout: 3), "Missing tab: \(label)")
        labeledButton.tap()
    }
}
