import XCTest
@testable import LobsDashboard

final class StoreTasksCRUDTests: TempDirectoryTestCase {

    func testAddTask_CreatesTaskFile() throws {
        // Create state/tasks directory
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("state/tasks"),
            withIntermediateDirectories: true
        )

        let store = LobsControlStore(repoRoot: tempDir)
        let task = try store.addTask(
            id: "test-task",
            title: "Test Task",
            owner: .rafe,
            status: .active,
            notes: "Test notes"
        )

        XCTAssertEqual(task.id, "test-task")
        XCTAssertEqual(task.title, "Test Task")

        // Verify file was created
        let taskFile = tempDir.appendingPathComponent("state/tasks/test-task.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: taskFile.path))
    }

    func testLoadLocalTasks_FromPerTaskFiles() throws {
        // Create state/tasks directory with a task file
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("state/tasks"),
            withIntermediateDirectories: true
        )

        let task = TestFixtures.makeTask(id: "task1", title: "Task 1")
        try writeJSON(task, at: "state/tasks/task1.json")

        let store = LobsControlStore(repoRoot: tempDir)
        let tasks = try store.loadLocalTasks()

        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].id, "task1")
    }

    func testSetStatus() throws {
        // Setup
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("state/tasks"),
            withIntermediateDirectories: true
        )
        let store = LobsControlStore(repoRoot: tempDir)
        _ = try store.addTask(
            id: "test",
            title: "Test",
            owner: .rafe,
            status: .active,
            notes: nil
        )

        // Change status
        try store.setStatus(taskId: "test", status: .completed)

        // Verify
        let tasks = try store.loadLocalTasks()
        XCTAssertEqual(tasks[0].status, .completed)
    }

    func testSetWorkState() throws {
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("state/tasks"),
            withIntermediateDirectories: true
        )
        let store = LobsControlStore(repoRoot: tempDir)
        _ = try store.addTask(
            id: "test",
            title: "Test",
            owner: .rafe,
            status: .active,
            workState: .notStarted,
            notes: nil
        )

        try store.setWorkState(taskId: "test", workState: .inProgress)

        let tasks = try store.loadLocalTasks()
        XCTAssertEqual(tasks[0].workState, .inProgress)
    }

    func testDeleteTask() throws {
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("state/tasks"),
            withIntermediateDirectories: true
        )
        let store = LobsControlStore(repoRoot: tempDir)
        _ = try store.addTask(
            id: "test",
            title: "Test",
            owner: .rafe,
            status: .active,
            notes: nil
        )

        try store.deleteTask(taskId: "test")

        let tasks = try store.loadLocalTasks()
        XCTAssertEqual(tasks.count, 0)

        // Verify file was deleted
        let taskFile = tempDir.appendingPathComponent("state/tasks/test.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: taskFile.path))
    }

    func testArchiveTask() throws {
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("state/tasks"),
            withIntermediateDirectories: true
        )
        let store = LobsControlStore(repoRoot: tempDir)
        _ = try store.addTask(
            id: "test",
            title: "Test",
            owner: .rafe,
            status: .completed,
            notes: nil
        )

        try store.archiveTask(taskId: "test")

        // Should be moved to archive
        let taskFile = tempDir.appendingPathComponent("state/tasks/test.json")
        let archiveFile = tempDir.appendingPathComponent("state/tasks-archive/test.json")

        XCTAssertFalse(FileManager.default.fileExists(atPath: taskFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveFile.path))
    }

    func testSetTitleAndNotes() throws {
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("state/tasks"),
            withIntermediateDirectories: true
        )
        let store = LobsControlStore(repoRoot: tempDir)
        _ = try store.addTask(
            id: "test",
            title: "Old Title",
            owner: .rafe,
            status: .active,
            notes: "Old notes"
        )

        try store.setTitleAndNotes(taskId: "test", title: "New Title", notes: "New notes")

        let tasks = try store.loadLocalTasks()
        XCTAssertEqual(tasks[0].title, "New Title")
        XCTAssertEqual(tasks[0].notes, "New notes")
    }

    func testSaveExistingTask() throws {
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("state/tasks"),
            withIntermediateDirectories: true
        )
        let store = LobsControlStore(repoRoot: tempDir)
        var task = try store.addTask(
            id: "test",
            title: "Original",
            owner: .rafe,
            status: .active,
            notes: nil
        )

        task.title = "Modified"
        try store.saveExistingTask(task)

        let tasks = try store.loadLocalTasks()
        XCTAssertEqual(tasks[0].title, "Modified")
    }

    func testSetSortOrder() throws {
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("state/tasks"),
            withIntermediateDirectories: true
        )
        let store = LobsControlStore(repoRoot: tempDir)
        _ = try store.addTask(
            id: "test",
            title: "Test",
            owner: .rafe,
            status: .active,
            notes: nil
        )

        try store.setSortOrder(taskId: "test", sortOrder: 42)

        let tasks = try store.loadLocalTasks()
        XCTAssertEqual(tasks[0].sortOrder, 42)
    }

    func testSetReviewState() throws {
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("state/tasks"),
            withIntermediateDirectories: true
        )
        let store = LobsControlStore(repoRoot: tempDir)
        _ = try store.addTask(
            id: "test",
            title: "Test",
            owner: .rafe,
            status: .active,
            reviewState: .pending,
            notes: nil
        )

        try store.setReviewState(taskId: "test", reviewState: .approved)

        let tasks = try store.loadLocalTasks()
        XCTAssertEqual(tasks[0].reviewState, .approved)
    }
}
