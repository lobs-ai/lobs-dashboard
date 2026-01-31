import Foundation

struct AnyTaskColumn {
  let title: String
  let dropStatus: TaskStatus
  let matches: (DashboardTask) -> Bool

  init(title: String, dropStatus: TaskStatus, matches: @escaping (DashboardTask) -> Bool) {
    self.title = title
    self.dropStatus = dropStatus
    self.matches = matches
  }
}
