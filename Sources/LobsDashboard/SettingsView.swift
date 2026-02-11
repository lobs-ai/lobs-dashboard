import SwiftUI

struct SettingsView: View {
  @EnvironmentObject var vm: AppViewModel
  @Environment(\.dismiss) private var dismiss
  
  @State private var showingChangeRepoConfirmation = false
  @State private var showingResetConfirmation = false
  @State private var showingPersonalityEditor = false
  @State private var showingSetupStatus = false
  @State private var showingHelpGuides = false
  @State private var showingServerSetupGuide = false
  @State private var showingRerunOnboardingConfirm = false

  @State private var showingForcePullConfirm: Bool = false
  @State private var showingForcePushConfirm: Bool = false
  
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("Settings")
        .font(.title)
        .fontWeight(.bold)
      
      Divider()
      
      // Configuration Section
      VStack(alignment: .leading, spacing: 12) {
        Text("Configuration")
          .font(.headline)
        
        if let config = vm.config {
          // Control Repo URL
          HStack {
            Text("Control Repository:")
              .foregroundColor(.secondary)
            Spacer()
            Text(config.controlRepoUrl.isEmpty ? "(not set)" : config.controlRepoUrl)
              .foregroundColor(.primary)
              .lineLimit(1)
              .truncationMode(.middle)
          }
          
          // Local Path
          HStack {
            Text("Local Path:")
              .foregroundColor(.secondary)
            Spacer()
            Text(config.controlRepoPath.isEmpty ? "(not set)" : config.controlRepoPath)
              .foregroundColor(.primary)
              .lineLimit(1)
              .truncationMode(.middle)
          }
          
          Divider()
            .padding(.vertical, 8)

          // Preferences
          VStack(alignment: .leading, spacing: 12) {
            Text("Interface")
              .font(.headline)

            Toggle("Show menu bar widget", isOn: Binding(
              get: { vm.menuBarWidgetEnabled },
              set: { vm.menuBarWidgetEnabled = $0 }
            ))
            .toggleStyle(.switch)
            .help("Shows the current/next task in the macOS menu bar for ambient awareness.")
          }

          Divider()
            .padding(.vertical, 8)

          // Orchestrator
          VStack(alignment: .leading, spacing: 12) {
            Text("Orchestrator")
              .font(.headline)

            OrchestratorControlPanel(compact: false)
              .frame(maxWidth: .infinity)
              .padding(.top, 4)
          }

          Divider()
            .padding(.vertical, 8)

          // Agent Personality
          VStack(alignment: .leading, spacing: 12) {
            Text("Agent")
              .font(.headline)

            Text("Customize the worker persona (SOUL.md, USER.md, IDENTITY.md) stored in your control repo.")
              .font(.caption)
              .foregroundColor(.secondary)

            Button("Edit Agent Personality…") {
              showingPersonalityEditor = true
            }
            .buttonStyle(.bordered)
            .disabled(config.controlRepoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }

          Divider()
            .padding(.vertical, 8)

          // Git Sync
          VStack(alignment: .leading, spacing: 12) {
            Text("Git Sync")
              .font(.headline)

            Text("Manual overrides for when automatic sync fails.")
              .font(.caption)
              .foregroundColor(.secondary)

            HStack(spacing: 12) {
              Button(role: .destructive) {
                showingForcePullConfirm = true
              } label: {
                Text("Force Pull (Discard Local)")
              }
              .buttonStyle(.bordered)
              .disabled(vm.repoURL == nil || vm.isGitBusy)
              .confirmationDialog(
                "Force Pull (Discard Local)",
                isPresented: $showingForcePullConfirm,
                titleVisibility: .visible
              ) {
                Button("Force Pull", role: .destructive) {
                  vm.forcePullDiscardLocal()
                }
                Button("Cancel", role: .cancel) {}
              } message: {
                Text("This will stash local changes as a safety backup, then reset your repo to origin/main and delete untracked files.")
              }

              Button(role: .destructive) {
                showingForcePushConfirm = true
              } label: {
                Text("Force Push (Overwrite Remote)")
              }
              .buttonStyle(.bordered)
              .disabled(vm.repoURL == nil || vm.isGitBusy)
              .confirmationDialog(
                "Force Push (Overwrite Remote)",
                isPresented: $showingForcePushConfirm,
                titleVisibility: .visible
              ) {
                Button("Force Push", role: .destructive) {
                  vm.forcePushOverwriteRemote()
                }
                Button("Cancel", role: .cancel) {}
              } message: {
                Text("This will overwrite remote changes if needed. Are you sure?")
              }
              .confirmationDialog(
                "Force Push Failed — Escalate to --force?",
                isPresented: $vm.forcePushEscalationPresented,
                titleVisibility: .visible
              ) {
                Button("Push --force", role: .destructive) {
                  vm.forcePushOverwriteRemoteForce()
                }
                Button("Cancel", role: .cancel) {}
              } message: {
                Text((vm.forcePushEscalationError ?? "Force push (with lease) failed") + "\n\nThis will overwrite remote history. Proceed only if you are sure.")
              }
            }
          }

          Divider()
            .padding(.vertical, 8)
          
          // Setup & Onboarding
          VStack(alignment: .leading, spacing: 12) {
            Text("Setup & Onboarding")
              .font(.headline)

            Text("Revisit the setup wizard or open guides any time.")
              .font(.caption)
              .foregroundColor(.secondary)

            HStack(spacing: 12) {
              Button("Re-run Onboarding Wizard…") {
                showingRerunOnboardingConfirm = true
              }
              .buttonStyle(.bordered)

              Button("Help & Shortcuts…") {
                showingHelpGuides = true
              }
              .buttonStyle(.bordered)

              Button("Server Setup Guide…") {
                showingServerSetupGuide = true
              }
              .buttonStyle(.bordered)
            }

            Button("View Setup Status…") {
              showingSetupStatus = true
            }
            .buttonStyle(.bordered)
          }

          Divider()
            .padding(.vertical, 8)
          
          // Action Buttons
          VStack(spacing: 12) {
            Button("Change Repository") {
              showingChangeRepoConfirmation = true
            }
            .buttonStyle(.bordered)
            .confirmationDialog(
              "Change Repository",
              isPresented: $showingChangeRepoConfirmation,
              titleVisibility: .visible
            ) {
              Button("Continue", role: .destructive) {
                changeRepository()
              }
              Button("Cancel", role: .cancel) {}
            } message: {
              Text("This will disconnect from your current control repo. Your local data will remain. Continue?")
            }
            
            Button("Reset Everything") {
              showingResetConfirmation = true
            }
            .buttonStyle(.bordered)
            .confirmationDialog(
              "Reset Everything",
              isPresented: $showingResetConfirmation,
              titleVisibility: .visible
            ) {
              Button("Reset", role: .destructive) {
                resetEverything()
              }
              Button("Cancel", role: .cancel) {}
            } message: {
              Text("This will reset all settings and require you to set up again. Continue?")
            }
          }
        } else {
          Text("No configuration found")
            .foregroundColor(.secondary)
        }
      }
      .padding()
      .background(Color(NSColor.controlBackgroundColor))
      .cornerRadius(8)
      
      Spacer()
    }
    .padding(24)
    .frame(width: 600, height: 460)
    .sheet(isPresented: $showingPersonalityEditor) {
      AgentPersonalitySheet()
        .environmentObject(vm)
        .frame(width: 760, height: 560)
    }
    .sheet(isPresented: $showingSetupStatus) {
      SetupStatusView()
        .environmentObject(vm)
    }
    .sheet(isPresented: $showingHelpGuides) {
      HelpPanelSheet(isPresented: $showingHelpGuides)
    }
    .sheet(isPresented: $showingServerSetupGuide) {
      OnboardingServerGuideView()
        .frame(width: 820, height: 720)
    }
    .confirmationDialog(
      "Re-run onboarding?",
      isPresented: $showingRerunOnboardingConfirm,
      titleVisibility: .visible
    ) {
      Button("Re-run Onboarding", role: .destructive) {
        rerunOnboarding()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This will take you back through the setup wizard, without deleting your current configuration.")
    }
  }
  
  private func changeRepository() {
    do {
      // Reset config but keep local data
      try ConfigManager.reset()
      
      // Update AppViewModel to trigger onboarding
      vm.config = nil
      
      // Close settings window - onboarding will appear
      dismiss()
    } catch {
      print("⚠️ Failed to reset config: \(error)")
    }
  }
  
  private func resetEverything() {
    do {
      // Delete configuration
      try ConfigManager.reset()

      // Also reset onboarding resume state.
      OnboardingStateManager.reset()
      
      // Update AppViewModel to trigger onboarding
      vm.config = nil
      
      // Close settings window - onboarding will appear
      dismiss()
    } catch {
      print("⚠️ Failed to reset config: \(error)")
    }
  }

  private func rerunOnboarding() {
    guard var c = vm.config else { return }

    // Reset resumable onboarding progress so the wizard starts from the beginning.
    OnboardingStateManager.reset()

    c.onboardingComplete = false
    vm.config = c

    // Close settings; the main window will swap into onboarding when `needsOnboarding` becomes true.
    dismiss()
  }
}

private struct AgentPersonalitySheet: View {
  @EnvironmentObject var vm: AppViewModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    OnboardingPersonalityView(
      onBack: nil,
      onContinue: { dismiss() },
      continueTitle: "Save",
      showBackButton: false
    )
    .environmentObject(vm)
  }
}

#Preview {
  SettingsView()
    .environmentObject(AppViewModel())
}
