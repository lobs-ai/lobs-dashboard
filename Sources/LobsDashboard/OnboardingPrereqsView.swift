import SwiftUI

struct OnboardingPrereqsView: View {
  let onBack: () -> Void
  let onContinue: () -> Void

  @State private var isChecking: Bool = false

  @State private var gitOK: Bool = false
  @State private var nodeOK: Bool = false
  @State private var ghOK: Bool = false

  @State private var nodeVersion: String = ""
  @State private var ghStatus: String = ""

  private var allOK: Bool { gitOK && nodeOK && ghOK }

  var body: some View {
    VStack(spacing: 28) {
      Spacer()

      VStack(spacing: 10) {
        Text("Prerequisites")
          .font(.system(size: 28, weight: .semibold))
        Text("We’ll check a few tools Lobs needs. Fix anything missing, then click Refresh.")
          .font(.system(size: 14))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 560)
      }

      VStack(alignment: .leading, spacing: 14) {
        prereqRow(title: "Git installed", ok: gitOK, detail: gitOK ? "Found" : "Install Xcode Command Line Tools")

        prereqRow(title: "Node.js 18+", ok: nodeOK, detail: nodeOK ? nodeVersion : "Install Node 18+ (nvm recommended)")

        prereqRow(title: "GitHub CLI (gh) authed", ok: ghOK, detail: ghOK ? ghStatus : "Run: gh auth login")
      }
      .frame(width: 560)
      .padding(20)
      .background(Theme.cardBg)
      .cornerRadius(12)
      .overlay(
        RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1)
      )

      if !allOK {
        VStack(alignment: .leading, spacing: 10) {
          Text("Install help")
            .font(.system(size: 13, weight: .semibold))
          Text("• Git: run `xcode-select --install`\n• Node: https://nodejs.org or `brew install node`\n• GitHub CLI: https://cli.github.com then `gh auth login`")
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(.secondary)
            .textSelection(.enabled)
        }
        .frame(width: 560, alignment: .leading)
      }

      Spacer()

      HStack(spacing: 12) {
        Button(action: onBack) {
          Text("Back")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.primary)
            .frame(width: 120)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(Theme.cardBg)
        .cornerRadius(8)

        Button(action: { Task { await refresh() } }) {
          Text(isChecking ? "Checking…" : "Refresh")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.primary)
            .frame(width: 120)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(Theme.cardBg)
        .cornerRadius(8)
        .disabled(isChecking)

        Button(action: onContinue) {
          Text("Next")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 120)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(Theme.accent)
        .cornerRadius(8)
        .disabled(!allOK)
        .opacity(allOK ? 1.0 : 0.5)
      }
      .padding(.bottom, 60)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.bg)
    .onAppear {
      Task { await refresh() }
    }
  }

  private func prereqRow(title: String, ok: Bool, detail: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
        .foregroundColor(ok ? .green : .red)
        .frame(width: 18)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 14, weight: .medium))
        Text(detail)
          .font(.system(size: 12))
          .foregroundColor(.secondary)
      }
      Spacer()
    }
  }

  private func refresh() async {
    await MainActor.run { isChecking = true }

    let git = await Shell.which("git")
    let node = await Shell.which("node")
    let gh = await Shell.which("gh")

    var gitOKLocal = false
    if git != nil {
      let res = await Shell.envAsync("git", ["--version"])
      gitOKLocal = res.ok
    }

    var nodeOKLocal = false
    var nodeVersionLocal = ""
    if node != nil {
      let res = await Shell.envAsync("node", ["-v"])
      nodeVersionLocal = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
      nodeOKLocal = res.ok && nodeVersionAtLeast18(nodeVersionLocal)
    }

    var ghOKLocal = false
    var ghStatusLocal = ""
    if gh != nil {
      let res = await Shell.envAsync("gh", ["auth", "status"]) // exit code 0 when authed
      ghStatusLocal = res.ok ? "Authenticated" : "Not authenticated"
      ghOKLocal = res.ok
    }

    await MainActor.run {
      gitOK = gitOKLocal
      nodeOK = nodeOKLocal
      ghOK = ghOKLocal
      nodeVersion = nodeVersionLocal.isEmpty ? "" : "Detected \(nodeVersionLocal)"
      ghStatus = ghStatusLocal
      isChecking = false
    }
  }

  private func nodeVersionAtLeast18(_ v: String) -> Bool {
    // v like "v20.11.0" or "20.11.0"
    let cleaned = v.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "v"))
    let parts = cleaned.split(separator: ".")
    guard let majorStr = parts.first, let major = Int(majorStr) else { return false }
    return major >= 18
  }
}

#Preview {
  OnboardingPrereqsView(onBack: {}, onContinue: {})
    .frame(width: 800, height: 600)
}
