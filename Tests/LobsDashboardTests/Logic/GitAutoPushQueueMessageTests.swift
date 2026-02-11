import XCTest
@testable import LobsDashboard

final class GitAutoPushQueueMessageTests: XCTestCase {

    func testEmptyMessages() {
        let message = GitAutoPushQueue.bundleCommitMessage(from: [])
        XCTAssertEqual(message, "Lobs: bundled updates")
    }

    func testSingleMessage() {
        let message = GitAutoPushQueue.bundleCommitMessage(from: ["Update task status"])
        XCTAssertEqual(message, "Update task status")
    }

    func testTwoMessages() {
        let messages = ["Update task A", "Update task B"]
        let message = GitAutoPushQueue.bundleCommitMessage(from: messages)
        XCTAssertTrue(message.contains("Update task A"))
        XCTAssertTrue(message.contains("Update task B"))
        XCTAssertTrue(message.contains("2 changes"))
    }

    func testThreeMessages() {
        let messages = ["Change 1", "Change 2", "Change 3"]
        let message = GitAutoPushQueue.bundleCommitMessage(from: messages)
        XCTAssertTrue(message.contains("Change 1"))
        XCTAssertTrue(message.contains("Change 2"))
        XCTAssertTrue(message.contains("Change 3"))
        XCTAssertTrue(message.contains("3 changes"))
        XCTAssertFalse(message.contains("+")) // No overflow
    }

    func testFourMessages_ShowsOverflow() {
        let messages = ["Change 1", "Change 2", "Change 3", "Change 4"]
        let message = GitAutoPushQueue.bundleCommitMessage(from: messages)
        XCTAssertTrue(message.contains("Change 1"))
        XCTAssertTrue(message.contains("Change 2"))
        XCTAssertTrue(message.contains("Change 3"))
        XCTAssertFalse(message.contains("Change 4")) // Not in summary
        XCTAssertTrue(message.contains("+1 more")) // Overflow indicator
        XCTAssertTrue(message.contains("4 changes"))
    }

    func testManyMessages_ShowsOverflow() {
        let messages = (1...10).map { "Change \($0)" }
        let message = GitAutoPushQueue.bundleCommitMessage(from: messages)
        XCTAssertTrue(message.contains("+7 more")) // 10 - 3 = 7
        XCTAssertTrue(message.contains("10 changes"))
    }

    func testTrimsWhitespace() {
        let messages = ["  Update A  ", "  Update B  ", "  Update C  "]
        let message = GitAutoPushQueue.bundleCommitMessage(from: messages)
        XCTAssertTrue(message.contains("Update A"))
        XCTAssertTrue(message.contains("Update B"))
        XCTAssertTrue(message.contains("Update C"))
    }
}
