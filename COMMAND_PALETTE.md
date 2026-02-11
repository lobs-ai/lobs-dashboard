# Command Palette (⌘K)

## Overview

The command palette provides quick access to projects, tasks, actions, and navigation throughout the dashboard.

## Usage

### Opening
- Press `⌘K` from anywhere in the app
- The palette appears as a centered overlay

### Navigation
- **Type** to search across all items
- **↑/↓** arrow keys to navigate results
- **Enter** to execute the selected action
- **Escape** to close the palette

### Filter Modes

Use prefix characters to filter results:

- `>` — Actions only (create task, refresh, etc.)
- `#` — Projects only
- `@` — Tasks only
- `/` — Research docs only
- `$` — Inbox items only

**Example:** Type `#dash` to find projects matching "dash"

## Features

### Smart Ranking

Results are ranked by relevance:
1. **Exact match** (highest priority)
2. **Prefix match** (starts with query)
3. **Word boundary match** (query matches start of a word)
4. **Fuzzy match** (characters appear in order)

### Recent Selections

The palette remembers your last 5-10 selections and shows them when you open with no query.

### Quick Actions

Built-in actions available:
- Create New Task
- Refresh / Sync
- Go to Overview
- Open Inbox
- AI Usage Stats

## Implementation Details

### Files
- `CommandPaletteView.swift` — Main view and search logic
- `ContentView.swift` — Integration and callbacks

### Architecture

```
CommandPaletteView
├── Search field with filter mode detection
├── Results list (ScrollView)
│   ├── Quick actions
│   ├── Project results
│   ├── Task results
│   ├── Research results
│   └── Inbox results
├── Fuzzy matching engine
├── Ranking algorithm
└── Recents persistence (UserDefaults)
```

### Key Components

**CommandResult**: Model for search results with icon, title, subtitle, category, and action closure.

**FilterMode**: Enum for search scoping (all/actions/projects/tasks/docs/inbox).

**KeyEventHandler**: NSView wrapper for intercepting arrow keys and escape.

### Extensibility

To add new result types:
1. Create a new result generator method (e.g., `trackerResults()`)
2. Add it to the `results` computed property
3. Add a filter mode prefix if desired
4. Update the filter mode enum and hints

### Callbacks

The palette uses callbacks to trigger ContentView state changes:
- `onNewTask`: Opens the new task sheet
- `onOpenInbox`: Opens inbox with optional item selection
- `onOpenAIUsage`: Opens AI usage stats sheet

## Testing Checklist

- [ ] ⌘K opens palette
- [ ] Search works across all categories
- [ ] Filter modes work (>, #, @, /, $)
- [ ] Arrow keys navigate results
- [ ] Enter executes selected action
- [ ] Escape closes palette
- [ ] Click outside closes palette
- [ ] Recents persist across app restarts
- [ ] Fuzzy matching finds partial matches
- [ ] Ranking prioritizes exact/prefix matches

## Future Enhancements

- [ ] Add keyboard shortcut hints in result rows
- [ ] Search research tiles/docs content (not just projects)
- [ ] Search tracker items
- [ ] Support for multi-word queries (AND logic)
- [ ] Syntax highlighting for filter prefixes
- [ ] Command history (beyond recents)
- [ ] Custom action aliases/shortcuts
