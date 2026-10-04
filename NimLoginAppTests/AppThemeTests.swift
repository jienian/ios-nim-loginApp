import XCTest
@testable import NimLoginApp

final class AppThemeTests: XCTestCase {
    func testColorSchemeMapping() {
        XCTAssertNil(AppTheme.system.colorScheme)
        XCTAssertEqual(AppTheme.light.colorScheme, .light)
        XCTAssertEqual(AppTheme.dark.colorScheme, .dark)
    }

    func testRawValueRoundTrip() {
        for theme in AppTheme.allCases {
            XCTAssertEqual(AppTheme(rawValue: theme.rawValue), theme)
        }
        XCTAssertNil(AppTheme(rawValue: "unknown"))
    }
}
