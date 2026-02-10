import SwiftUI

/// UI for resolving git rebase conflicts per-file.
///
/// Notes:
/// - This assumes a rebase is currently in-progress (started via `AppViewModel.showSyncConflictDetails()`).
/// - Per-file actions use `git checkout --ours/--theirs` then stage the file.
struct SyncConflictDetailsView: View {
  @ObservedObject var vm: AppViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .center, spacing: 10) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        VStack(alignment: .leading, spacing: 2) {
          Text("Sync Conflict Details")
            .font(.headline)
            .fontWeight(.bold)
          Text("Choose how to resolve each conflicted file, then continue the rebase.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button("Refresh") {
          vm.syncConflictRefreshFiles()
        }
        .buttonStyle(.plain)
        .font(.footnote.weight(.semibold))
      }

      if let err = vm.syncConflictLastError, !err.isEmpty {
        Text(err)
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
          .background(Color.orange.opacity(0.12))
          .clipShape(RoundedRectangle(cornerRadius: 8))
      }

      if vm.syncConflictFiles.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("No conflicted files detected.")
            .font(.callout)
          Text("If a rebase is still in progress, try Refresh. Otherwise you can close this window.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
      } else {
        Text("Conflicted files")
          .font(.subheadline)
          .fontWeight(.semibold)

        List {
          ForEach(vm.syncConflictFiles, id: \.self) { path in
            HStack(spacing: 10) {
              Text(path)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .lineLimit(2)
              Spacer()
              Button("Keep Mine") {
                vm.syncConflictResolveFileKeepingMine(path)
              }
              .buttonStyle(.bordered)
              .controlSize(.small)

              Button("Use Remote") {
                vm.syncConflictResolveFileUsingRemote(path)
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
            }
            .padding(.vertical, 4)
          }
        }
      }

      HStack(spacing: 10) {
        Button {
          vm.syncConflictAbortRebase()
        } label: {
          Text("Abort")
        }
        .buttonStyle(.bordered)

        Spacer()

        Button {
          vm.syncConflictContinueRebase()
        } label: {
          Text("Continue Rebase")
        }
        .buttonStyle(.borderedProminent)
        .disabled(vm.isGitBusy)

        Button("Close") {
          vm.syncConflictDetailsPresented = false
        }
        .buttonStyle(.bordered)
      }
    }
    .padding(16)
    .frame(minWidth: 680, minHeight: 420)
  }
}
