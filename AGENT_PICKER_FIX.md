# Agent Picker Display Fix

## Issue Fixed
The agent picker in task creation was showing only the raw agent type identifier (e.g., "programmer") instead of displaying the full name with emoji (e.g., "🛠️ Programmer").

## User Report
> "when choosing an agent for a task on task creation it should have names"

## Solution
Replaced SwiftUI `Picker` with `Menu` to have full control over the collapsed display.

### Before
When the picker was collapsed, it showed:
```
programmer
```

### After
When the menu is collapsed, it shows:
```
🛠️ Programmer
```

## Implementation Details

### Why Picker Didn't Work
SwiftUI's `Picker` component displays only the tag value when collapsed, regardless of the content defined in the picker options. Even though we had:

```swift
HStack {
  Text("🛠️")
  Text("Programmer")
}
.tag("programmer")
```

The collapsed picker would only show `"programmer"` (the tag value).

### Menu Solution
`Menu` allows custom control over both the menu items AND the collapsed button label:

```swift
Menu {
  // Menu items (same as before)
  ForEach(availableAgents) { agent in
    Button { selectedAgent = agent.0 } label: {
      HStack {
        Text(agent.1)  // emoji
        Text(agent.0.capitalized)
      }
    }
  }
} label: {
  // Custom collapsed display
  HStack {
    if let selected = availableAgents.first(where: { $0.0 == selectedAgent }) {
      Text(selected.1)  // "🛠️"
      Text(selected.0.capitalized)  // "Programmer"
    }
    Spacer()
    Image(systemName: "chevron.down")
  }
  .padding()
  .background(Color.controlBackground)
  .clipShape(RoundedRectangle(cornerRadius: 6))
}
```

## Available Agents
The picker/menu shows these agents:

| ID | Emoji | Name | Description |
|----|-------|------|-------------|
| `programmer` | 🛠️ | Programmer | Code implementation, bug fixes |
| `researcher` | 🔬 | Researcher | Research and investigation |
| `reviewer` | 🔍 | Reviewer | Code review and feedback |
| `writer` | ✍️ | Writer | Documentation and writing |
| `architect` | 🏗️ | Architect | System design and architecture |

## Testing

### Unit Tests
Created `AgentPickerTests.swift` with 10 tests covering:
- ✅ Agent structure validation (ID, emoji, description)
- ✅ Agent ID matching expected types
- ✅ Emoji uniqueness
- ✅ Name capitalization
- ✅ Selected agent display format
- ✅ Placeholder behavior for invalid selection
- ✅ Default agent is programmer
- ✅ Description informativeness
- ✅ UI display expectations
- ✅ Menu chevron indicator

### Manual Testing
1. **Create new task:**
   - Click "+ New Task" or press ⌘N
   - Observe agent picker shows "🛠️ Programmer" by default

2. **Change agent:**
   - Click the agent menu
   - Select different agent (e.g., "🔬 Researcher")
   - Verify collapsed menu shows "🔬 Researcher"

3. **Visual consistency:**
   - Check emoji is visible and clear
   - Check name is capitalized
   - Check chevron down indicator is present
   - Check padding and background match other controls

## Files Modified
1. `Sources/LobsDashboard/ContentView.swift`
   - Replaced `Picker` with `Menu` for agent selection
   - Added custom collapsed label showing emoji + name

2. `Tests/LobsDashboardTests/UI/AgentPickerTests.swift`
   - Created 10 comprehensive tests
   - Documents expected UI behavior

## Build Status
✅ Compiles successfully: `swift build` → exit 0  
⚠️ Preview macro errors are pre-existing and unrelated

## Pattern for Future Reference

When you need a dropdown that shows custom content in both expanded AND collapsed states:

```swift
// ❌ Don't use Picker if you need custom collapsed display
Picker("Label", selection: $value) {
  ForEach(items) { item in
    CustomView(item)  // Only shows in expanded state
      .tag(item.id)   // Tag value shows in collapsed state
  }
}

// ✅ Do use Menu for full control
Menu {
  ForEach(items) { item in
    Button { value = item.id } label: {
      CustomView(item)  // Shows in expanded menu
    }
  }
} label: {
  CustomSelectedView(selected: value)  // Shows in collapsed state
}
```

## User Experience Impact
**Before:** Users had to remember what "programmer" meant  
**After:** Users see "🛠️ Programmer" - clear, visual, and informative
