import Foundation

final class LobsControlStore {
  let repoRoot: URL

  init(repoRoot: URL) {
    self.repoRoot = repoRoot
  }

  private var tasksURL: URL { repoRoot.appendingPathComponent("state/tasks.json") }
  private var tasksDirURL: URL { repoRoot.appendingPathComponent("state/tasks") }
  private var archiveDirURL: URL { repoRoot.appendingPathComponent("state/tasks-archive") }

  private func decoder() -> JSONDecoder {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
  }

  private func encoder() -> JSONEncoder {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    e.dateEncodingStrategy = .iso8601
    return e
  }

  private func taskFileURL(taskId: String) -> URL {
    tasksDirURL.appendingPathComponent("\(taskId).json")
  }

  func loadTasks() throws -> TasksFile {
    // Prefer per-task files if the directory exists.
    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      let items = try FileManager.default.contentsOfDirectory(
        at: tasksDirURL,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )

      let dec = decoder()
      var tasks: [DashboardTask] = []

      for url in items where url.pathExtension.lowercased() == "json" {
        let data = try Data(contentsOf: url)
        let t = try dec.decode(DashboardTask.self, from: data)
        tasks.append(t)
      }

      // Stable ordering (nice UX)
      tasks.sort { (a, b) in
        if a.status.rawValue != b.status.rawValue { return a.status.rawValue < b.status.rawValue }
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
        return a.createdAt > b.createdAt
      }

      return TasksFile(schemaVersion: 0, generatedAt: Date(), tasks: tasks)
    }

    // Fallback: legacy single file.
    let data = try Data(contentsOf: tasksURL)
    return try decoder().decode(TasksFile.self, from: data)
  }

  func saveTasks(_ file: TasksFile) throws {
    // If per-task directory exists, write each task to its own file.
    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      try FileManager.default.createDirectory(
        at: tasksDirURL,
        withIntermediateDirectories: true
      )

      let enc = encoder()
      for task in file.tasks {
        var t = task
        t.updatedAt = Date()
        let data = try enc.encode(t)
        try data.write(to: taskFileURL(taskId: t.id), options: [.atomic])
      }

      // Keep legacy tasks.json updated too (helps older tooling).
      var legacy = file
      legacy.generatedAt = Date()
      let legacyData = try enc.encode(legacy)
      try FileManager.default.createDirectory(
        at: tasksURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try legacyData.write(to: tasksURL, options: [.atomic])
      return
    }

    // Legacy mode
    var file = file
    file.generatedAt = Date()

    let data = try encoder().encode(file)

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
    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      let url = taskFileURL(taskId: taskId)
      let data = try Data(contentsOf: url)
      var task = try decoder().decode(DashboardTask.self, from: data)
      task.status = status
      task.updatedAt = Date()
      let out = try encoder().encode(task)
      try out.write(to: url, options: [.atomic])
      return
    }

    var file = try loadTasks()
    guard let idx = file.tasks.firstIndex(where: { $0.id == taskId }) else { return }
    file.tasks[idx].status = status
    file.tasks[idx].updatedAt = Date()
    try saveTasks(file)
  }

  func setWorkState(taskId: String, workState: WorkState?) throws {
    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      let url = taskFileURL(taskId: taskId)
      let data = try Data(contentsOf: url)
      var task = try decoder().decode(DashboardTask.self, from: data)
      task.workState = workState
      task.updatedAt = Date()
      let out = try encoder().encode(task)
      try out.write(to: url, options: [.atomic])
      return
    }

    var file = try loadTasks()
    guard let idx = file.tasks.firstIndex(where: { $0.id == taskId }) else { return }
    file.tasks[idx].workState = workState
    file.tasks[idx].updatedAt = Date()
    try saveTasks(file)
  }

  func setReviewState(taskId: String, reviewState: ReviewState?) throws {
    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      let url = taskFileURL(taskId: taskId)
      let data = try Data(contentsOf: url)
      var task = try decoder().decode(DashboardTask.self, from: data)
      task.reviewState = reviewState
      task.updatedAt = Date()
      let out = try encoder().encode(task)
      try out.write(to: url, options: [.atomic])
      return
    }

    var file = try loadTasks()
    guard let idx = file.tasks.firstIndex(where: { $0.id == taskId }) else { return }
    file.tasks[idx].reviewState = reviewState
    file.tasks[idx].updatedAt = Date()
    try saveTasks(file)
  }

  func setTitleAndNotes(taskId: String, title: String, notes: String?) throws {
    let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)

    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      let url = taskFileURL(taskId: taskId)
      let data = try Data(contentsOf: url)
      var task = try decoder().decode(DashboardTask.self, from: data)
      task.title = cleanTitle.isEmpty ? task.title : cleanTitle
      task.notes = (cleanNotes?.isEmpty == true) ? nil : cleanNotes
      task.updatedAt = Date()
      let out = try encoder().encode(task)
      try out.write(to: url, options: [.atomic])
      return
    }

    var file = try loadTasks()
    guard let idx = file.tasks.firstIndex(where: { $0.id == taskId }) else { return }
    if !cleanTitle.isEmpty { file.tasks[idx].title = cleanTitle }
    file.tasks[idx].notes = (cleanNotes?.isEmpty == true) ? nil : cleanNotes
    file.tasks[idx].updatedAt = Date()
    try saveTasks(file)
  }

  func addTask(
    id: String = UUID().uuidString,
    title: String,
    owner: TaskOwner,
    status: TaskStatus,
    workState: WorkState? = .notStarted,
    reviewState: ReviewState? = .pending,
    notes: String?
  ) throws -> DashboardTask {
    let now = Date()
    let task = DashboardTask(
      id: id,
      title: title,
      status: status,
      owner: owner,
      createdAt: now,
      updatedAt: now,
      workState: workState,
      reviewState: reviewState,
      artifactPath: nil,
      notes: notes?.isEmpty == true ? nil : notes
    )

    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      try FileManager.default.createDirectory(at: tasksDirURL, withIntermediateDirectories: true)
      let out = try encoder().encode(task)
      try out.write(to: taskFileURL(taskId: task.id), options: [.atomic])
      return task
    }

    var file = try loadTasks()
    file.tasks.append(task)
    try saveTasks(file)
    return task
  }

  func archiveTask(taskId: String) throws {
    // Per-file mode: move the task JSON into state/tasks-archive/
    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      let src = taskFileURL(taskId: taskId)
      if !FileManager.default.fileExists(atPath: src.path) { return }
      try FileManager.default.createDirectory(at: archiveDirURL, withIntermediateDirectories: true)
      let dst = archiveDirURL.appendingPathComponent("\(taskId).json")
      // Replace if exists
      _ = try? FileManager.default.removeItem(at: dst)
      try FileManager.default.moveItem(at: src, to: dst)
      return
    }

    // Legacy mode: remove from tasks.json
    var file = try loadTasks()
    file.tasks.removeAll { $0.id == taskId }
    try saveTasks(file)
  }

  func archiveCompleted(olderThanDays days: Int) throws {
    guard days > 0 else { return }
    if !FileManager.default.fileExists(atPath: tasksDirURL.path) { return }

    let items = try FileManager.default.contentsOfDirectory(
      at: tasksDirURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )

    let dec = decoder()
    let cutoff = Date().addingTimeInterval(TimeInterval(-days * 24 * 3600))

    for url in items where url.pathExtension.lowercased() == "json" {
      let data = try Data(contentsOf: url)
      let t = try dec.decode(DashboardTask.self, from: data)
      if t.status.rawValue == "completed" && t.updatedAt < cutoff {
        try archiveTask(taskId: t.id)
      }
    }
  }
}

