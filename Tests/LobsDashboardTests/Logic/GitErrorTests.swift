import XCTest
@testable import LobsDashboard

final class GitErrorTests: XCTestCase {

    // MARK: - Parse Tests

    func testParseNetworkUnreachable() {
        let stderr = "fatal: could not resolve host: github.com"
        let error = GitError.parse(stderr: stderr, exitCode: 128)
        if case .networkUnreachable = error {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected .networkUnreachable, got \(error)")
        }
    }

    func testParseAuthenticationFailed() {
        let stderr = "Permission denied (publickey)"
        let error = GitError.parse(stderr: stderr, exitCode: 128)
        if case .authenticationFailed = error {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected .authenticationFailed, got \(error)")
        }
    }

    func testParseRepositoryNotFound() {
        let stderr = "fatal: repository 'https://github.com/user/repo.git' not found"
        let error = GitError.parse(stderr: stderr, exitCode: 128)
        if case .repositoryNotFound = error {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected .repositoryNotFound, got \(error)")
        }
    }

    func testParsePermissionDenied() {
        let stderr = "fatal: unable to access 'https://...': The requested URL returned error: 403"
        let error = GitError.parse(stderr: stderr, exitCode: 128)
        if case .permissionDenied = error {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected .permissionDenied, got \(error)")
        }
    }

    func testParseMergeConflict() {
        let stderr = "CONFLICT (content): Merge conflict in file.txt"
        let error = GitError.parse(stderr: stderr, exitCode: 1)
        if case .mergeConflict = error {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected .mergeConflict, got \(error)")
        }
    }

    func testParseInvalidRepository() {
        let stderr = "fatal: not a git repository (or any of the parent directories): .git"
        let error = GitError.parse(stderr: stderr, exitCode: 128)
        if case .invalidRepository = error {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected .invalidRepository, got \(error)")
        }
    }

    func testParseUncommittedChanges() {
        let stderr = "error: Your local changes to the following files would be overwritten by merge"
        let error = GitError.parse(stderr: stderr, exitCode: 1)
        if case .uncommittedChanges = error {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected .uncommittedChanges, got \(error)")
        }
    }

    func testParseRemoteRejected() {
        let stderr = "! [rejected] main -> main (fetch first)"
        let error = GitError.parse(stderr: stderr, exitCode: 1)
        if case .remoteRejected = error {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected .remoteRejected, got \(error)")
        }
    }

    func testParseUnknownError() {
        let stderr = "Some unknown error message"
        let error = GitError.parse(stderr: stderr, exitCode: 1)
        if case .unknownError(let msg) = error {
            XCTAssertEqual(msg, "Some unknown error message")
        } else {
            XCTFail("Expected .unknownError, got \(error)")
        }
    }

    // MARK: - isRetryable Tests

    func testNetworkUnreachableIsRetryable() {
        let error = GitError.networkUnreachable
        XCTAssertTrue(error.isRetryable)
    }

    func testRemoteRejectedIsRetryable() {
        let error = GitError.remoteRejected
        XCTAssertTrue(error.isRetryable)
    }

    func testAuthenticationFailedIsNotRetryable() {
        let error = GitError.authenticationFailed
        XCTAssertFalse(error.isRetryable)
    }

    // MARK: - suggestsPull Tests

    func testRemoteRejectedSuggestsPull() {
        let error = GitError.remoteRejected
        XCTAssertTrue(error.suggestsPull)
    }

    func testMergeConflictSuggestsPull() {
        let error = GitError.mergeConflict
        XCTAssertTrue(error.suggestsPull)
    }

    func testNetworkUnreachableDoesNotSuggestPull() {
        let error = GitError.networkUnreachable
        XCTAssertFalse(error.suggestsPull)
    }

    // MARK: - errorDescription Tests

    func testErrorDescriptions() {
        XCTAssertNotNil(GitError.networkUnreachable.errorDescription)
        XCTAssertNotNil(GitError.authenticationFailed.errorDescription)
        XCTAssertNotNil(GitError.mergeConflict.errorDescription)
    }

    // MARK: - GitOperationResult Tests

    func testSuccessResult() {
        let result = GitOperationResult.success(output: "All good")
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.output, "All good")
        XCTAssertNil(result.error)
        XCTAssertFalse(result.canRetry)
        XCTAssertFalse(result.suggestsPull)
    }

    func testFailureResult() {
        let error = GitError.networkUnreachable
        let result = GitOperationResult.failure(error: error, output: "Failed")
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.output, "Failed")
        XCTAssertNotNil(result.error)
        XCTAssertTrue(result.canRetry) // networkUnreachable is retryable
        XCTAssertFalse(result.suggestsPull)
    }
}
