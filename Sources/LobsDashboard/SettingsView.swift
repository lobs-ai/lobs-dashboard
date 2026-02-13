import SwiftUI

struct SettingsView: View {
  @EnvironmentObject var vm: AppViewModel
  @Environment(\.dismiss) private var dismiss
  
  @State private var showingResetConfirmation = false
  @State private var showingPersonalityEditor = false
  @State private var showingSetupStatus = false
  @State private var showingHelpGuides = false
  @State private var showingServerSetupGuide = false
  @State private var showingRerunOnboardingConfirm = false

  @State private var serverURL: String = ""
  @State private var connectionTestStatus: ConnectionTestStatus = .idle
  
  enum ConnectionTestStatus {
    case idle
    case testing
    case success(String)
    case failure(String)
  }
  
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
          // Server URL
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("Server URL:")
                .foregroundColor(.secondary)
              Spacer()
            }
            
            HStack(spacing: 8) {
              TextField("http://localhost:8000", text: $serverURL)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                  RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .onSubmit {
                  saveServerURL()
                }
              
              Button(action: testConnection) {
                HStack(spacing: 4) {
                  if case .testing = connectionTestStatus {
                    ProgressView()
                      .scaleEffect(0.6)
                      .frame(width: 12, height: 12)
                  } else {
                    Image(systemName: connectionIcon)
                      .font(.system(size: 11))
                  }
                  Text(connectionButtonText)
                    .font(.system(size: 12))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
              }
              .buttonStyle(.bordered)
              .disabled({
                if case .testing = connectionTestStatus { return true }
                return false
              }())
            }
            
            // Connection status message
            if case .success(let message) = connectionTestStatus {
              HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundColor(.green)
                  .font(.system(size: 11))
                Text(message)
                  .font(.system(size: 11))
                  .foregroundColor(.secondary)
              }
            } else if case .failure(let error) = connectionTestStatus {
              HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                  .foregroundColor(.red)
                  .font(.system(size: 11))
                Text(error)
                  .font(.system(size: 11))
                  .foregroundColor(.red)
              }
            }
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

          // Agent Personality
          VStack(alignment: .leading, spacing: 12) {
            Text("Agent")
              .font(.headline)

            Text("Customize the worker persona (SOUL.md, USER.md, IDENTITY.md) via the server API.")
              .font(.caption)
              .foregroundColor(.secondary)

            Button("Edit Agent Personality…") {
              showingPersonalityEditor = true
            }
            .buttonStyle(.bordered)
            .disabled(vm.repoURL == nil)
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
    .onAppear {
      if let config = vm.config {
        serverURL = config.serverURL
      }
    }
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
    
    // Persist the config change so it survives app restart.
    // Without this, if the user quits before completing onboarding,
    // the next app launch will still have onboardingComplete=true.
    do {
      try ConfigManager.save(c)
    } catch {
      print("⚠️ Failed to save config during rerunOnboarding: \(error)")
    }

    // Close settings; the main window will swap into onboarding when `needsOnboarding` becomes true.
    dismiss()
  }
  
  private var connectionIcon: String {
    switch connectionTestStatus {
    case .idle:
      return "network"
    case .testing:
      return "network"
    case .success:
      return "checkmark.circle.fill"
    case .failure:
      return "xmark.circle.fill"
    }
  }
  
  private var connectionButtonText: String {
    switch connectionTestStatus {
    case .idle:
      return "Test Connection"
    case .testing:
      return "Testing..."
    case .success:
      return "Connected"
    case .failure:
      return "Failed"
    }
  }
  
  private func saveServerURL() {
    guard var config = vm.config else { return }
    config.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
    vm.config = config
    do {
      try ConfigManager.save(config)
    } catch {
      print("⚠️ Failed to save server URL: \(error)")
    }
  }
  
  private func testConnection() {
    connectionTestStatus = .testing
    
    Task {
      do {
        let urlString = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlString) else {
          await MainActor.run {
            connectionTestStatus = .failure("Invalid URL")
          }
          return
        }
        
        let healthURL = url.appendingPathComponent("/api/health")
        let (data, response) = try await URLSession.shared.data(from: healthURL)
        
        guard let httpResponse = response as? HTTPURLResponse else {
          await MainActor.run {
            connectionTestStatus = .failure("Invalid response")
          }
          return
        }
        
        if httpResponse.statusCode == 200 {
          // Try to parse JSON for a status message
          if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
             let status = json["status"] as? String {
            await MainActor.run {
              connectionTestStatus = .success("Server healthy: \(status)")
            }
          } else {
            await MainActor.run {
              connectionTestStatus = .success("Server is online")
            }
          }
          
          // Auto-save on successful connection
          saveServerURL()
        } else {
          await MainActor.run {
            connectionTestStatus = .failure("Server returned \(httpResponse.statusCode)")
          }
        }
      } catch {
        await MainActor.run {
          connectionTestStatus = .failure(error.localizedDescription)
        }
      }
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

// // #Preview {
// SettingsView()
// .environmentObject(AppViewModel())
// }
