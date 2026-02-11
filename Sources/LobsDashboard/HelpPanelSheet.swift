import SwiftUI

/// Help & shortcuts sheet.
///
/// This was originally embedded in `ContentView.swift`, but is now reusable so it can
/// be opened from Settings as well.
struct HelpPanelSheet: View {
  @Binding var isPresented: Bool

  private struct ShortcutRow: View {
    let keys: String
    let description: String

    var body: some View {
      HStack {
        Text(keys)
          .font(.system(size: 13, design: .monospaced))
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(Color.primary.opacity(0.08))
          .clipShape(RoundedRectangle(cornerRadius: 5))
        Spacer()
        Text(description)
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
      }
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header
      HStack {
        Image(systemName: "questionmark.circle.fill")
          .font(.title2)
          .foregroundStyle(.blue)
        Text("Help & Shortcuts")
          .font(.title2)
          .fontWeight(.bold)
        Spacer()
        Button { withAnimation(.easeInOut(duration: 0.25)) { isPresented = false } } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.title3)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }
      .padding(20)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          // Keyboard Shortcuts
          VStack(alignment: .leading, spacing: 12) {
            Label("Keyboard Shortcuts", systemImage: "keyboard")
              .font(.headline)

            VStack(spacing: 8) {
              ShortcutRow(keys: "⌘ K", description: "Global fuzzy-finder")
              ShortcutRow(keys: "⌘ N", description: "Create new task")
              ShortcutRow(keys: "⌘ R", description: "Refresh / sync with git")
              ShortcutRow(keys: "⌘ W", description: "Request worker")
              ShortcutRow(keys: "⌘ /", description: "Show this help panel")
              ShortcutRow(keys: "↑ ↓", description: "Navigate between tasks")
              ShortcutRow(keys: "Esc", description: "Close overlays / deselect")
            }
          }

          Divider()

          // Board Overview
          VStack(alignment: .leading, spacing: 12) {
            Label("Kanban Board", systemImage: "square.grid.3x3.topleft.filled")
              .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
              Text("• **Drag tasks** between columns to change status")
              Text("• **Click a task** to view details and edit notes")
              Text("• **Drag within a column** to reorder tasks")
              Text("• Tasks flow: **Inbox → Active → Done**")
              Text("• Use the **quick-add bar** at the top of Active to add tasks fast")
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
          }

          Divider()

          // Project Types
          VStack(alignment: .leading, spacing: 12) {
            Label("Project Types", systemImage: "folder")
              .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
              HStack(alignment: .top, spacing: 8) {
                Image(systemName: "square.grid.3x3.topleft.filled")
                  .foregroundStyle(.blue)
                  .frame(width: 20)
                VStack(alignment: .leading) {
                  Text("Kanban").fontWeight(.medium)
                  Text("Task board with columns for workflow stages.")
                    .foregroundStyle(.secondary)
                }
              }
              HStack(alignment: .top, spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                  .foregroundStyle(.green)
                  .frame(width: 20)
                VStack(alignment: .leading) {
                  Text("Research").fontWeight(.medium)
                  Text("Tile-based workspace for notes, links, findings, and comparisons.")
                    .foregroundStyle(.secondary)
                }
              }
              HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checklist")
                  .foregroundStyle(.orange)
                  .frame(width: 20)
                VStack(alignment: .leading) {
                  Text("Tracker").fontWeight(.medium)
                  Text("Checklist-style tracker for progress on items.")
                    .foregroundStyle(.secondary)
                }
              }
            }
            .font(.system(size: 13))
          }

          Divider()

          // Features
          VStack(alignment: .leading, spacing: 12) {
            Label("Features", systemImage: "sparkles")
              .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
              Text("• **README** — Each project has a pinned README for context. Click to expand/edit.")
              Text("• **Inbox** — Review design docs and artifacts from Lobs. Threaded conversations supported.")
              Text("• **Templates** — Create task templates to quickly add groups of related tasks.")
              Text("• **Project Management** — Reorder, archive, or delete projects from the project menu.")
              Text("• **Auto-refresh** — Dashboard syncs with git automatically (configurable in settings).")
              Text("• **Worker Status** — See if Lobs is currently working on tasks (shown in stats bar).")
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
          }

          Divider()

          // Git Sync
          VStack(alignment: .leading, spacing: 12) {
            Label("How It Works", systemImage: "arrow.triangle.2.circlepath")
              .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
              Text("Lobs Dashboard syncs state through a shared git repository (**lobs-control**). All tasks, projects, and research are stored as JSON files.")
              Text("")
              Text("• **You** create tasks and requests through the dashboard")
              Text("• **Lobs** (the AI worker) picks up tasks, does the work, and updates status")
              Text("• Everything stays in sync via git — pull to see updates, push to share changes")
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
          }
        }
        .padding(20)
      }
    }
    .frame(width: 500, height: 600)
    .background(Theme.boardBg)
  }
}

#Preview {
  HelpPanelSheet(isPresented: .constant(true))
}
