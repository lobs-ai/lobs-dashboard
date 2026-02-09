import SwiftUI
import AppKit

/// Server setup instructions screen of the onboarding wizard
struct OnboardingServerSetupView: View {
    @EnvironmentObject var vm: AppViewModel
    let repoUrl: String
    let onBack: () -> Void
    let onContinue: () -> Void
    
    @State private var copiedIndex: Int? = nil
    @State private var copiedAll: Bool = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 12) {
                // Title
                Text("Server Setup")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.primary)
                
                // Subtitle
                Text("Run these commands on your server to connect your AI assistant:")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
            
            // Instructions
            VStack(alignment: .leading, spacing: 20) {
                // Step 1
                StepBlock(
                    number: 1,
                    title: "Clone your control repo:",
                    command: "git clone \(repoUrl) ~/lobs-control",
                    isCopied: copiedIndex == 1,
                    onCopy: {
                        copyToClipboard("git clone \(repoUrl) ~/lobs-control")
                        copiedIndex = 1
                        resetCopyState(for: 1)
                    }
                )
                
                // Step 2
                StepBlock(
                    number: 2,
                    title: "Clone the orchestrator:",
                    command: "git clone https://github.com/RafeSymonds/lobs-orchestrator.git ~/lobs-orchestrator\ncd ~/lobs-orchestrator && pip install -r requirements.txt",
                    isCopied: copiedIndex == 2,
                    onCopy: {
                        copyToClipboard("git clone https://github.com/RafeSymonds/lobs-orchestrator.git ~/lobs-orchestrator\ncd ~/lobs-orchestrator && pip install -r requirements.txt")
                        copiedIndex = 2
                        resetCopyState(for: 2)
                    }
                )
                
                // Step 3
                StepBlock(
                    number: 3,
                    title: "Start the orchestrator:",
                    command: "cd ~/lobs-orchestrator && python3 main.py",
                    isCopied: copiedIndex == 3,
                    onCopy: {
                        copyToClipboard("cd ~/lobs-orchestrator && python3 main.py")
                        copiedIndex = 3
                        resetCopyState(for: 3)
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
                    Text("Make sure OpenClaw is configured on your server before starting the orchestrator.")
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
                    Text("Verify Setup")
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
        git clone \(repoUrl) ~/lobs-control
        git clone https://github.com/RafeSymonds/lobs-orchestrator.git ~/lobs-orchestrator
        cd ~/lobs-orchestrator && pip install -r requirements.txt
        cd ~/lobs-orchestrator && python3 main.py
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
