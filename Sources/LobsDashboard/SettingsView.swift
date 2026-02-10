import SwiftUI

struct SettingsView: View {
  @EnvironmentObject var vm: AppViewModel
  @Environment(\.dismiss) private var dismiss
  
  @State private var showingChangeRepoConfirmation = false
  @State private var showingResetConfirmation = false
  @State private var showingPersonalityEditor = false
  
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
      
      // Update AppViewModel to trigger onboarding
      vm.config = nil
      
      // Close settings window - onboarding will appear
      dismiss()
    } catch {
      print("⚠️ Failed to reset config: \(error)")
    }
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
