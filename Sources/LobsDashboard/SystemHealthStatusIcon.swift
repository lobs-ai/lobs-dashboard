import SwiftUI

/// Compact system-health indicator for the app toolbar.
///
/// This replaces the old Overview "System Health" card: the status is always available,
/// but doesn't take up prime space on the Overview page.
struct SystemHealthStatusIcon: View {
  @ObservedObject var vm: AppViewModel

  @State private var showingPopover: Bool = false

  private struct HealthItem: Identifiable {
    let id = UUID().uuidString
    let key: String
    let value: String
    let color: Color
    let hint: String
  }

  private var workerStale: Bool {
    if let ws = vm.workerStatus { return isWorkerStatusStale(ws) }
    return false
  }

  private var healthItems: [HealthItem] {
    var out: [HealthItem] = []

    // Worker
    if vm.workerStatus == nil {
      out.append(HealthItem(key: "Worker", value: "unknown", color: .secondary, hint: "Worker status file not found yet"))
    } else if workerStale {
      out.append(HealthItem(key: "Worker", value: "stale", color: .orange, hint: "Worker looks active but hasn't heartbeated recently"))
    } else if vm.workerStatus?.active == true {
      out.append(HealthItem(key: "Worker", value: "running", color: .purple, hint: "Worker is currently active"))
    } else {
      out.append(HealthItem(key: "Worker", value: "idle", color: .green, hint: "Worker is idle"))
    }

    // Sync
    if vm.syncBlockedByUncommitted {
      out.append(HealthItem(key: "Sync", value: "blocked", color: .orange, hint: "Local uncommitted changes are preventing sync"))
    } else if vm.pendingChangesCount > 0 {
      out.append(HealthItem(key: "Sync", value: "pending", color: .orange, hint: "You have local commits waiting to push"))
    } else {
      out.append(HealthItem(key: "Sync", value: "ok", color: .green, hint: "Repo is clean / pushed"))
    }

    // Remote drift
    if vm.controlRepoBehind > 0 {
      out.append(HealthItem(key: "Remote", value: "behind", color: .blue, hint: "Origin has \(vm.controlRepoBehind) newer commit(s)"))
    } else {
      out.append(HealthItem(key: "Remote", value: "up to date", color: .green, hint: "Local matches origin"))
    }

    // Push errors
    if let err = vm.lastPushError, !err.isEmpty {
      out.append(HealthItem(key: "Push", value: "failed", color: .red, hint: err))
    }

    return out
  }

  private var overall: (label: String, color: Color, icon: String) {
    if vm.syncBlockedByUncommitted { return ("Needs attention", .orange, "exclamationmark.triangle.fill") }
    if vm.lastPushError != nil { return ("Needs attention", .orange, "exclamationmark.triangle.fill") }
    if workerStale { return ("Needs attention", .orange, "exclamationmark.triangle.fill") }
    if vm.controlRepoBehind > 0 { return ("Updates available", .blue, "arrow.down.circle.fill") }
    return ("Healthy", .green, "heart.fill")
  }

  var body: some View {
    Button {
      showingPopover.toggle()
    } label: {
      Image(systemName: overall.icon)
        .font(.body)
        .foregroundStyle(overall.color)
        .padding(6)
        .background(Color.primary.opacity(showingPopover ? 0.08 : 0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(Color.primary.opacity(showingPopover ? 0.12 : 0), lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
    .help("System Health — \(overall.label)")
    .popover(isPresented: $showingPopover, arrowEdge: .top) {
      SystemHealthPopover(vm: vm)
    }
  }

  private func isWorkerStatusStale(_ status: WorkerStatus) -> Bool {
    // If the worker looks active but hasn't emitted a heartbeat recently, treat the status as stale.
    // This prevents the UI from getting stuck in "running" when the worker crashed or was killed.
    guard status.active else { return false }
    let cutoff: TimeInterval = 10 * 60
    if let hb = status.lastHeartbeat {
      return Date().timeIntervalSince(hb) > cutoff
    }
    if let started = status.startedAt {
      return Date().timeIntervalSince(started) > cutoff
    }
    return false
  }
}

private struct SystemHealthPopover: View {
  @ObservedObject var vm: AppViewModel

  private struct HealthRow: View {
    let key: String
    let value: String
    let color: Color
    let hint: String

    var body: some View {
      HStack(spacing: 10) {
        Text(key)
          .font(.callout)
          .foregroundStyle(.secondary)
          .frame(width: 64, alignment: .leading)
        Text(value)
          .font(.callout)
          .fontWeight(.semibold)
          .foregroundStyle(color)
        Spacer()
      }
      .help(hint)
    }
  }

  private var workerStale: Bool {
    if let ws = vm.workerStatus {
      guard ws.active else { return false }
      let cutoff: TimeInterval = 10 * 60
      if let hb = ws.lastHeartbeat { return Date().timeIntervalSince(hb) > cutoff }
      if let started = ws.startedAt { return Date().timeIntervalSince(started) > cutoff }
    }
    return false
  }

  private var overall: (label: String, color: Color) {
    if vm.syncBlockedByUncommitted { return ("Needs attention", .orange) }
    if vm.lastPushError != nil { return ("Needs attention", .orange) }
    if workerStale { return ("Needs attention", .orange) }
    if vm.controlRepoBehind > 0 { return ("Updates available", .blue) }
    return ("Healthy", .green)
  }

  private var items: [(String, String, Color, String)] {
    var out: [(String, String, Color, String)] = []

    if vm.workerStatus == nil {
      out.append(("Worker", "unknown", .secondary, "Worker status file not found yet"))
    } else if workerStale {
      out.append(("Worker", "stale", .orange, "Worker looks active but hasn't heartbeated recently"))
    } else if vm.workerStatus?.active == true {
      out.append(("Worker", "running", .purple, "Worker is currently active"))
    } else {
      out.append(("Worker", "idle", .green, "Worker is idle"))
    }

    if vm.syncBlockedByUncommitted {
      out.append(("Sync", "blocked", .orange, "Local uncommitted changes are preventing sync"))
    } else if vm.pendingChangesCount > 0 {
      out.append(("Sync", "pending", .orange, "You have local commits waiting to push"))
    } else {
      out.append(("Sync", "ok", .green, "Repo is clean / pushed"))
    }

    if vm.controlRepoBehind > 0 {
      out.append(("Remote", "behind", .blue, "Origin has \(vm.controlRepoBehind) newer commit(s)"))
    } else {
      out.append(("Remote", "up to date", .green, "Local matches origin"))
    }

    if let err = vm.lastPushError, !err.isEmpty {
      out.append(("Push", "failed", .red, err))
    }

    return out
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Image(systemName: "heart.text.square.fill")
          .foregroundStyle(overall.color)
        Text("System Health")
          .font(.headline)
          .fontWeight(.bold)
        Spacer()
        Text(overall.label)
          .font(.caption)
          .foregroundStyle(overall.color)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(overall.color.opacity(0.12))
          .clipShape(Capsule())
      }

      VStack(alignment: .leading, spacing: 8) {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
          let (k, v, c, hint) = item
          HealthRow(key: k, value: v, color: c, hint: hint)
        }
      }

      Divider()

      HStack(spacing: 10) {
        Button {
          vm.reloadIfPossible()
        } label: {
          HStack(spacing: 6) {
            Image(systemName: "arrow.clockwise")
            Text("Refresh")
          }
        }

        if vm.pendingChangesCount > 0 || (vm.lastPushError != nil) {
          Button {
            vm.pushNow()
          } label: {
            HStack(spacing: 6) {
              Image(systemName: "arrow.up.circle.fill")
              Text("Push Now")
            }
          }
          .tint(.orange)
        }

        Spacer()
      }
      .controlSize(.small)
    }
    .padding(14)
    .frame(width: 320)
  }
}

// #Preview {
// SystemHealthStatusIcon(vm: AppViewModel())
// }
