import Foundation

enum TaskStatus: String, Codable, CaseIterable {
  case inbox
  case active
  case completed
  case rejected
}

enum TaskOwner: String, Codable, CaseIterable {
  case lobs
  case rafe
}

struct DashboardTask: Codable, Identifiable, Hashable {
  var id: String
  var title: String
  var status: TaskStatus
  var owner: TaskOwner
  var createdAt: Date
  var updatedAt: Date
  var artifactPath: String?
  var notes: String?
}

struct TasksFile: Codable {
  var schemaVersion: Int
  var generatedAt: Date
  var tasks: [DashboardTask]
}

struct RemindersFile: Codable {
  var schemaVersion: Int
  var generatedAt: Date
  var reminders: [Reminder]
}

struct Reminder: Codable, Identifiable, Hashable {
  var id: String
  var title: String
  var dueAt: Date
}
