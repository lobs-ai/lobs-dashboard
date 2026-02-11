import SwiftUI

/// High-level guide for setting up the server-side components.
/// This is informational only — the actual setup happens on your server.
struct OnboardingServerGuideView: View {
  var body: some View {
    ScrollView {
      VStack(spacing: 28) {
        VStack(spacing: 10) {
          Image(systemName: "server.rack")
            .font(.system(size: 40))
            .foregroundColor(.secondary)
          Text("Server Setup")
            .font(.system(size: 28, weight: .semibold))
          Text("The dashboard is just the frontend. The AI agent runs on a server.")
            .font(.system(size: 14))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 560)
        }
        .padding(.top, 40)

        VStack(alignment: .leading, spacing: 20) {
          // Architecture overview
          VStack(alignment: .leading, spacing: 8) {
            Label("How it works", systemImage: "arrow.triangle.2.circlepath")
              .font(.system(size: 15, weight: .semibold))

            Text("""
              • **Dashboard** (this app) — runs on your Mac, shows tasks and state
              • **Control repo** — shared Git repository with tasks, projects, and state
              • **OpenClaw** — the AI runtime that executes tasks (runs on server)
              • **Orchestrator** — monitors the control repo and spawns workers (runs on server)
              """)
              .font(.system(size: 13))
              .foregroundColor(.secondary)
              .textSelection(.enabled)
          }
          .padding(16)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Theme.cardBg)
          .cornerRadius(12)

          // Server requirements
          VStack(alignment: .leading, spacing: 8) {
            Label("Server requirements", systemImage: "desktopcomputer")
              .font(.system(size: 15, weight: .semibold))

            Text("""
              • Linux server, Mac mini, or similar always-on machine
              • Node.js 18+ (for OpenClaw)
              • Python 3.10+ (for orchestrator)
              • Git access to your control repo
              """)
              .font(.system(size: 13))
              .foregroundColor(.secondary)
              .textSelection(.enabled)
          }
          .padding(16)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Theme.cardBg)
          .cornerRadius(12)

          // Setup steps
          VStack(alignment: .leading, spacing: 8) {
            Label("Setup steps (on your server)", systemImage: "list.number")
              .font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 12) {
              setupStep(number: 1, title: "Install OpenClaw", command: "npm install -g openclaw")
              setupStep(number: 2, title: "Configure OpenClaw", command: "openclaw config set auth.anthropicApiKey <key>")
              setupStep(number: 3, title: "Clone repos", command: "git clone <your-control-repo>")
              setupStep(number: 4, title: "Clone orchestrator", command: "git clone https://github.com/RafeSymonds/lobs-orchestrator")
              setupStep(number: 5, title: "Start orchestrator", command: "cd lobs-orchestrator && python3 main.py")
            }
          }
          .padding(16)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Theme.cardBg)
          .cornerRadius(12)

          // Links
          VStack(alignment: .leading, spacing: 8) {
            Label("Resources", systemImage: "link")
              .font(.system(size: 15, weight: .semibold))

            HStack(spacing: 16) {
              Link("OpenClaw Docs", destination: URL(string: "https://docs.openclaw.ai")!)
                .font(.system(size: 13))
              Link("Orchestrator Repo", destination: URL(string: "https://github.com/RafeSymonds/lobs-orchestrator")!)
                .font(.system(size: 13))
            }
          }
          .padding(16)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Theme.cardBg)
          .cornerRadius(12)
        }
        .frame(width: 560)

        Text("You can set this up later. Click Next to continue.")
          .font(.system(size: 13))
          .foregroundColor(.secondary)
          .padding(.bottom, 40)
      }
      .frame(maxWidth: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.bg)
  }

  private func setupStep(number: Int, title: String, command: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text("\(number)")
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundColor(.white)
        .frame(width: 22, height: 22)
        .background(Theme.accent)
        .clipShape(Circle())

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 13, weight: .medium))
        Text(command)
          .font(.system(size: 12, design: .monospaced))
          .foregroundColor(.secondary)
          .textSelection(.enabled)
      }
    }
  }
}

#Preview {
  OnboardingServerGuideView()
    .frame(width: 800, height: 700)
}
