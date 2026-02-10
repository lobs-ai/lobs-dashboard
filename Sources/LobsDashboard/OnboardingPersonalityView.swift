import SwiftUI
import AppKit

/// Onboarding step: customize the worker's personality prompt files.
struct OnboardingPersonalityView: View {
  @EnvironmentObject var vm: AppViewModel

  let onBack: (() -> Void)?
  let onContinue: () -> Void
  var continueTitle: String = "Save & Continue"
  var showBackButton: Bool = true

  @State private var input: AgentPersonalityManager.WizardInput = .default

  @State private var soulText: String = ""
  @State private var userText: String = ""
  @State private var identityText: String = ""

  @State private var isSaving: Bool = false
  @State private var errorMessage: String? = nil
  @State private var warningMessage: String? = nil

  @State private var selectedEditorTab: EditorTab = .form

  enum EditorTab: String, CaseIterable, Identifiable {
    case form = "Form"
    case soul = "SOUL.md"
    case user = "USER.md"
    case identity = "IDENTITY.md"

    var id: String { rawValue }
  }

  var body: some View {
    VStack(spacing: 22) {
      Spacer(minLength: 10)

      VStack(spacing: 10) {
        Text("Agent Personality")
          .font(.system(size: 28, weight: .semibold))
          .foregroundColor(.primary)

        Text("Set the name, vibe, and preferences that shape how your worker communicates.")
          .font(.system(size: 14))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 560)
      }

      Picker("", selection: $selectedEditorTab) {
        ForEach(EditorTab.allCases) { tab in
          Text(tab.rawValue).tag(tab)
        }
      }
      .pickerStyle(.segmented)
      .frame(width: 560)

      Group {
        switch selectedEditorTab {
        case .form:
          formView
        case .soul:
          fileEditor(title: "SOUL.md", text: $soulText)
        case .user:
          fileEditor(title: "USER.md", text: $userText)
        case .identity:
          fileEditor(title: "IDENTITY.md", text: $identityText)
        }
      }
      .frame(width: 660, height: 320)

      if let err = errorMessage {
        HStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundColor(.red)
          Text(err)
            .font(.system(size: 13))
            .foregroundColor(.red)
        }
        .frame(maxWidth: 660)
      } else if let warn = warningMessage {
        HStack(spacing: 8) {
          Image(systemName: "info.circle")
            .foregroundColor(.orange)
          Text(warn)
            .font(.system(size: 13))
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: 660)
      }

      Spacer(minLength: 10)

      HStack(spacing: 12) {
        if showBackButton, let onBack {
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
          .disabled(isSaving)
          .opacity(isSaving ? 0.5 : 1.0)
        }

        Button(action: regenerateFromForm) {
          Text("Regenerate")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.primary)
            .frame(width: 120)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(Theme.cardBg)
        .cornerRadius(8)
        .disabled(isSaving)
        .opacity(isSaving ? 0.5 : 1.0)
        .help("Rebuild the three files from the form values")

        Button(action: saveAndContinue) {
          HStack(spacing: 8) {
            if isSaving {
              ProgressView().scaleEffect(0.7)
            }
            Text(continueTitle)
              .font(.system(size: 14, weight: .medium))
          }
          .foregroundColor(.white)
          .frame(width: showBackButton ? 160 : 140)
          .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(Theme.accent)
        .cornerRadius(8)
        .disabled(isSaving)
        .opacity(isSaving ? 0.7 : 1.0)
      }
      .padding(.bottom, 44)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.bg)
    .onAppear {
      loadInitial()
    }
  }

  private var formView: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        GroupBox {
          VStack(alignment: .leading, spacing: 10) {
            Text("Worker")
              .font(.system(size: 14, weight: .semibold))

            HStack(spacing: 10) {
              labeledField("Name", text: $input.agentName, placeholder: "Worker")
              labeledField("Vibe", text: $input.agentVibe, placeholder: "Focused, professional, reliable")
            }

            labeledField("Avatar", text: $input.agentAvatar, placeholder: "(N/A — workers don't need avatars)")

            Text("Tip: you can further tweak the markdown in the tabs above.")
              .font(.system(size: 12))
              .foregroundColor(.secondary)
          }
          .padding(6)
        }

        GroupBox {
          VStack(alignment: .leading, spacing: 10) {
            Text("About You")
              .font(.system(size: 14, weight: .semibold))

            HStack(spacing: 10) {
              labeledField("Name", text: $input.userName, placeholder: "Rafe")
              labeledField("Role", text: $input.userRole, placeholder: "Builder")
            }

            HStack(spacing: 10) {
              labeledField("Timezone", text: $input.userTimezone, placeholder: "America/New_York (ET)")
            }

            Text("Preferences")
              .font(.system(size: 12, weight: .medium))
              .foregroundColor(.secondary)
              .padding(.top, 4)

            multiLineListEditor(values: $input.userPreferences)

            Text("Annoyances")
              .font(.system(size: 12, weight: .medium))
              .foregroundColor(.secondary)
              .padding(.top, 4)

            multiLineListEditor(values: $input.userAnnoyances)

            Text("Extra Notes")
              .font(.system(size: 12, weight: .medium))
              .foregroundColor(.secondary)
              .padding(.top, 4)

            TextEditor(text: $input.extraNotes)
              .font(.system(size: 13))
              .frame(height: 80)
              .padding(8)
              .background(Theme.cardBg)
              .cornerRadius(8)
              .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
          }
          .padding(6)
        }
      }
      .padding(4)
    }
  }

  private func labeledField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
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
    .frame(maxWidth: .infinity)
  }

  private func multiLineListEditor(values: Binding<[String]>) -> some View {
    let joined = values.wrappedValue.joined(separator: "\n")

    return TextEditor(
      text: Binding(
        get: { joined },
        set: { newValue in
          let lines = newValue
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
          values.wrappedValue = lines
        }
      )
    )
    .font(.system(size: 13))
    .frame(height: 90)
    .padding(8)
    .background(Theme.cardBg)
    .cornerRadius(8)
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
  }

  private func fileEditor(title: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(title)
          .font(.system(size: 14, weight: .semibold))
        Spacer()
        Button("Copy") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(text.wrappedValue, forType: .string)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }

      TextEditor(text: text)
        .font(.system(size: 13, design: .monospaced))
        .padding(10)
        .background(Theme.cardBg)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
    }
  }

  private func loadInitial() {
    guard let repoPath = vm.config?.controlRepoPath, !repoPath.isEmpty else {
      // This view should only be reachable after repo config exists.
      regenerateFromForm()
      return
    }

    let existing = AgentPersonalityManager.load(repoPath: repoPath)
    soulText = existing.soul
    userText = existing.user
    identityText = existing.identity

    // Also pre-fill the form from defaults so the user has something sensible.
    // (We don't parse existing markdown back into the form.)
    input = .default
  }

  private func regenerateFromForm() {
    errorMessage = nil
    warningMessage = nil

    let generated = AgentPersonalityManager.generateFiles(from: input)
    soulText = generated.soul
    userText = generated.user
    identityText = generated.identity
  }

  private func saveAndContinue() {
    errorMessage = nil
    warningMessage = nil

    guard let repoPath = vm.config?.controlRepoPath, !repoPath.isEmpty else {
      errorMessage = "Missing control repo path."
      return
    }

    isSaving = true

    Task { @MainActor in
      let result = await AgentPersonalityManager.save(
        repoPath: repoPath,
        files: .init(soul: soulText, user: userText, identity: identityText),
        commitMessage: "Update agent personality files"
      )

      isSaving = false

      if !result.success {
        errorMessage = result.warning ?? "Failed to save."
        return
      }

      warningMessage = result.warning
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
        onContinue()
      }
    }
  }
}

#Preview {
  OnboardingPersonalityView(onBack: {}, onContinue: {})
    .environmentObject(AppViewModel())
    .frame(width: 800, height: 600)
}
