import SwiftUI

/// Dashboard setup screen - checks minimal prerequisites for the dashboard app itself
struct OnboardingDashboardSetupView: View {
  @EnvironmentObject private var wizard: OnboardingWizardContext

  let onComplete: () -> Void

  private let commandTimeoutSeconds: Double = 5

  @State private var isChecking: Bool = false

  @State private var gitOK: Bool = false
  @State private var gitDetail: String = ""
  @State private var gitError: String? = nil
  @State private var gitExpanded: Bool = false

  var body: some View {
    VStack(spacing: 28) {
      Spacer()

      VStack(spacing: 10) {
        Text("Dashboard Setup")
          .font(.system(size: 28, weight: .semibold))
        Text("Let's make sure you have what the dashboard needs to work.")
          .font(.system(size: 14))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 560)
      }

      VStack(alignment: .leading, spacing: 12) {
        prereqDisclosure(
          title: "Git installed",
          ok: gitOK,
          detail: gitDetail,
          error: gitError,
          expanded: $gitExpanded,
          help: { gitHelp }
        )
      }
      .frame(width: 600)
      .padding(20)
      .background(Theme.cardBg)
      .cornerRadius(12)
      .overlay(
        RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1)
      )

      // Info note
      HStack(spacing: 8) {
        Image(systemName: "info.circle")
          .foregroundColor(.secondary)
          .font(.system(size: 13))
        Text("The dashboard needs Git to clone and manage your control repository. Server setup (Node.js, Python, etc.) comes next.")
          .font(.system(size: 13))
          .foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(width: 600)

      Spacer()

      Button(action: { Task { await refresh() } }) {
        Text(isChecking ? "Checking…" : "Refresh")
          .font(.system(size: 14, weight: .medium))
          .foregroundColor(.primary)
          .frame(width: 140)
          .padding(.vertical, 10)
      }
      .buttonStyle(.plain)
      .background(Theme.cardBg)
      .cornerRadius(8)
      .disabled(isChecking)
      .padding(.bottom, 20)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.bg)
    .onAppear {
      wizard.configureNext(title: "Next", enabled: gitOK) {
        onComplete()
      }
      wizard.configureSkip(shown: false)
      Task { await refresh() }
    }
    .onChange(of: gitOK) { ok in
      wizard.updateNextEnabled(ok)
    }
  }

  private func prereqDisclosure(
    title: String,
    ok: Bool,
    detail: String,
    error: String?,
    expanded: Binding<Bool>,
    @ViewBuilder help: () -> some View
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
          .foregroundColor(ok ? .green : .red)
          .frame(width: 18)

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.system(size: 14, weight: .medium))

          Text(detail.isEmpty ? (ok ? "OK" : "Missing") : detail)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        }

        Spacer()

        if !ok {
          Button(action: { expanded.wrappedValue.toggle() }) {
            Text(expanded.wrappedValue ? "Hide" : "Fix")
              .font(.system(size: 12, weight: .medium))
              .foregroundColor(Theme.accent)
          }
          .buttonStyle(.plain)
        }
      }

      if let error, !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text(error)
          .font(.system(size: 12, design: .monospaced))
          .foregroundColor(.red)
          .textSelection(.enabled)
      }

      if !ok && expanded.wrappedValue {
        help()
          .padding(.leading, 30)
          .padding(.top, 4)
      }

      Divider().opacity(0.6)
    }
  }

  private var gitHelp: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Install Git")
        .font(.system(size: 12, weight: .semibold))

      Text("On macOS, Git is installed with Xcode Command Line Tools.")
        .font(.system(size: 12))
        .foregroundColor(.secondary)

      Text("xcode-select --install")
        .font(.system(size: 12, design: .monospaced))
        .textSelection(.enabled)
        .padding(8)
        .background(Theme.bg.opacity(0.35))
        .cornerRadius(8)

      Link("Apple developer tools", destination: URL(string: "https://developer.apple.com/xcode/resources/")!)
        .font(.system(size: 12))
    }
  }

  private func refresh() async {
    await MainActor.run {
      isChecking = true
      gitError = nil
      gitDetail = "Checking…"
    }

    // Git check
    do {
      let gitPath = await Shell.which("git")
      if gitPath == nil {
        await MainActor.run {
          gitOK = false
          gitDetail = "Not found in PATH"
          gitExpanded = true
        }
      } else {
        let res = await Shell.envAsync("git", ["--version"], timeoutSeconds: commandTimeoutSeconds)
        await MainActor.run {
          gitOK = res.ok
          gitDetail = res.ok ? res.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : "Git command failed"
          gitError = res.ok ? nil : cleanError(res)
          gitExpanded = !res.ok
        }
      }
    }

    await MainActor.run {
      isChecking = false
    }
  }

  private func cleanError(_ res: Shell.Result) -> String {
    let stderr = res.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    if !stderr.isEmpty { return stderr }
    let stdout = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    if !stdout.isEmpty { return stdout }
    return "Command failed (exit code \(res.exitCode))"
  }
}

#Preview {
  OnboardingDashboardSetupView(onComplete: {})
    .environmentObject(OnboardingWizardContext())
    .frame(width: 900, height: 650)
}
