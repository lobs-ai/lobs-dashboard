# lobs-dashboard (skeleton)

Minimal localhost-only dashboard that proves the loop:

**task → state → artifact → human approval**

## Run (macOS)

```bash
cd lobs-dashboard
swift run lobs-dashboard
```

Then open:
- http://127.0.0.1:8080

## Data storage

On first run, it seeds:
- a task in `tasks.json`
- a markdown artifact in `artifacts/`
- a JSONL log in `log.jsonl`

The server prints the exact paths on startup.

## Endpoints
- `GET /` → UI
- `GET /api/tasks` → tasks array
- `GET /api/tasks/{id}/artifact` → markdown text
- `POST /api/tasks/{id}/approve` → sets status=completed
- `POST /api/tasks/{id}/reject` → sets status=rejected

## Notes
- Uses `Network` (`NWListener`) for a tiny HTTP server.
- No external frameworks.
