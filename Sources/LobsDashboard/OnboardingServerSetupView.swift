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
    
    // Prerequisite checks
    private let commandTimeoutSeconds: Double = 5
    @State private var isChecking: Bool = false
    @State private var showPrereqs: Bool = true
    
    @State private var nodeOK: Bool = false
    @State private var pythonOK: Bool = false
    @State private var nodeDetail: String = ""
    @State private var pythonDetail: String = ""
    @State private var nodeError: String? = nil
    @State private var pythonError: String? = nil
    @State private var nodeExpanded: Bool = false
    @State private var pythonExpanded: Bool = false
    
    private var prereqsOK: Bool { nodeOK && pythonOK }
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 12) {
                // Title
                Text("Server Setup")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.primary)
                
                // Subtitle
                Text("Optional: Set up the Lobs orchestrator on your server")
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
            
            if showPrereqs {
                // Prerequisites section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Server Prerequisites")
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()
                        Button(action: { Task { await refreshPrereqs() } }) {
                            Text(isChecking ? "Checking…" : "Refresh")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Theme.accent)
                        }
                        .buttonStyle(.plain)
                        .disabled(isChecking)
                    }
                    
                    prereqDisclosure(
                        title: "Node.js 18+",
                        ok: nodeOK,
                        detail: nodeDetail,
                        error: nodeError,
                        expanded: $nodeExpanded,
                        help: { nodeHelp }
                    )
                    
                    prereqDisclosure(
                        title: "Python 3.10+",
                        ok: pythonOK,
                        detail: pythonDetail,
                        error: pythonError,
                        expanded: $pythonExpanded,
                        help: { pythonHelp }
                    )
                }
                .frame(width: 600)
                .padding(20)
                .background(Theme.cardBg)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1)
                )
            }
            
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
                    title: "Clone the orchestrator + install dependencies:",
                    command: "git clone https://github.com/RafeSymonds/lobs-orchestrator.git ~/lobs-orchestrator\ncd ~/lobs-orchestrator && python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt",
                    isCopied: copiedIndex == 3,
                    onCopy: {
                        copyToClipboard("git clone https://github.com/RafeSymonds/lobs-orchestrator.git ~/lobs-orchestrator\ncd ~/lobs-orchestrator && python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt")
                        copiedIndex = 3
                        resetCopyState(for: 3)
                    }
                )

                // Step 4
                StepBlock(
                    number: 4,
                    title: "Configure orchestrator to use your control repo:",
                    command: "cd ~/lobs-orchestrator\necho 'LOBS_CONTROL_REPO_PATH=~/lobs-control' > .env",
                    isCopied: copiedIndex == 4,
                    onCopy: {
                        copyToClipboard("cd ~/lobs-orchestrator\necho 'LOBS_CONTROL_REPO_PATH=~/lobs-control' > .env")
                        copiedIndex = 4
                        resetCopyState(for: 4)
                    }
                )

                // Step 5
                StepBlock(
                    number: 5,
                    title: "Start the orchestrator (test run):",
                    command: "cd ~/lobs-orchestrator && source .venv/bin/activate && python3 main.py",
                    isCopied: copiedIndex == 5,
                    onCopy: {
                        copyToClipboard("cd ~/lobs-orchestrator && source .venv/bin/activate && python3 main.py")
                        copiedIndex = 5
                        resetCopyState(for: 5)
                    }
                )

                // Step 6
                StepBlock(
                    number: 6,
                    title: "Set up as a systemd service (optional, Linux):",
                    command: "# See orchestrator README for systemd setup\n# https://github.com/RafeSymonds/lobs-orchestrator",
                    isCopied: copiedIndex == 6,
                    onCopy: {
                        copyToClipboard("# See orchestrator README for systemd setup\n# https://github.com/RafeSymonds/lobs-orchestrator")
                        copiedIndex = 6
                        resetCopyState(for: 6)
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
        .onAppear {
            Task { await refreshPrereqs() }
        }
    }
    
    /// Copy text to clipboard
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    // MARK: - Prerequisite checks
    
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
                    
                    Text(detail.isEmpty ? (ok ? "OK" : "Not installed") : detail)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if !ok {
                    Button(action: { expanded.wrappedValue.toggle() }) {
                        Text(expanded.wrappedValue ? "Hide" : "Install")
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
    
    private var nodeHelp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Install Node.js (18 or newer)")
                .font(.system(size: 12, weight: .semibold))
            
            Text("OpenClaw requires Node.js 18 or newer.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                Link("nodejs.org", destination: URL(string: "https://nodejs.org/")!)
                    .font(.system(size: 12))
                Link("nvm", destination: URL(string: "https://github.com/nvm-sh/nvm")!)
                    .font(.system(size: 12))
            }
            
            Text("node --version")
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .background(Theme.bg.opacity(0.35))
                .cornerRadius(8)
        }
    }
    
    private var pythonHelp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Install Python 3.10+")
                .font(.system(size: 12, weight: .semibold))
            
            Text("The orchestrator requires Python 3.10 or newer.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                Link("python.org", destination: URL(string: "https://www.python.org/downloads/")!)
                    .font(.system(size: 12))
                Link("Homebrew", destination: URL(string: "https://brew.sh")!)
                    .font(.system(size: 12))
            }
            
            Text("python3 --version")
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .background(Theme.bg.opacity(0.35))
                .cornerRadius(8)
        }
    }
    
    private func refreshPrereqs() async {
        await MainActor.run {
            isChecking = true
            nodeError = nil
            pythonError = nil
            nodeDetail = "Checking…"
            pythonDetail = "Checking…"
        }
        
        // Node check
        do {
            let nodePath = await Shell.which("node")
            if nodePath == nil {
                await MainActor.run {
                    nodeOK = false
                    nodeDetail = "Not found in PATH"
                    nodeExpanded = true
                }
            } else {
                let res = await Shell.envAsync("node", ["--version"], timeoutSeconds: commandTimeoutSeconds)
                let ver = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                let ok = res.ok && nodeVersionAtLeast18(ver)
                await MainActor.run {
                    nodeOK = ok
                    nodeDetail = res.ok ? "Detected \(ver.isEmpty ? "(unknown)" : ver)" : "Node command failed"
                    nodeError = (res.ok && ok) ? nil : (!res.ok ? cleanError(res) : "Node must be version 18 or newer")
                    nodeExpanded = !ok
                }
            }
        }
        
        // Python check
        do {
            let pyPath = await Shell.which("python3")
            if pyPath == nil {
                await MainActor.run {
                    pythonOK = false
                    pythonDetail = "Not found in PATH"
                    pythonExpanded = true
                }
            } else {
                let res = await Shell.envAsync("python3", ["--version"], timeoutSeconds: commandTimeoutSeconds)
                let ver = (res.stdout.isEmpty ? res.stderr : res.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
                let ok = res.ok && pythonVersionAtLeast3_10(ver)
                await MainActor.run {
                    pythonOK = ok
                    pythonDetail = res.ok ? "Detected \(ver.isEmpty ? "(unknown)" : ver)" : "python3 command failed"
                    pythonError = (res.ok && ok) ? nil : (!res.ok ? cleanError(res) : "Python must be version 3.10 or newer")
                    pythonExpanded = !ok
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
    
    private func nodeVersionAtLeast18(_ v: String) -> Bool {
        // v like "v20.11.0" or "20.11.0"
        let cleaned = v.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        let parts = cleaned.split(separator: ".")
        guard let majorStr = parts.first, let major = Int(majorStr) else { return false }
        return major >= 18
    }
    
    private func pythonVersionAtLeast3_10(_ v: String) -> Bool {
        // "Python 3.11.7" or "3.11.7"
        let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.hasPrefix("Python ") ? String(trimmed.dropFirst("Python ".count)) : trimmed
        let parts = cleaned.split(separator: ".")
        guard parts.count >= 2,
              let major = Int(parts[0]),
              let minor = Int(parts[1]) else { return false }
        if major > 3 { return true }
        if major < 3 { return false }
        return minor >= 10
    }
    
    /// Copy all commands to clipboard
    private func copyAllCommands() {
        let allCommands = """
        npm install -g openclaw@latest
        openclaw onboard --install-daemon
        git clone https://github.com/RafeSymonds/lobs-orchestrator.git ~/lobs-orchestrator
        cd ~/lobs-orchestrator && python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt
        cd ~/lobs-orchestrator
        echo 'LOBS_CONTROL_REPO_PATH=~/lobs-control' > .env
        cd ~/lobs-orchestrator && source .venv/bin/activate && python3 main.py
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
