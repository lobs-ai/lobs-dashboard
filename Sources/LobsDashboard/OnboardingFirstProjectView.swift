import SwiftUI

/// Optional step: clone a first project repo into the workspace.
///
/// This is intentionally lightweight — it just clones into:
///   <workspace>/projects/<repo>
/// so users can start creating tasks against a real codebase.
struct OnboardingFirstProjectView: View {
  let workspacePath: String
  let onBack: () -> Void
  let onSkip: () -> Void
  let onComplete: () -> Void

  @State private var repoURL: String = ""
  @State private var isCloning: Bool = false
  @State private var log: String = ""
  @State private var error: String? = nil
  @State private var didClone: Bool = false

  private var projectsDir: URL {
    URL(fileURLWithPath: workspacePath).appendingPathComponent("projects")
  }

  var body: some View {
    VStack(spacing: 24) {
      Spacer()

      VStack(spacing: 10) {
        Text("First Project (Optional)")
          .font(.system(size: 28, weight: .semibold))
        Text("If you have a repo you want Lobs to help with, paste its GitHub URL. We’ll clone it into your workspace.")
          .font(.system(size: 14))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 640)
      }

      VStack(alignment: .leading, spacing: 12) {
        Text("GitHub URL")
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(.secondary)

        TextField("https://github.com/owner/repo (or git@github.com:owner/repo.git)", text: $repoURL)
          .textFieldStyle(.plain)
          .font(.system(size: 14, design: .monospaced))
          .padding(10)
          .background(Theme.cardBg)
          .cornerRadius(8)
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))

        Text("We’ll use \"gh repo clone\" if available, otherwise \"git clone\".")
          .font(.system(size: 12))
          .foregroundColor(.secondary)

        if let error {
          Text(error)
            .font(.system(size: 13))
            .foregroundColor(.red)
        }

        if didClone {
          HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            Text("Cloned into: \(projectsDir.path)")
              .font(.system(size: 13))
          }
        }

        if !log.isEmpty {
          ScrollView {
            Text(log)
              .font(.system(size: 11, design: .monospaced))
              .foregroundColor(.secondary)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(height: 220)
          .padding(12)
          .background(Theme.cardBg)
          .cornerRadius(8)
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
        }
      }
      .frame(width: 680)

      Spacer()

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
        .disabled(isCloning)

        Button(action: onSkip) {
          Text("Skip")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.primary)
            .frame(width: 120)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(Theme.cardBg)
        .cornerRadius(8)
        .disabled(isCloning)

        Button(action: { Task { await clone() } }) {
          Text(isCloning ? "Cloning…" : "Clone")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 120)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(Theme.accent)
        .cornerRadius(8)
        .disabled(isCloning || repoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(repoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)

        Button(action: onComplete) {
          Text("Next")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 120)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(Theme.accent)
        .cornerRadius(8)
        .disabled(!didClone)
        .opacity(didClone ? 1.0 : 0.5)
      }
      .padding(.bottom, 60)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.bg)
    .onAppear {
      // Ensure projects directory exists.
      do {
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
      } catch {
        self.error = "Failed to create projects directory: \(error.localizedDescription)"
      }
    }
  }

  private func clone() async {
    await MainActor.run {
      isCloning = true
      error = nil
      log = ""
      didClone = false
    }

    do {
      try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
    } catch {
      await MainActor.run {
        isCloning = false
        error = "Failed to create projects directory: \(error.localizedDescription)"
      }
      return
    }

    let url = repoURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let dest = projectsDir.appendingPathComponent(repoName(from: url))

    if FileManager.default.fileExists(atPath: dest.path) {
      await MainActor.run {
        isCloning = false
        didClone = true
        log = "Folder already exists, using current checkout: \(dest.path)"
      }
      return
    }

    // Prefer gh when available because it works nicely with private repos.
    let gh = await Shell.which("gh")
    let res: Shell.Result
    if gh != nil {
      res = await Shell.envAsync("gh", ["repo", "clone", url, dest.path])
    } else {
      res = await Shell.envAsync("git", ["clone", url, dest.path])
    }

    await MainActor.run {
      isCloning = false
      log = (res.stdout + "\n" + res.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
      if res.ok {
        didClone = true
      } else {
        error = "Clone failed. Make sure you have access to the repo and try again."
      }
    }
  }

  private func repoName(from url: String) -> String {
    // Handles:
    // - https://github.com/owner/repo
    // - https://github.com/owner/repo.git
    // - git@github.com:owner/repo.git
    // - owner/repo (gh accepts this)
    var s = url.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasSuffix(".git") { s = String(s.dropLast(4)) }

    // Strip trailing slash.
    while s.hasSuffix("/") { s = String(s.dropLast()) }

    // Take last path-ish segment.
    if let lastSlash = s.lastIndex(of: "/") {
      return String(s[s.index(after: lastSlash)...])
    }
    if let lastColon = s.lastIndex(of: ":") {
      return String(s[s.index(after: lastColon)...])
    }
    if let last = s.split(separator: "/").last {
      return String(last)
    }
    return "project"
  }
}

#Preview {
  OnboardingFirstProjectView(
    workspacePath: NSHomeDirectory() + "/lobs",
    onBack: {},
    onSkip: {},
    onComplete: {}
  )
  .frame(width: 900, height: 650)
}
