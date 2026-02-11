import XCTest
@testable import LobsDashboard

final class StoreProjectsCRUDTests: TempDirectoryTestCase {

    func testLoadProjects_MissingFile_ReturnsDefaultProject() throws {
        let store = LobsControlStore(repoRoot: tempDir)
        let projectsFile = try store.loadProjects()

        XCTAssertEqual(projectsFile.projects.count, 1)
        XCTAssertEqual(projectsFile.projects[0].id, "default")
        XCTAssertEqual(projectsFile.projects[0].title, "Default")
    }

    func testSaveAndLoadProjects() throws {
        let store = LobsControlStore(repoRoot: tempDir)
        let project = TestFixtures.makeProject(id: "test", title: "Test Project")
        let projectsFile = ProjectsFile(
            schemaVersion: 1,
            generatedAt: Date(),
            projects: [project]
        )

        try store.saveProjects(projectsFile)

        let loaded = try store.loadProjects()
        XCTAssertEqual(loaded.projects.count, 1)
        XCTAssertEqual(loaded.projects[0].id, "test")
        XCTAssertEqual(loaded.projects[0].title, "Test Project")
    }

    func testRenameProject() throws {
        let store = LobsControlStore(repoRoot: tempDir)
        let project = TestFixtures.makeProject(id: "test", title: "Old Title")
        let projectsFile = ProjectsFile(
            schemaVersion: 1,
            generatedAt: Date(),
            projects: [project]
        )
        try store.saveProjects(projectsFile)

        try store.renameProject(id: "test", newTitle: "New Title")

        let loaded = try store.loadProjects()
        XCTAssertEqual(loaded.projects[0].title, "New Title")
    }

    func testRenameProject_TrimsWhitespace() throws {
        let store = LobsControlStore(repoRoot: tempDir)
        let project = TestFixtures.makeProject(id: "test", title: "Old")
        let projectsFile = ProjectsFile(
            schemaVersion: 1,
            generatedAt: Date(),
            projects: [project]
        )
        try store.saveProjects(projectsFile)

        try store.renameProject(id: "test", newTitle: "  New Title  ")

        let loaded = try store.loadProjects()
        XCTAssertEqual(loaded.projects[0].title, "New Title")
    }

    func testDeleteProject() throws {
        let store = LobsControlStore(repoRoot: tempDir)
        let projects = [
            TestFixtures.makeProject(id: "keep", title: "Keep"),
            TestFixtures.makeProject(id: "delete", title: "Delete")
        ]
        let projectsFile = ProjectsFile(
            schemaVersion: 1,
            generatedAt: Date(),
            projects: projects
        )
        try store.saveProjects(projectsFile)

        try store.deleteProject(id: "delete")

        let loaded = try store.loadProjects()
        XCTAssertEqual(loaded.projects.count, 1)
        XCTAssertEqual(loaded.projects[0].id, "keep")
    }

    func testArchiveProject() throws {
        let store = LobsControlStore(repoRoot: tempDir)
        let project = TestFixtures.makeProject(id: "test", title: "Test", archived: false)
        let projectsFile = ProjectsFile(
            schemaVersion: 1,
            generatedAt: Date(),
            projects: [project]
        )
        try store.saveProjects(projectsFile)

        try store.archiveProject(id: "test")

        let loaded = try store.loadProjects()
        XCTAssertEqual(loaded.projects[0].archived, true)
    }

    func testArchiveProject_AlreadyArchived_NoChange() throws {
        let store = LobsControlStore(repoRoot: tempDir)
        let project = TestFixtures.makeProject(id: "test", title: "Test", archived: true)
        let projectsFile = ProjectsFile(
            schemaVersion: 1,
            generatedAt: Date(),
            projects: [project]
        )
        try store.saveProjects(projectsFile)

        let beforeUpdate = try store.loadProjects().projects[0].updatedAt

        try store.archiveProject(id: "test")

        let afterUpdate = try store.loadProjects().projects[0].updatedAt
        // updatedAt should not change since it was already archived
        XCTAssertEqual(beforeUpdate.timeIntervalSince1970, afterUpdate.timeIntervalSince1970, accuracy: 0.1)
    }

    func testUpdateProjectNotes() throws {
        let store = LobsControlStore(repoRoot: tempDir)
        let project = TestFixtures.makeProject(id: "test", title: "Test")
        let projectsFile = ProjectsFile(
            schemaVersion: 1,
            generatedAt: Date(),
            projects: [project]
        )
        try store.saveProjects(projectsFile)

        try store.updateProjectNotes(id: "test", notes: "New notes")

        let loaded = try store.loadProjects()
        XCTAssertEqual(loaded.projects[0].notes, "New notes")
    }
}
