import SwiftUI

struct ContentView: View {
  @EnvironmentObject var vm: AppViewModel
  @State private var showPicker = false
  @State private var autoPush = true
  @State private var newTitle = ""
  @State private var newNotes = ""
  @FocusState private var focusedField: Field?

  private enum Field {
    case title
    case notes
  }

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
          Text("Repo: \(repo.path)").font(.caption).foregroundStyle(.secondary)
        } else {
          Text("Repo: (not set)").font(.caption).foregroundStyle(.secondary)
        }

        if let err = vm.lastError {
          Text("Error: \(err)")
            .font(.caption)
            .foregroundStyle(.red)
        }

        List(selection: $vm.selectedTaskId) {
          Section("Inbox") {
            ForEach(vm.tasks.filter { $0.status == .inbox }) { t in
              Text("[\(t.owner.rawValue)] \(t.title)").tag(Optional(t.id))
            }
          }
          Section("Active") {
            ForEach(vm.tasks.filter { $0.status == .active }) { t in
              Text("[\(t.owner.rawValue)] \(t.title)").tag(Optional(t.id))
            }
          }
          Section("Completed") {
            ForEach(vm.tasks.filter { $0.status == .completed }) { t in
              Text("[\(t.owner.rawValue)] \(t.title)").tag(Optional(t.id))
            }
          }
        }
        .onChange(of: vm.selectedTaskId) { _ in
          vm.reload()
        }

        Spacer()
      }
      .padding()
    } detail: {
      VStack(alignment: .leading, spacing: 12) {
        VStack(alignment: .leading, spacing: 6) {
          TextField("New task title…", text: $newTitle)
            .textFieldStyle(.roundedBorder)
            .focused($focusedField, equals: .title)
          TextEditor(text: $newNotes)
            .font(.system(.body))
            .frame(minHeight: 80)
            .overlay(
              RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.3))
            )
            .focused($focusedField, equals: .notes)
          HStack {
            Button("Submit to Lobs") {
              vm.submitTaskToLobs(title: newTitle, notes: newNotes, autoPush: autoPush)
              newTitle = ""
              newNotes = ""
              focusedField = .title
            }
            .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.repoURL == nil)
          }
        }

        HStack {
          Button("✅ Approve") { vm.approveSelected(autoPush: autoPush) }
            .disabled(vm.selectedTaskId == nil)
          Button("❌ Reject") { vm.rejectSelected(autoPush: autoPush) }
            .disabled(vm.selectedTaskId == nil)
        }

        ScrollView {
          Text(vm.artifactText)
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        Spacer()
      }
      .padding()
    }
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
    .onAppear {
      vm.reloadIfPossible()
      focusedField = .title
    }
  }
}
