# lobs-dashboard — Agent Guide

macOS SwiftUI desktop app for managing tasks, projects, and research. Rafe's primary interface for interacting with Lobs.

## Quick Start
Open `Sources/LobsDashboard/` in Xcode or build via:
```bash
./bin/build   # Generates build info, builds, saves hash to ~/.lobs/dashboard-build-commit
swift run
```

### Build Info
The build script (`bin/build`) saves the current HEAD commit hash to
`~/.lobs/dashboard-build-commit` after each successful build. The running app reads this file
at runtime to detect when you've pulled new code but haven't recompiled (shows "N to rebuild"
indicator). `BuildInfo.generated.swift` serves as a compile-time fallback if the hash file
doesn't exist.

## Architecture

### API-First Design
The dashboard is a **REST API client** — all state lives in lobs-server (FastAPI + SQLite). There is no local persistence or git-based state management.

```
Dashboard ←→ lobs-server (REST API over Tailscale) ←→ SQLite DB
                    ↕
           Orchestrator (built-in)
```

### Key Files
```
Sources/LobsDashboard/
├── Models.swift          # Data models (Task, Project, etc.)
├── APIService.swift      # REST API client (all server communication)
├── AppViewModel.swift    # Main view model (state, CRUD via API)
├── Store.swift           # Legacy git-backed persistence (unused, kept as fallback)
├── GitHubService.swift   # GitHub API client (Issues CRUD — still used for GitHub sync)
├── ContentView.swift     # Root view (sidebar, project picker, create sheets)
├── BoardView.swift       # Kanban board (columns: active, waiting, blocked, done)
├── OverviewView.swift    # Dashboard home screen (stats, project cards, activity feed)
├── ResearchView.swift    # Research project view (tile grid, detail panel, requests)
├── InboxView.swift       # Inbox for design docs and artifacts
├── DocumentsView.swift   # Documents browser
├── SettingsView.swift    # Settings (server URL config, connection test)
└── SpellCheckingTextEditor.swift  # NSTextView wrapper with spell check
```

### Data Flow
- **APIService.swift** handles all HTTP calls to lobs-server
- **AppViewModel.swift** calls APIService methods, manages UI state
- **Server URL** is configurable in Settings (stored in AppConfig)
- **No git operations** for task/project/inbox state — all via REST API
- **GitHub Issues sync** is the only remaining git-adjacent feature (separate from state management)

## Key Concepts

### Project Types
- **Kanban** — traditional board with task columns (active, waiting, blocked, done)
- **Research** — tile-based workspace with notes, links, findings, comparisons + "Ask Lobs" requests

### Server Connection
- Dashboard connects to lobs-server over Tailscale (private network)
- Server URL configured in Settings → connection test verifies reachability
- First-run onboarding prompts for server URL (no git clone needed)

### GitHub Mode (Collaborative)
- Optional per-project: syncs tasks bidirectionally with GitHub Issues
- GitHub is source of truth for collaborative projects
- Separate from the core API-based state management

### Views
- **OverviewView** — default landing page, shows stats across all projects
- **BoardView** — kanban columns for task projects
- **ResearchView** — tile grid + detail split for research projects
- **InboxView** — document reader for artifacts and inbox items
- **DocumentsView** — browse reports and research documents

## API Endpoints Used
All endpoints are defined in APIService.swift. Key ones:
- `GET/POST/PUT /api/tasks` — task CRUD
- `GET/POST /api/projects` — project management
- `GET/POST /api/inbox` — inbox items
- `GET/POST /api/docs` — documents and reports
- `GET /api/worker-status` — orchestrator worker status
- `GET /api/agents` — agent statuses
- `GET /api/orchestrator/*` — orchestrator control (status, pause, resume)
- `GET /api/research/*` — research requests and findings

## Common Edits
- **Add a new view**: Create SwiftUI view, wire into ContentView
- **Add a model field**: Update Models.swift (make new fields optional for backwards compat)
- **Add an API call**: Add method to APIService.swift, call from AppViewModel
- **Change server behavior**: Edit lobs-server (separate repo: `~/lobs-server`)

## Testing
No formal test suite yet. Validate by building (`swift build`) and manual testing.
Server has full test coverage — run `cd ~/lobs-server && python -m pytest`.

## Dependencies
- Pure SwiftUI + AppKit (NSViewRepresentable for spell checking)
- No external packages — everything is stdlib/system frameworks
