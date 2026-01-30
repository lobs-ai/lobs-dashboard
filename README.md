# lobs-dashboard

Local macOS SwiftUI app for operating `lobs-control`.

- No networking.
- Reads/writes `lobs-control/state/*.json`.
- Runs `git` under the hood to commit (and optionally push) changes.

## Run (macOS)

```bash
cd ~/lobs-dashboard
swift run lobs-dashboard
```

## First-run usage
- Click **Choose lobs-control…** and select your `lobs-control` folder.
- Select a task to view its artifact.
- Use ✅ Approve / ❌ Reject to update status (writes `state/tasks.json`).
- The app will run `git add -A`, `git commit`, and (if enabled) `git push`.

## Notes for Codex
- Repo path is configurable via `@AppStorage("repoPath")`.
- Git is executed via `Process` calling `/usr/bin/env git`.
- Task store format: `state/tasks.json` (schemaVersion=1).
