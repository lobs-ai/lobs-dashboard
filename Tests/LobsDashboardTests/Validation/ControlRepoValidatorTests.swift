import XCTest
@testable import LobsDashboard

final class ControlRepoValidatorTests: TempDirectoryTestCase {

    func testValidateEmptyDirectory() {
        let validator = ControlRepoValidator()
        let result = validator.validate(repoPath: tempDir.path)

        XCTAssertFalse(result.isValid)
        XCTAssertFalse(result.issues.isEmpty)
        XCTAssertTrue(result.issues.contains(.missingDirectory("state")))
    }

    func testValidateCompleteRepo() throws {
        // Create valid structure
        let stateDir = tempDir.appendingPathComponent("state")
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)

        let tasksDir = stateDir.appendingPathComponent("tasks")
        try FileManager.default.createDirectory(at: tasksDir, withIntermediateDirectories: true)

        let projectsJSON = """
        {
          "schemaVersion": 1,
          "generatedAt": "2024-01-01T00:00:00Z",
          "projects": []
        }
        """
        try projectsJSON.write(
            to: stateDir.appendingPathComponent("projects.json"),
            atomically: true,
            encoding: .utf8
        )

        let workerStatusJSON = """
        {
          "active": false
        }
        """
        try workerStatusJSON.write(
            to: stateDir.appendingPathComponent("worker-status.json"),
            atomically: true,
            encoding: .utf8
        )

        let validator = ControlRepoValidator()
        let result = validator.validate(repoPath: tempDir.path)

        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testValidateInvalidJSON() throws {
        // Create structure with invalid JSON
        let stateDir = tempDir.appendingPathComponent("state")
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)

        let invalidJSON = "{ invalid json"
        try invalidJSON.write(
            to: stateDir.appendingPathComponent("projects.json"),
            atomically: true,
            encoding: .utf8
        )

        let validator = ControlRepoValidator()
        let result = validator.validate(repoPath: tempDir.path)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.contains { issue in
            if case .invalidJson("state/projects.json", _) = issue {
                return true
            }
            return false
        })
    }

    func testInitializeCreatesStructure() {
        let validator = ControlRepoValidator()
        let result = validator.initialize(repoPath: tempDir.path)

        XCTAssertTrue(result.isValid)
        XCTAssertFalse(result.created.isEmpty)
        XCTAssertTrue(result.created.contains("state"))
        XCTAssertTrue(result.created.contains("state/tasks"))
        XCTAssertTrue(result.created.contains("state/projects.json"))
        XCTAssertTrue(result.created.contains("state/worker-status.json"))

        // Verify files exist
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: tempDir.appendingPathComponent("state").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: tempDir.appendingPathComponent("state/tasks").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: tempDir.appendingPathComponent("state/projects.json").path
        ))
    }

    func testInitializePreservesExisting() throws {
        // Create partial structure
        let stateDir = tempDir.appendingPathComponent("state")
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)

        let existingJSON = """
        {
          "schemaVersion": 1,
          "generatedAt": "2024-01-01T00:00:00Z",
          "projects": [{"id": "existing", "title": "Existing"}]
        }
        """
        try existingJSON.write(
            to: stateDir.appendingPathComponent("projects.json"),
            atomically: true,
            encoding: .utf8
        )

        let validator = ControlRepoValidator()
        let result = validator.initialize(repoPath: tempDir.path)

        // Should create missing files but not overwrite existing
        XCTAssertTrue(result.isValid)
        XCTAssertFalse(result.created.contains("state/projects.json"))
        XCTAssertTrue(result.created.contains("state/tasks"))

        // Verify existing file was preserved
        let content = try String(
            contentsOf: stateDir.appendingPathComponent("projects.json"),
            encoding: .utf8
        )
        XCTAssertTrue(content.contains("Existing"))
    }
}
