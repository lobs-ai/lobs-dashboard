import SwiftUI

struct OnboardingAgentSetupView: View {
  @EnvironmentObject private var wizard: OnboardingWizardContext

  let workspacePath: String
  let initialAgentName: String
  let initialUserName: String
  let onComplete: (String, String) -> Void

  @State private var agentName: String
  @State private var userName: String
  @State private var timezone: String

  @State private var error: String? = nil

  private var canProceed: Bool {
    !agentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !timezone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  init(
    workspacePath: String,
    initialAgentName: String,
    initialUserName: String,
    onComplete: @escaping (String, String) -> Void
  ) {
    self.workspacePath = workspacePath
    self.initialAgentName = initialAgentName
    self.initialUserName = initialUserName
    self.onComplete = onComplete

    self._agentName = State(initialValue: initialAgentName)
    self._userName = State(initialValue: initialUserName)
    self._timezone = State(initialValue: TimeZone.current.identifier)
  }

  private var lobsWorkspaceURL: URL {
    URL(fileURLWithPath: workspacePath).appendingPathComponent("lobs-workspace")
  }

  var body: some View {
    VStack(spacing: 24) {
      Spacer()

      VStack(spacing: 10) {
        Text("Set Up Your Agent")
          .font(.system(size: 28, weight: .semibold))
        Text("This writes a few simple files that shape how your assistant behaves.")
          .font(.system(size: 14))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 600)
      }

      VStack(alignment: .leading, spacing: 14) {
        field(label: "Assistant name", text: $agentName, placeholder: "Lobs")
        field(label: "Your name", text: $userName, placeholder: "Rafe")

        VStack(alignment: .leading, spacing: 6) {
          Text("Timezone")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.secondary)
          TextField("America/New_York", text: $timezone)
            .textFieldStyle(.plain)
            .font(.system(size: 14, design: .monospaced))
            .padding(10)
            .background(Theme.cardBg)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
          Text("Auto-detected. You can change this later.")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        }

        if let error {
          Text(error)
            .font(.system(size: 13))
            .foregroundColor(.red)
        }

        Text("Files written to: \(lobsWorkspaceURL.path)")
          .font(.system(size: 12))
          .foregroundColor(.secondary)
      }
      .frame(width: 600)

      Spacer()

      Text("Use Next to write these files")
        .font(.system(size: 13))
        .foregroundColor(.secondary)
        .padding(.bottom, 20)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.bg)
    .onAppear {
      wizard.configureNext(title: "Next", enabled: canProceed) {
        writeAndContinue()
      }
      wizard.configureSkip(shown: false)
    }
    .onChange(of: canProceed) { ok in
      wizard.updateNextEnabled(ok)
    }
  }

  private func field(label: String, text: Binding<String>, placeholder: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label)
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.secondary)
      TextField(placeholder, text: text)
        .textFieldStyle(.plain)
        .font(.system(size: 14))
        .padding(10)
        .background(Theme.cardBg)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
    }
  }

  private func writeAndContinue() {
    let agent = agentName.trimmingCharacters(in: .whitespacesAndNewlines)
    let user = userName.trimmingCharacters(in: .whitespacesAndNewlines)
    let tz = timezone.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !agent.isEmpty else { error = "Assistant name cannot be empty."; return }
    guard !user.isEmpty else { error = "Your name cannot be empty."; return }
    guard !tz.isEmpty else { error = "Timezone cannot be empty."; return }

    do {
      try FileManager.default.createDirectory(at: lobsWorkspaceURL, withIntermediateDirectories: true)

      let identity = """
      # IDENTITY.md

      - **Name:** \(agent)
      - **Role:** Your async AI assistant
      - **Timezone:** \(tz)
      """

      let userFile = """
      # USER.md

      - **Name:** \(user)
      - **Timezone:** \(tz)
      - **Preferences:**
        - Quality > speed (but ship when done)
        - Clean, tested code
        - Clear commit messages
        - Don’t break existing stuff
      """

      let soul = """
      # SOUL.md

      You are \(agent), an async AI assistant.

      - Be direct and pragmatic.
      - Prefer safe, reversible changes.
      - Keep messages concise and information-dense.
      """

      try identity.write(to: lobsWorkspaceURL.appendingPathComponent("IDENTITY.md"), atomically: true, encoding: .utf8)
      try userFile.write(to: lobsWorkspaceURL.appendingPathComponent("USER.md"), atomically: true, encoding: .utf8)
      try soul.write(to: lobsWorkspaceURL.appendingPathComponent("SOUL.md"), atomically: true, encoding: .utf8)

      error = nil
      onComplete(agent, user)
    } catch {
      self.error = "Failed to write agent files: \(error.localizedDescription)"
    }
  }
}

#Preview {
  OnboardingAgentSetupView(workspacePath: LobsPaths.defaultWorkspace, initialAgentName: "Lobs", initialUserName: "Rafe", onComplete: { _, _ in })
    .environmentObject(OnboardingWizardContext())
    .frame(width: 800, height: 600)
}
