import SwiftUI

/// Detailed setup status view showing what's configured and what needs attention.
/// Allows users to fix individual setup issues without restarting the entire wizard.
struct SetupStatusView: View {
  @EnvironmentObject var vm: AppViewModel
  @EnvironmentObject var orchestrator: OrchestratorManager
  @Environment(\.dismiss) private var dismiss
  
  @State private var showingRestartWizardConfirmation = false
  @State private var showingPersonalityEditor = false
  @State private var onboardingState: OnboardingState = OnboardingStateManager.load()
  
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        // Header
        VStack(alignment: .leading, spacing: 8) {
          Text("Setup Status")
            .font(.title)
            .fontWeight(.bold)
          
          Text("Review your configuration and fix any issues.")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        
        Divider()
        
        // Configuration Status
        VStack(alignment: .leading, spacing: 16) {
          Text("Configuration")
            .font(.headline)
          
          VStack(spacing: 12) {
            statusRow(
              title: "Workspace",
              status: workspaceStatus,
              action: workspaceStatus.needsAction ? { restartWizard() } : nil,
              actionLabel: "Configure"
            )
            
            statusRow(
              title: "Control Repository",
              status: controlRepoStatus,
              action: controlRepoStatus.needsAction ? { restartWizard() } : nil,
              actionLabel: "Configure"
            )
            
            statusRow(
              title: "Orchestrator Repository",
              status: orchestratorRepoStatus,
              action: orchestratorRepoStatus.needsAction ? { restartWizard() } : nil,
              actionLabel: "Clone/Fix"
            )
            
            statusRow(
              title: "Workspace Repository",
              status: workspaceRepoStatus,
              action: workspaceRepoStatus.needsAction ? { restartWizard() } : nil,
              actionLabel: "Clone/Fix"
            )
            
            statusRow(
              title: "OpenClaw",
              status: openClawStatus,
              action: openClawStatus.needsAction ? { restartWizard() } : nil,
              actionLabel: "Configure"
            )
          }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        
        // Agent & Orchestrator
        VStack(alignment: .leading, spacing: 16) {
          Text("Services")
            .font(.headline)
          
          VStack(spacing: 12) {
            statusRow(
              title: "Agent Personality",
              status: agentPersonalityStatus,
              action: { showingPersonalityEditor = true },
              actionLabel: "Edit"
            )
            
            statusRow(
              title: "Orchestrator",
              status: orchestratorStatus,
              action: orchestratorStatus.needsAction ? { startOrchestrator() } : nil,
              actionLabel: "Start"
            )
          }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        
        // Actions
        VStack(alignment: .leading, spacing: 16) {
          Text("Actions")
            .font(.headline)
          
          VStack(spacing: 12) {
            Button("Restart Full Setup Wizard") {
              showingRestartWizardConfirmation = true
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)
            .confirmationDialog(
              "Restart Setup Wizard",
              isPresented: $showingRestartWizardConfirmation,
              titleVisibility: .visible
            ) {
              Button("Restart", role: .none) {
                restartWizard()
              }
              Button("Cancel", role: .cancel) {}
            } message: {
              Text("This will restart the full setup wizard. Your existing configuration will be preserved, but you can review and update any settings.")
            }
          }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
      }
      .padding(24)
    }
    .frame(minWidth: 600, minHeight: 500)
    .sheet(isPresented: $showingPersonalityEditor) {
      AgentPersonalitySheet()
        .environmentObject(vm)
        .frame(width: 760, height: 560)
    }
    .onAppear {
      refreshOnboardingState()
    }
  }
  
  // MARK: - Status Checks
  
  private struct StatusInfo {
    let isConfigured: Bool
    let message: String
    let needsAction: Bool
    
    var icon: String {
      isConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }
    
    var color: Color {
      isConfigured ? .green : .orange
    }
  }
  
  private var workspaceStatus: StatusInfo {
    guard let config = vm.config else {
      return StatusInfo(isConfigured: false, message: "Not configured", needsAction: true)
    }
    
    let workspacePath = AppViewModel.detectWorkspacePath(controlRepoPath: config.controlRepoPath)
    let exists = AppViewModel.directoryExists(atPath: workspacePath)
    
    if exists {
      return StatusInfo(isConfigured: true, message: workspacePath, needsAction: false)
    } else {
      return StatusInfo(isConfigured: false, message: "Directory not found", needsAction: true)
    }
  }
  
  private var controlRepoStatus: StatusInfo {
    guard let config = vm.config else {
      return StatusInfo(isConfigured: false, message: "Not configured", needsAction: true)
    }
    
    let path = config.controlRepoPath.trimmingCharacters(in: .whitespacesAndNewlines)
    if path.isEmpty {
      return StatusInfo(isConfigured: false, message: "Not set", needsAction: true)
    }
    
    if AppViewModel.isGitRepo(atPath: path) {
      return StatusInfo(isConfigured: true, message: path, needsAction: false)
    } else {
      return StatusInfo(isConfigured: false, message: "Not a valid git repository", needsAction: true)
    }
  }
  
  private var orchestratorRepoStatus: StatusInfo {
    guard let config = vm.config else {
      return StatusInfo(isConfigured: false, message: "Workspace not configured", needsAction: true)
    }
    
    let workspacePath = AppViewModel.detectWorkspacePath(controlRepoPath: config.controlRepoPath)
    let orchestratorPath = (workspacePath as NSString).appendingPathComponent("lobs-orchestrator")
    
    if AppViewModel.isGitRepo(atPath: orchestratorPath) {
      return StatusInfo(isConfigured: true, message: "Cloned", needsAction: false)
    } else {
      return StatusInfo(isConfigured: false, message: "Not cloned", needsAction: true)
    }
  }
  
  private var workspaceRepoStatus: StatusInfo {
    guard let config = vm.config else {
      return StatusInfo(isConfigured: false, message: "Workspace not configured", needsAction: true)
    }
    
    let workspacePath = AppViewModel.detectWorkspacePath(controlRepoPath: config.controlRepoPath)
    let lobsWorkspacePath = (workspacePath as NSString).appendingPathComponent("lobs-workspace")
    
    if AppViewModel.isGitRepo(atPath: lobsWorkspacePath) {
      return StatusInfo(isConfigured: true, message: "Cloned", needsAction: false)
    } else {
      return StatusInfo(isConfigured: false, message: "Not cloned", needsAction: true)
    }
  }
  
  private var openClawStatus: StatusInfo {
    if AppViewModel.isOpenClawConfigured() {
      return StatusInfo(isConfigured: true, message: "Configured", needsAction: false)
    } else {
      return StatusInfo(isConfigured: false, message: "Not configured", needsAction: true)
    }
  }
  
  private var agentPersonalityStatus: StatusInfo {
    let isConfigured = onboardingState.isCompleted(.agentSetup) && 
                       onboardingState.agentName != nil &&
                       onboardingState.userName != nil
    
    if isConfigured {
      let name = onboardingState.agentName ?? "Lobs"
      return StatusInfo(isConfigured: true, message: "Configured (\(name))", needsAction: false)
    } else {
      return StatusInfo(isConfigured: false, message: "Not customized", needsAction: false)
    }
  }
  
  private var orchestratorStatus: StatusInfo {
    if orchestrator.status.isRunning {
      return StatusInfo(isConfigured: true, message: "Running", needsAction: false)
    } else {
      return StatusInfo(isConfigured: false, message: "Not running", needsAction: true)
    }
  }
  
  // MARK: - Status Row
  
  private func statusRow(
    title: String,
    status: StatusInfo,
    action: (() -> Void)?,
    actionLabel: String
  ) -> some View {
    HStack(spacing: 12) {
      Image(systemName: status.icon)
        .foregroundColor(status.color)
        .font(.system(size: 16))
        .frame(width: 20)
      
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 13, weight: .medium))
        
        Text(status.message)
          .font(.system(size: 12))
          .foregroundColor(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      
      Spacer()
      
      if let action = action {
        Button(action: action) {
          Text(actionLabel)
            .font(.system(size: 12))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
    }
    .padding(.vertical, 6)
  }
  
  // MARK: - Actions
  
  private func refreshOnboardingState() {
    onboardingState = OnboardingStateManager.load()
  }
  
  private func restartWizard() {
    do {
      if var config = vm.config {
        config.onboardingComplete = false
        try ConfigManager.save(config)
        vm.config = config
      }
      
      // Don't reset state - keep completed steps so users can skip them
      
      dismiss()
    } catch {
      print("⚠️ Failed to restart onboarding: \(error)")
    }
  }
  
  private func startOrchestrator() {
    Task {
      await orchestrator.start()
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
  SetupStatusView()
    .environmentObject(AppViewModel())
    .environmentObject(OrchestratorManager())
}
