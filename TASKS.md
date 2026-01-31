# Lobs Dashboard

Local macOS SwiftUI dashboard for reviewing and updating tasks in `lobs-control`.
It reads from and writes to `lobs-control/state/tasks.json` and commits changes via `git`.

## Data model (schemaVersion=2)

`state/tasks.json` contains:
- `schemaVersion`: `2`
- `generatedAt`: ISO-8601 timestamp
- `tasks`: array of task objects

Each task includes:
- `id`: string
- `title`: string
- `status`: string (known: `inbox`, `active`, `waiting_on`, `completed`, `rejected`; other values supported)
- `owner`: string (known: `lobs`, `rafe`; other values supported)
- `createdAt`: ISO-8601 timestamp
- `updatedAt`: ISO-8601 timestamp
- `artifactPath`: optional string path relative to repo root
- `notes`: optional string

## UI behavior

- **Sections:** Inbox, Active, Waiting on, Completed, Rejected, Other.
- **Unknown status handling:** any unrecognized `status` is grouped under **Other** with its raw status label.
- **Artifact viewer:** selects and loads `artifactPath` content if present, otherwise shows a placeholder.

## Task approval flow

- **Approve** sets `status=completed`.
- **Reject** sets `status=rejected`.
- The app writes `state/tasks.json`, then runs:
  - `git add -A`
  - `git commit -m "Lobs: set <id> status=<status>"`
  - `git push` (optional)

## Repo selection

- The repo path is stored in `@AppStorage("repoPath")`.
- Use **Choose lobs-control…** to select the repo folder.

## Notes

- No network services or web server.
- If no task is selected, the detail pane shows `(select a task)`.
