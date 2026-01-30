import Foundation

final class LobsControlStore {
  let repoRoot: URL

  init(repoRoot: URL) {
    self.repoRoot = repoRoot
  }

  private var tasksURL: URL { repoRoot.appendingPathComponent("state/tasks.json") }

  func loadTasks() throws -> TasksFile {
    let data = try Data(contentsOf: tasksURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(TasksFile.self, from: data)
  }

  func saveTasks(_ file: TasksFile) throws {
    var file = file
    file.generatedAt = Date()

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(file)

    try FileManager.default.createDirectory(
      at: tasksURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    try data.write(to: tasksURL, options: [.atomic])
  }

  func readArtifact(relativePath: String) throws -> String {
    let url = repoRoot.appendingPathComponent(relativePath)
    return try String(contentsOf: url, encoding: .utf8)
  }

  func setStatus(taskId: String, status: TaskStatus) throws {
    var file = try loadTasks()
    guard let idx = file.tasks.firstIndex(where: { $0.id == taskId }) else { return }
    file.tasks[idx].status = status
    file.tasks[idx].updatedAt = Date()
    try saveTasks(file)
  }
}
