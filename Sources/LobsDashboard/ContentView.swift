import SwiftUI

private struct TaskDropDelegate: DropDelegate {
  let status: TaskStatus
  let vm: AppViewModel

  func validateDrop(info: DropInfo) -> Bool { true }

  func performDrop(info: DropInfo) -> Bool {
    guard let id = vm.draggingTaskId else { return false }
    vm.moveTask(taskId: id, to: status)
    return true
  }
}

struct ContentView: View {
  @EnvironmentObject var vm: AppViewModel

  @State private var showPicker = false
  @State private var autoPush = true

  @State private var showAddTask = false

  @State private var showAllCompleted = false
  @State private var showAllRejected = false

  var selectedTask: DashboardTask? {
    guard let id = vm.selectedTaskId else { return nil }
    return vm.tasks.first(where: { $0.id == id })
  }

  var body: some View {
    NavigationSplitView {
      SidebarView(
        vm: vm,
        showPicker: $showPicker,
        autoPush: $autoPush,
        showAddTask: $showAddTask
      )
      .frame(minWidth: 260)

    } content: {
      BoardView(
        vm: vm,
        showAllCompleted: $showAllCompleted,
        showAllRejected: $showAllRejected
      )
        .navigationTitle("Lobs Dashboard")
        .toolbar {
          ToolbarItemGroup {
            Button {
              showAddTask = true
            } label: {
              Label("New task", systemImage: "plus")
            }
            .help("Create a new task for Lobs to work on")

            Button {
              vm.reload()
            } label: {
              Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Pull latest from GitHub and reload tasks")

            TextField("Search", text: $vm.searchText)
              .textFieldStyle(.roundedBorder)
              .frame(width: 220)
              .help("Search title + notes")

            Menu {
              Button("All") { vm.ownerFilter = "all" }
              Button("Owner: Lobs") { vm.ownerFilter = "lobs" }
              Button("Owner: Rafe") { vm.ownerFilter = "rafe" }
              Button("Owner: Other") { vm.ownerFilter = "other" }
            } label: {
              Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            }
            .help("Filter tasks")

            Toggle(isOn: $autoPush) {
              Label("Auto-push", systemImage: autoPush ? "arrow.up.circle.fill" : "arrow.up.circle")
            }
            .help("When enabled, task changes are committed and pushed to GitHub")
          }
        }

    } detail: {
      InspectorView(vm: vm, selectedTask: selectedTask, autoPush: $autoPush)
        .frame(minWidth: 360)
    }
    // Fix “left panel is too small by default”.
    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
    .fileImporter(
      isPresented: $showPicker,
      allowedContentTypes: [.folder]
    ) { result in
      switch result {
      case .success(let url):
        vm.setRepoURL(url)
        vm.reload()
      case .failure(let err):
        vm.lastError = String(describing: err)
      }
    }
    .sheet(isPresented: $showAddTask) {
      AddTaskSheet(vm: vm, autoPush: $autoPush)
    }
    .onAppear { vm.reloadIfPossible() }
  }
}

private struct SidebarView: View {
  @ObservedObject var vm: AppViewModel

  @Binding var showPicker: Bool
  @Binding var autoPush: Bool
  @Binding var showAddTask: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Repo")
          .font(.headline)

        Button {
          showPicker = true
        } label: {
          Label("Choose lobs-control…", systemImage: "folder")
        }
        .help("Pick your local lobs-control folder")

        if let repo = vm.repoURL {
          Text(repo.path)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        } else {
          Text("Not set")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Divider()

      VStack(alignment: .leading, spacing: 6) {
        Text("Actions")
          .font(.headline)

        Button {
          showAddTask = true
        } label: {
          Label("New task", systemImage: "plus")
        }

        Toggle("Auto-push", isOn: $autoPush)
          .toggleStyle(.switch)

        if let err = vm.lastError {
          Divider()
          Text("Error")
            .font(.headline)
          Text(err)
            .font(.caption)
            .foregroundStyle(.red)
            .textSelection(.enabled)
        }
      }

      Spacer()
    }
    .padding()
  }
}

private struct BoardView: View {
  @ObservedObject var vm: AppViewModel
  @Binding var showAllCompleted: Bool
  @Binding var showAllRejected: Bool

  var body: some View {
    ScrollView(.horizontal) {
      HStack(alignment: .top, spacing: 14) {
        ForEach(vm.columns, id: \.title) { col in
          BoardColumn(
            title: col.title,
            tasks: vm.filteredTasks.filter(col.matches),
            dropStatus: col.dropStatus,
            vm: vm,
            showAllCompleted: $showAllCompleted,
            showAllRejected: $showAllRejected
          )
        }
      }
      .padding(14)
    }
    .background(Color(nsColor: .underPageBackgroundColor))
  }
}

private struct BoardColumn: View {
  let title: String
  let tasks: [DashboardTask]
  let dropStatus: TaskStatus

  @ObservedObject var vm: AppViewModel

  @Binding var showAllCompleted: Bool
  @Binding var showAllRejected: Bool

  var body: some View {
    let isCompleted = title.lowercased() == "completed"
    let isRejected = title.lowercased() == "rejected"

    let showAll = isCompleted ? showAllCompleted : (isRejected ? showAllRejected : true)
    let visibleTasks = (isCompleted || isRejected) && !showAll
      ? Array(tasks.sorted { $0.updatedAt > $1.updatedAt }.prefix(vm.completedShowRecent))
      : tasks

    let wipLimit = (title.lowercased() == "active") ? vm.wipLimitActive : 0

    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text(title)
          .font(.headline)

        if wipLimit > 0 && tasks.count > wipLimit {
          Text("WIP")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.2))
            .clipShape(Capsule())
            .help("Active WIP limit exceeded")
        }

        Spacer()

        Text("\(tasks.count)")
          .font(.caption)
          .foregroundStyle(.secondary)

        if isCompleted {
          Button {
            showAllCompleted.toggle()
          } label: {
            Image(systemName: showAllCompleted ? "chevron.down" : "chevron.right")
          }
          .buttonStyle(.plain)
          .help(showAllCompleted ? "Show only recent" : "Show all")
        }

        if isRejected {
          Button {
            showAllRejected.toggle()
          } label: {
            Image(systemName: showAllRejected ? "chevron.down" : "chevron.right")
          }
          .buttonStyle(.plain)
          .help(showAllRejected ? "Show only recent" : "Show all")
        }
      }

      if (isCompleted || isRejected) && !showAll {
        Text("Showing most recent \(min(vm.completedShowRecent, tasks.count))")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 10) {
          ForEach(visibleTasks) { t in
            TaskTile(task: t, isSelected: vm.selectedTaskId == t.id)
              .onTapGesture { vm.selectTask(t) }
              .onDrag {
                vm.draggingTaskId = t.id
                return NSItemProvider(object: t.id as NSString)
              }
          }
        }
        .padding(10)
      }
      .frame(width: 320, height: 520)
      .background(Color(nsColor: .windowBackgroundColor))
      .clipShape(RoundedRectangle(cornerRadius: 14))
      .overlay(
        RoundedRectangle(cornerRadius: 14)
          .stroke(Color.gray.opacity(0.2))
      )
      .onDrop(of: [.text], delegate: TaskDropDelegate(status: dropStatus, vm: vm))
    }
  }
}

private struct InspectorView: View {
  @ObservedObject var vm: AppViewModel
  let selectedTask: DashboardTask?
  @Binding var autoPush: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let task = selectedTask {
        VStack(alignment: .leading, spacing: 6) {
          Text(task.title)
            .font(.title3)
            .fontWeight(.semibold)

          HStack(spacing: 8) {
            Tag(text: task.owner.rawValue, tint: .gray)
            Tag(text: task.status.rawValue, tint: .blue)
            if let ws = task.workState { Tag(text: ws.rawValue, tint: .indigo) }
            if let rs = task.reviewState { Tag(text: rs.rawValue, tint: .green) }
          }

          if let notes = task.notes, !notes.isEmpty {
            Text(notes)
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }

        Divider()

        GroupBox("Review") {
          VStack(alignment: .leading, spacing: 10) {
            HStack {
              Button {
                vm.approveSelected(autoPush: autoPush)
              } label: {
                Label("Approve", systemImage: "checkmark.seal")
              }
              .help("Marks reviewState=approved")

              Button {
                vm.requestChangesSelected(autoPush: autoPush)
              } label: {
                Label("Request changes", systemImage: "pencil.and.outline")
              }
              .help("Marks reviewState=changes_requested")
            }

            Button {
              vm.rejectSelected(autoPush: autoPush)
            } label: {
              Label("Reject", systemImage: "xmark.seal")
            }
            .help("Marks reviewState=rejected")
          }
        }

        GroupBox("Completion") {
          VStack(alignment: .leading, spacing: 10) {
            Button {
              vm.completeSelected(autoPush: autoPush)
            } label: {
              Label("Mark complete", systemImage: "checkmark.circle")
            }
            .help("Moves the task to status=completed")

            Button {
              vm.approveSelected(autoPush: autoPush)
              vm.completeSelected(autoPush: autoPush)
            } label: {
              Label("Approve + complete", systemImage: "checkmark.circle.badge.checkmark")
            }
            .help("Sets reviewState=approved then status=completed")
          }
        }

        Divider()

        Text("Artifact")
          .font(.headline)

        ScrollView {
          Text(vm.artifactText)
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }

      } else {
        VStack(alignment: .leading, spacing: 8) {
          Text("Select a task")
            .font(.title3)
            .fontWeight(.semibold)
          Text("Click a card on the board to see details, review actions, and the artifact.")
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
    }
    .padding()
  }
}

private struct AddTaskSheet: View {
  @ObservedObject var vm: AppViewModel
  @Binding var autoPush: Bool

  @Environment(\.dismiss) private var dismiss

  @State private var title: String = ""
  @State private var notes: String = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("New task for Lobs")
        .font(.title2)
        .fontWeight(.semibold)

      TextField("Title", text: $title)
        .textFieldStyle(.roundedBorder)

      TextField("Notes (optional)", text: $notes, axis: .vertical)
        .textFieldStyle(.roundedBorder)
        .lineLimit(4, reservesSpace: true)

      HStack {
        Button("Cancel") { dismiss() }

        Spacer()

        Button {
          vm.submitTaskToLobs(title: title, notes: notes.isEmpty ? nil : notes, autoPush: autoPush)
          dismiss()
        } label: {
          Label("Create", systemImage: "plus.circle.fill")
        }
        .keyboardShortcut(.defaultAction)
        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }

      Text("Creates a task in lobs-control and (if Auto-push is on) commits + pushes it to GitHub.")
        .font(.caption)
        .foregroundStyle(.secondary)

      Spacer()
    }
    .padding(16)
    .frame(minWidth: 520, minHeight: 260)
  }
}

private struct Tag: View {
  let text: String
  let tint: Color

  var body: some View {
    Text(text)
      .font(.caption2)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(tint.opacity(0.12))
      .foregroundStyle(.primary)
      .clipShape(Capsule())
  }
}

private struct TaskTile: View {
  let task: DashboardTask
  let isSelected: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(task.title)
        .font(.subheadline)
        .fontWeight(.semibold)
        .lineLimit(3)

      HStack(spacing: 6) {
        Tag(text: task.owner.rawValue, tint: .gray)

        if let ws = task.workState {
          Tag(text: ws.rawValue, tint: .indigo)
        }

        if let rs = task.reviewState {
          Tag(text: rs.rawValue, tint: .green)
        }
      }

      if let notes = task.notes, !notes.isEmpty {
        Text(notes)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(isSelected ? Color.accentColor.opacity(0.12) : Color.black.opacity(0.03))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.18))
    )
  }
}
