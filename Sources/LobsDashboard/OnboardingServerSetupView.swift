import SwiftUI
import AppKit
import Foundation

/// Server setup instructions screen of the onboarding wizard
struct OnboardingServerSetupView: View {
    @EnvironmentObject var vm: AppViewModel
    let repoUrl: String
    let onBack: () -> Void
    let onContinue: () -> Void
    
    @State private var copiedIndex: Int? = nil
    @State private var copiedAll: Bool = false
    @State private var isChecking = false
    @State private var nodeOK = false
    @State private var pythonOK = false
    @State private var nodeDetail = ""
    @State private var pythonDetail = ""
    @State private var nodeError: String? = nil
    @State private var pythonError: String? = nil
    @State private var nodeExpanded = false
    @State private var pythonExpanded = false

    private let commandTimeoutSeconds: TimeInterval = 12
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 12) {
                // Title
                Text("Server Setup")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.primary)
                
                // Subtitle
                Text("Optional: Set up lobs-server on your machine")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                
                // Note about optional setup
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                    Text("You can skip this and set up your server later. The dashboard will work without a server.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 560)
            }
            
            // Server Prerequisites Note
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Server Prerequisites")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.secondary)
                        Text("Node.js 18+ (required for OpenClaw)")
                            .font(.system(size: 14))
                    }
                    
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.secondary)
                        Text("Python 3.10+ (required for lobs-server)")
                            .font(.system(size: 14))
                    }
                }
                .padding(.leading, 8)
                
                Text("Make sure these are installed on your server before running the commands below.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
            .frame(width: 600)
            .padding(20)
            .background(Theme.cardBg)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1)
            )
            
            // Instructions
            VStack(alignment: .leading, spacing: 20) {
                Text("Installation Steps")
                    .font(.system(size: 16, weight: .semibold))
                
                // Step 1
                StepBlock(
                    number: 1,
                    title: "Install OpenClaw (AI worker runtime):",
                    command: "npm install -g openclaw@latest",
                    isCopied: copiedIndex == 1,
                    onCopy: {
                        copyToClipboard("npm install -g openclaw@latest")
                        copiedIndex = 1
                        resetCopyState(for: 1)
                    }
                )

                // Step 2
                StepBlock(
                    number: 2,
                    title: "Run OpenClaw onboarding + install Gateway service:",
                    command: "openclaw onboard --install-daemon",
                    isCopied: copiedIndex == 2,
                    onCopy: {
                        copyToClipboard("openclaw onboard --install-daemon")
                        copiedIndex = 2
                        resetCopyState(for: 2)
                    }
                )

                // Step 3
                StepBlock(
                    number: 3,
                    title: "Clone lobs-server:",
                    command: "git clone <your-lobs-server-repo> ~/lobs-server\ncd ~/lobs-server && python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt",
                    isCopied: copiedIndex == 3,
                    onCopy: {
                        copyToClipboard("git clone <your-lobs-server-repo> ~/lobs-server\ncd ~/lobs-server && python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt")
                        copiedIndex = 3
                        resetCopyState(for: 3)
                    }
                )

                // Step 4
                StepBlock(
                    number: 4,
                    title: "Start lobs-server (test run):",
                    command: "cd ~/lobs-server && source .venv/bin/activate && python3 main.py",
                    isCopied: copiedIndex == 4,
                    onCopy: {
                        copyToClipboard("cd ~/lobs-server && source .venv/bin/activate && python3 main.py")
                        copiedIndex = 4
                        resetCopyState(for: 4)
                    }
                )

                // Step 5
                StepBlock(
                    number: 5,
                    title: "Set up as a systemd service (optional, Linux):",
                    command: "# See lobs-server README for systemd setup",
                    isCopied: copiedIndex == 5,
                    onCopy: {
                        copyToClipboard("# See lobs-server README for systemd setup")
                        copiedIndex = 5
                        resetCopyState(for: 5)
                    }
                )
                
                // Copy All Commands Button
                Button(action: copyAllCommands) {
                    HStack(spacing: 6) {
                        Image(systemName: copiedAll ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12))
                        Text(copiedAll ? "Copied!" : "Copy All Commands")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(copiedAll ? .green : Theme.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .background(copiedAll ? Color.green.opacity(0.1) : Theme.accent.opacity(0.1))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(copiedAll ? Color.green.opacity(0.3) : Theme.accent.opacity(0.3), lineWidth: 1)
                )
                
                // Helper text
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                    Text("Make sure Node.js and Python are installed on your server first (see prerequisites above). The OpenClaw onboarding wizard will configure API keys and services.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
            }
            .frame(width: 560)
            
            Spacer()
            
            // Navigation buttons
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
                
                Button(action: onContinue) {
                    Text("Continue")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 120)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .background(Theme.accent)
                .cornerRadius(8)
            }
            .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
    
    /// Copy text to clipboard
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    /// Copy all commands to clipboard
    private func copyAllCommands() {
        let allCommands = """
        npm install -g openclaw@latest
        openclaw onboard --install-daemon
        git clone <your-lobs-server-repo> ~/lobs-server
        cd ~/lobs-server && python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt
        cd ~/lobs-server && source .venv/bin/activate && python3 main.py
        """
        
        copyToClipboard(allCommands)
        copiedAll = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            copiedAll = false
        }
    }
    
    /// Reset copy state after delay
    private func resetCopyState(for index: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if copiedIndex == index {
                copiedIndex = nil
            }
        }
    }
}

/// Individual step block with command and copy button
struct StepBlock: View {
    let number: Int
    let title: String
    let command: String
    let isCopied: Bool
    let onCopy: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Step title
            HStack(spacing: 8) {
                Text("\(number).")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.accent)
                
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
            }
            
            // Code block
            HStack(alignment: .top, spacing: 0) {
                Text(command)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Copy button
                Button(action: onCopy) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(isCopied ? .green : .secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .padding(12)
                .help("Copy to clipboard")
            }
            .background(Theme.cardBg)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.border, lineWidth: 1)
            )
        }
    }
}

#Preview {
    OnboardingServerSetupView(
        repoUrl: "git@github.com:user/lobs-control.git",
        onBack: {},
        onContinue: {}
    )
    .environmentObject(AppViewModel())
    .frame(width: 800, height: 600)
}
