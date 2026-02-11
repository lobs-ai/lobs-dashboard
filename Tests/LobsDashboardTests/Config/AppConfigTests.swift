import XCTest
@testable import LobsDashboard

final class AppConfigTests: XCTestCase {

    func testDefaultInit() {
        let config = AppConfig()
        XCTAssertEqual(config.controlRepoUrl, "")
        XCTAssertEqual(config.controlRepoPath, "")
        XCTAssertFalse(config.onboardingComplete)
        XCTAssertEqual(config.settings.ownerFilter, "all")
    }

    func testRoundTrip() throws {
        let settings = UserSettings(ownerFilter: "lobs", wipLimitActive: 10)
        let original = AppConfig(
            controlRepoUrl: "git@github.com:user/repo.git",
            controlRepoPath: "/Users/test/repo",
            onboardingComplete: true,
            settings: settings
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AppConfig.self, from: data)

        XCTAssertEqual(decoded.controlRepoUrl, original.controlRepoUrl)
        XCTAssertEqual(decoded.controlRepoPath, original.controlRepoPath)
        XCTAssertEqual(decoded.onboardingComplete, original.onboardingComplete)
        XCTAssertEqual(decoded.settings.ownerFilter, original.settings.ownerFilter)
    }
}
