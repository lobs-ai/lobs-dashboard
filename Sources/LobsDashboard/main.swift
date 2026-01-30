import Foundation
import Network

// MARK: - Models

enum TaskStatus: String, Codable {
  case inbox
  case active
  case completed
  case rejected
}

struct Task: Codable, Identifiable {
  var id: String
  var title: String
  var status: TaskStatus
  var createdAt: Date
  var updatedAt: Date
  var artifactPath: String?
}

struct LogEntry: Codable {
  var ts: Date
  var kind: String
  var taskId: String?
  var message: String
}

// MARK: - Storage

final class Store {
  private let fm = FileManager.default
  private let baseDir: URL
  private let tasksURL: URL
  private let logURL: URL

  init() throws {
    let appSupport = try fm.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )

    self.baseDir = appSupport.appendingPathComponent("lobs-dashboard", isDirectory: true)
    self.tasksURL = baseDir.appendingPathComponent("tasks.json")
    self.logURL = baseDir.appendingPathComponent("log.jsonl")

    try fm.createDirectory(at: baseDir, withIntermediateDirectories: true)

    if !fm.fileExists(atPath: tasksURL.path) {
      try seed()
    }
  }

  private func seed() throws {
    let artifactsDir = baseDir.appendingPathComponent("artifacts", isDirectory: true)
    try fm.createDirectory(at: artifactsDir, withIntermediateDirectories: true)

    let artifactURL = artifactsDir.appendingPathComponent("seed-artifact.md")
    let artifact = """
    # Seed Artifact

    This is a fake artifact to prove the loop.

    - Click **Approve** or **Reject** in the UI.
    - The task status should update.
    - The log should record the decision.
    """
    try artifact.data(using: .utf8)!.write(to: artifactURL)

    let now = Date()
    let t = Task(
      id: UUID().uuidString,
      title: "Seed task: prove approve/reject loop",
      status: .inbox,
      createdAt: now,
      updatedAt: now,
      artifactPath: artifactURL.path
    )

    try saveTasks([t])
    try appendLog(.init(ts: now, kind: "seed", taskId: t.id, message: "Seeded initial task + artifact"))
  }

  func loadTasks() throws -> [Task] {
    let data = try Data(contentsOf: tasksURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode([Task].self, from: data)
  }

  func saveTasks(_ tasks: [Task]) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(tasks)
    try data.write(to: tasksURL, options: [.atomic])
  }

  func appendLog(_ entry: LogEntry) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(entry)
    let line = String(data: data, encoding: .utf8)! + "\n"

    if fm.fileExists(atPath: logURL.path) {
      let handle = try FileHandle(forWritingTo: logURL)
      try handle.seekToEnd()
      try handle.write(contentsOf: line.data(using: .utf8)!)
      try handle.close()
    } else {
      try line.data(using: .utf8)!.write(to: logURL)
    }
  }

  func readArtifact(taskId: String) throws -> String? {
    let tasks = try loadTasks()
    guard let t = tasks.first(where: { $0.id == taskId }), let p = t.artifactPath else { return nil }
    return try String(contentsOfFile: p, encoding: .utf8)
  }

  func updateTaskStatus(taskId: String, status: TaskStatus) throws {
    var tasks = try loadTasks()
    guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
    tasks[idx].status = status
    tasks[idx].updatedAt = Date()
    try saveTasks(tasks)
    try appendLog(.init(ts: Date(), kind: "status", taskId: taskId, message: "Set status=\(status.rawValue)"))
  }

  func info() -> [String: String] {
    [
      "baseDir": baseDir.path,
      "tasks": tasksURL.path,
      "log": logURL.path
    ]
  }
}

// MARK: - HTTP

struct HTTPResponse {
  var status: String
  var headers: [String: String]
  var body: Data
}

func http(_ statusCode: Int, _ reason: String) -> String {
  "HTTP/1.1 \(statusCode) \(reason)\r\n"
}

func respond(_ conn: NWConnection, _ res: HTTPResponse) {
  var headerLines = ""
  for (k, v) in res.headers {
    headerLines += "\(k): \(v)\r\n"
  }
  headerLines += "Content-Length: \(res.body.count)\r\n"
  headerLines += "Connection: close\r\n"

  let startLine = res.status
  let payload = startLine + headerLines + "\r\n"

  var data = Data(payload.utf8)
  data.append(res.body)

  conn.send(content: data, completion: .contentProcessed { _ in
    conn.cancel()
  })
}

func parseRequestLine(_ raw: String) -> (method: String, path: String)? {
  // e.g. "GET /api/tasks HTTP/1.1"
  let parts = raw.split(separator: " ")
  guard parts.count >= 2 else { return nil }
  return (String(parts[0]), String(parts[1]))
}

func splitLines(_ data: Data) -> [String] {
  String(decoding: data, as: UTF8.self).split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
}

// Very small request body parser for JSON POSTs; good enough for our endpoints.
func extractBody(_ data: Data) -> Data {
  // Find header/body boundary (CRLF CRLF)
  if let range = data.range(of: Data("\r\n\r\n".utf8)) {
    return data.suffix(from: range.upperBound)
  }
  return Data()
}

// MARK: - App

do {
  let store = try Store()

  let listener = try NWListener(using: .tcp, on: 8080)
  listener.newConnectionHandler = { conn in
    conn.start(queue: .global())

    conn.receive(minimumIncompleteLength: 1, maximumLength: 1_000_000) { data, _, _, _ in
      guard let data else {
        conn.cancel();
        return
      }

      let lines = splitLines(data)
      guard let first = lines.first, let req = parseRequestLine(first) else {
        respond(conn, .init(status: http(400, "Bad Request"), headers: ["Content-Type": "text/plain"], body: Data("bad request".utf8)))
        return
      }

      let method = req.method
      let path = req.path

      // Routing
      if method == "GET" && (path == "/" || path == "/index.html") {
        if let url = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Resources/public"),
           let body = try? Data(contentsOf: url) {
          respond(conn, .init(status: http(200, "OK"), headers: ["Content-Type": "text/html; charset=utf-8"], body: body))
          return
        }
        respond(conn, .init(status: http(500, "Internal Server Error"), headers: ["Content-Type": "text/plain"], body: Data("missing index.html".utf8)))
        return
      }

      if method == "GET" && path == "/api/info" {
        let json = try! JSONSerialization.data(withJSONObject: store.info(), options: [.prettyPrinted, .sortedKeys])
        respond(conn, .init(status: http(200, "OK"), headers: ["Content-Type": "application/json"], body: json))
        return
      }

      if method == "GET" && path == "/api/tasks" {
        do {
          let tasks = try store.loadTasks()
          let encoder = JSONEncoder()
          encoder.dateEncodingStrategy = .iso8601
          let body = try encoder.encode(tasks)
          respond(conn, .init(status: http(200, "OK"), headers: ["Content-Type": "application/json"], body: body))
        } catch {
          respond(conn, .init(status: http(500, "Internal Server Error"), headers: ["Content-Type": "text/plain"], body: Data("\(error)".utf8)))
        }
        return
      }

      if method == "GET" && path.hasPrefix("/api/tasks/") && path.hasSuffix("/artifact") {
        let parts = path.split(separator: "/")
        // /api/tasks/{id}/artifact
        if parts.count == 4 {
          let id = String(parts[2])
          do {
            if let md = try store.readArtifact(taskId: id) {
              respond(conn, .init(status: http(200, "OK"), headers: ["Content-Type": "text/markdown; charset=utf-8"], body: Data(md.utf8)))
            } else {
              respond(conn, .init(status: http(404, "Not Found"), headers: ["Content-Type": "text/plain"], body: Data("no artifact".utf8)))
            }
          } catch {
            respond(conn, .init(status: http(500, "Internal Server Error"), headers: ["Content-Type": "text/plain"], body: Data("\(error)".utf8)))
          }
          return
        }
      }

      if method == "POST" && path.hasPrefix("/api/tasks/") {
        let parts = path.split(separator: "/")
        // /api/tasks/{id}/approve | /reject
        if parts.count == 4 {
          let id = String(parts[2])
          let action = String(parts[3])
          do {
            if action == "approve" {
              try store.updateTaskStatus(taskId: id, status: .completed)
              respond(conn, .init(status: http(200, "OK"), headers: ["Content-Type": "application/json"], body: Data("{}".utf8)))
              return
            }
            if action == "reject" {
              try store.updateTaskStatus(taskId: id, status: .rejected)
              respond(conn, .init(status: http(200, "OK"), headers: ["Content-Type": "application/json"], body: Data("{}".utf8)))
              return
            }
          } catch {
            respond(conn, .init(status: http(500, "Internal Server Error"), headers: ["Content-Type": "text/plain"], body: Data("\(error)".utf8)))
            return
          }
        }
      }

      respond(conn, .init(status: http(404, "Not Found"), headers: ["Content-Type": "text/plain"], body: Data("not found".utf8)))
    }
  }

  listener.start(queue: .global())

  print("Lobs Dashboard server running at http://127.0.0.1:8080")
  print("Storage:")
  for (k, v) in store.info() {
    print("  \(k): \(v)")
  }

  dispatchMain()

} catch {
  fputs("Fatal: \(error)\n", stderr)
  exit(1)
}
