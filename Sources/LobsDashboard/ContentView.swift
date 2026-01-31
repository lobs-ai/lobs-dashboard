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

  var body: some View {
    NavigationSplitView {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Button("Choose lobs-control…") { showPicker = true }
          Button("Reload") { vm.reload() }
          Toggle("Auto-push", isOn: $autoPush)
            .toggleStyle(.switch)
        }

        if let repo = vm.repoURL {
          Text("Repo: \(repo.path)")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Text("Repo: (not set)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if let err = vm.lastError {
          Text("Error: \(err)")
            .font(.caption)
            .foregroundStyle(.red)
        }

        Spacer()
      }
      .padding()
    } detail: {
      VStack(alignment: .leading, spacing: 12) {
        // Actions: review vs completion are separate.
        HStack {
          Button("Approve") { vm.approveSelected(autoPush: autoPush) }
            .disabled(vm.selectedTaskId == nil)
          Button("Request changes") { vm.requestChangesSelected(autoPush: autoPush) }
            .disabled(vm.selectedTaskId == nil)
          Button("Reject") { vm.rejectSelected(autoPush: autoPush) }
            .disabled(vm.selectedTaskId == nil)

          Divider()

          Button("Mark complete") { vm.completeSelected(autoPush: autoPush) }
            .disabled(vm.selectedTaskId == nil)

          Button("Approve + complete") {
            vm.approveSelected(autoPush: autoPush)
            vm.completeSelected(autoPush: autoPush)
          }
          .disabled(vm.selectedTaskId == nil)
        }

        // Kanban board
        ScrollView([.horizontal, .vertical]) {
          HStack(alignment: .top, spacing: 12) {
            ForEach(vm.columns, id: \.title) { col in
              VStack(alignment: .leading, spacing: 8) {
                Text(col.title)
                  .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                  ForEach(vm.tasks.filter(col.matches)) { t in
                    TaskTile(task: t, isSelected: vm.selectedTaskId == t.id)
                      .onTapGesture { vm.selectTask(t) }
                      .onDrag {
                        vm.draggingTaskId = t.id
                        return NSItemProvider(object: t.id as NSString)
                      }
                  }
                }
                .frame(width: 280, alignment: .topLeading)
                .padding(8)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                  RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.25))
                )
                .onDrop(
                  of: [.text],
                  delegate: TaskDropDelegate(status: col.dropStatus, vm: vm)
                )
              }
            }
          }
          .padding(12)
        }

        Divider()

        ScrollView {
          Text(vm.artifactText)
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .padding()
    }
    .navigationSplitViewStyle(.balanced)
    // Fix “left panel is too small by default”.
    .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 520)
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
    .onAppear { vm.reloadIfPossible() }
  }
}

private struct TaskTile: View {
  let task: DashboardTask
  let isSelected: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(task.title)
        .font(.subheadline)
        .fontWeight(.semibold)
        .lineLimit(3)

      HStack(spacing: 6) {
        Text(task.owner.rawValue)
          .font(.caption2)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.gray.opacity(0.15))
          .clipShape(Capsule())

        if let ws = task.workState {
          Text(ws.rawValue)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.12))
            .clipShape(Capsule())
        }

        if let rs = task.reviewState {
          Text(rs.rawValue)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.12))
            .clipShape(Capsule())
        }
      }

      if let notes = task.notes, !notes.isEmpty {
        Text(notes)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(isSelected ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.02))
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.2))
    )
  }
}
