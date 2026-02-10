import AppKit
import Combine
import Foundation

/// Menu bar widget for ambient awareness of the current / next task.
///
/// Lives inside the main app target (not a separate menu bar app).
@MainActor
final class MenuBarController: NSObject {
  private var statusItem: NSStatusItem?
  private var menu: NSMenu?

  private weak var vm: AppViewModel?
  private var cancellables: Set<AnyCancellable> = []

  func attach(viewModel: AppViewModel) {
    self.vm = viewModel

    if statusItem == nil {
      let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      item.button?.title = "Loading…"
      item.button?.toolTip = "Lobs Dashboard"
      self.statusItem = item

      let menu = NSMenu(title: "Lobs Dashboard")
      self.menu = menu
      item.menu = menu
    }

    // Rebuild whenever tasks/projects change.
    cancellables.removeAll()
    viewModel.$tasks
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.refresh() }
      .store(in: &cancellables)

    viewModel.$projects
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.refresh() }
      .store(in: &cancellables)

    viewModel.$selectedTaskId
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.refresh() }
      .store(in: &cancellables)

    refresh()
  }

  private func refresh() {
    guard let statusItem, let menu else { return }

    let (current, next) = computeCurrentAndNextTask()

    // Title: keep it compact; menu bar real estate is precious.
    let title: String
    if let current {
      title = truncateTitle(current.title, max: 26)
      statusItem.button?.toolTip = current.title
    } else {
      title = "No tasks"
      statusItem.button?.toolTip = "No active tasks"
    }
    statusItem.button?.title = title

    // Menu
    menu.removeAllItems()

    if let current {
      let cur = NSMenuItem(title: "Current: \(current.title)", action: #selector(selectTaskFromMenu(_:)), keyEquivalent: "")
      cur.target = self
      cur.representedObject = current.id
      menu.addItem(cur)
    } else {
      let cur = NSMenuItem(title: "Current: (none)", action: nil, keyEquivalent: "")
      cur.isEnabled = false
      menu.addItem(cur)
    }

    if let next {
      let nxt = NSMenuItem(title: "Next: \(next.title)", action: #selector(selectTaskFromMenu(_:)), keyEquivalent: "")
      nxt.target = self
      nxt.representedObject = next.id
      menu.addItem(nxt)
    } else {
      let nxt = NSMenuItem(title: "Next: (none)", action: nil, keyEquivalent: "")
      nxt.isEnabled = false
      menu.addItem(nxt)
    }

    menu.addItem(.separator())

    let open = NSMenuItem(title: "Open Dashboard", action: #selector(openDashboard(_:)), keyEquivalent: "")
    open.target = self
    menu.addItem(open)

    let reload = NSMenuItem(title: "Refresh", action: #selector(refreshNow(_:)), keyEquivalent: "r")
    reload.keyEquivalentModifierMask = [.command]
    reload.target = self
    menu.addItem(reload)

    menu.addItem(.separator())

    let quit = NSMenuItem(title: "Quit Lobs Dashboard", action: #selector(quitApp(_:)), keyEquivalent: "q")
    quit.keyEquivalentModifierMask = [.command]
    quit.target = self
    menu.addItem(quit)
  }

  private func computeCurrentAndNextTask() -> (current: DashboardTask?, next: DashboardTask?) {
    guard let vm else { return (nil, nil) }

    let projectsById = Dictionary(uniqueKeysWithValues: vm.projects.map { ($0.id, $0) })

    // Prefer actionable work: active/waiting_on/unknown statuses.
    // Inbox is treated as lower priority (it’s a staging area).
    var actionable: [DashboardTask] = []
    var inbox: [DashboardTask] = []

    for t in vm.tasks {
      // Skip archived projects.
      let pid = t.projectId ?? "default"
      if let p = projectsById[pid], (p.archived ?? false) == true { continue }

      switch t.status {
      case .completed, .rejected:
        continue
      case .inbox:
        inbox.append(t)
      case .active, .waitingOn, .other:
        actionable.append(t)
      }
    }

    let sortedActionable = sortForMenubar(actionable)
    let sortedInbox = sortForMenubar(inbox)

    let all = sortedActionable + sortedInbox
    guard !all.isEmpty else { return (nil, nil) }

    // If the user already has a selected task, treat it as “current” when it still exists.
    if let sel = vm.selectedTaskId, let selected = all.first(where: { $0.id == sel }) {
      let next = all.first(where: { $0.id != selected.id })
      return (selected, next)
    }

    let cur = all.first
    let nxt = all.dropFirst().first
    return (cur, nxt)
  }

  private func sortForMenubar(_ tasks: [DashboardTask]) -> [DashboardTask] {
    tasks.sorted { a, b in
      let ap = a.pinned ?? false
      let bp = b.pinned ?? false
      if ap != bp { return ap && !bp }

      let oa = a.sortOrder ?? Int.max
      let ob = b.sortOrder ?? Int.max
      if oa != ob { return oa < ob }

      if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
      return a.updatedAt > b.updatedAt
    }
  }

  private func truncateTitle(_ title: String, max: Int) -> String {
    guard title.count > max else { return title }
    let idx = title.index(title.startIndex, offsetBy: max)
    return String(title[..<idx]) + "…"
  }

  @objc private func selectTaskFromMenu(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String,
          let vm else { return }

    openDashboard(nil)

    // Best-effort select without changing project; the main UI already scopes
    // tasks by selected project. Selecting a task from another project is still
    // useful because it drives artifact preview + deep link behavior.
    if let t = vm.tasks.first(where: { $0.id == id }) {
      vm.selectTask(t)
    }
  }

  @objc private func openDashboard(_ sender: Any?) {
    NSApp.activate(ignoringOtherApps: true)
    // Bring an existing window forward if one exists.
    if let win = NSApp.windows.first {
      win.makeKeyAndOrderFront(nil)
    }
  }

  @objc private func refreshNow(_ sender: Any?) {
    vm?.silentReload()
  }

  @objc private func quitApp(_ sender: Any?) {
    NSApp.terminate(nil)
  }
}

@MainActor
final class LobsDashboardAppDelegate: NSObject, NSApplicationDelegate {
  let menuBar = MenuBarController()

  func applicationDidFinishLaunching(_ notification: Notification) {
    // AppViewModel is attached from SwiftUI onAppear.
  }
}
