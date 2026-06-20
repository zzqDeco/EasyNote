//
//  EasyNoteUITests.swift
//  EasyNoteUITests
//
//  Created by 赵子谦 on 2025/3/1.
//

import XCTest

final class EasyNoteUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-easynote-ui-testing",
            "-easynote-disable-animations"
        ]
        app.launchEnvironment["EASYNOTE_UI_TESTING"] = "1"
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    @MainActor
    func testLaunches() throws {
        app.launch()

        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testPrimaryTabNavigationSmoke() throws {
        app.launch()

        tapTab(in: app, identifier: "tab.explore", label: "探索")
        XCTAssertTrue(waitForAny([
            app.navigationBars["探索"],
            app.otherElements["tab.explore.content"]
        ]))

        tapTab(in: app, identifier: "tab.todo", label: "待办")
        XCTAssertTrue(waitForAny([
            app.buttons["todo.addButton"],
            app.buttons["todo.floatingAddButton"]
        ]))
        XCTAssertTrue(waitForAny([
            app.segmentedControls["todo.filterPicker"],
            app.otherElements["todo.filterPicker"]
        ]))

        tapTab(in: app, identifier: "tab.diary", label: "日记")
        XCTAssertTrue(
            app.textFields["diary.searchField"].waitForExistence(timeout: 5),
            "Missing diary search field"
        )
        XCTAssertTrue(
            app.buttons["diary.filterButton"].waitForExistence(timeout: 5),
            "Missing diary filter button"
        )
        XCTAssertTrue(
            app.buttons["diary.addButton"].waitForExistence(timeout: 5),
            "Missing diary add button"
        )

        tapTab(in: app, identifier: "tab.settings", label: "设置")
        XCTAssertTrue(waitForAny([
            app.secureTextFields["settings.apiKeyField"],
            app.textFields["settings.apiKeyField"]
        ]))
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

    @MainActor
    private func waitForAny(_ elements: [XCUIElement], timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if elements.contains(where: { $0.exists }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return elements.contains(where: { $0.exists })
    }
}
