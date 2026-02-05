# lobs-dashboard

Native macOS SwiftUI app for operating **Lobs** via a shared git state repo (**`lobs-control`**).

- No server required.
- Reads/writes JSON state under your local `lobs-control/` checkout.
- Runs `git` under the hood to pull/commit/push changes.

## Prereqs
- macOS (SwiftUI)
- `git`

## Setup (required)
You need a local checkout of `lobs-control`.

```bash
git clone git@github.com:RafeSymonds/lobs-control.git ~/lobs-control
```

If you clone `lobs-dashboard` but **don’t** have `lobs-control` set up yet, the app will simply show the onboarding/“choose repo” UI and you won’t be able to view/edit tasks until you select a valid `lobs-control` folder.

## Run (macOS)

```bash
cd ~/lobs-dashboard
./bin/build
./bin/run
```

## First run
- Click **Choose lobs-control…** and select your `~/lobs-control` folder.
- The dashboard will load state from the repo and (optionally) auto-sync via git.

## Data layout (in `lobs-control/`)
- `state/projects.json` — project definitions
- `state/tasks/*.json` — one JSON file per task
- `state/research/<projectId>/...` — research docs + requests
- `inbox/` and `artifacts/` — async writeups and threads

## Notes for devs/agents
- Repo path is stored in UserDefaults under key `repoPath`.
- Git is executed via `Process` calling `/usr/bin/env git`.
- The app is designed to be resilient to new/unknown task statuses.
