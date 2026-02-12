# Documents Button Visibility Fix

## Issue Fixed
The Documents toolbar button was always visible, even when there were no agent documents to display. This created confusion because:
1. The button appeared immediately on launch (before async document loading)
2. Clicking it showed an empty state
3. Users weren't sure if it was broken or just loading

## Solution
Made the Documents button conditional - it now only appears when there are agent documents available, matching the existing pattern used for the Templates button.

## Change Details

### Modified Files
- `Sources/LobsDashboard/ContentView.swift` - Added conditional visibility check

### Code Change
```swift
// Before: Always visible
DocumentsToolbarButton(vm: vm) {
  withAnimation(.easeInOut(duration: 0.25)) { showDocuments = true }
}

// After: Only visible when documents exist
if !vm.agentDocuments.isEmpty {
  DocumentsToolbarButton(vm: vm) {
    withAnimation(.easeInOut(duration: 0.25)) { showDocuments = true }
  }
}
```

## Pattern Consistency

This change aligns the Documents button with the existing toolbar button pattern:

| Button | Visibility | Reason |
|--------|-----------|--------|
| **Inbox** | Always visible | Core feature, always relevant |
| **New Task** | Always visible | Primary action |
| **Refresh** | Always visible | Always available |
| **Templates** | Conditional (`!vm.templates.isEmpty`) | Optional feature |
| **Documents** | Conditional (`!vm.agentDocuments.isEmpty`) | Optional feature |

## User Experience

### Before
1. App launches
2. Documents button appears immediately (even though documents aren't loaded yet)
3. User clicks → sees empty state or loading spinner
4. Confusion: "Is this broken? Should I wait?"

### After
1. App launches
2. Documents button NOT visible (no documents loaded yet)
3. Background task loads agent documents
4. Documents button smoothly appears when documents are available
5. User sees button → knows there's content to view

## Testing

### Unit Tests
Created `DocumentsButtonVisibilityTests.swift` with 6 test cases:
- ✅ Button hidden when no documents
- ✅ Button visible when documents exist
- ✅ Matches Templates button pattern
- ✅ Appears after async load
- ✅ Consistent with OverviewView section logic
- ✅ Updates dynamically as documents are added/removed

### Manual Testing Steps
1. **Fresh app launch (no documents):**
   ```bash
   # Remove agent documents from lobs-control repo
   rm -rf ~/lobs-control/state/reports/*
   rm -rf ~/lobs-control/state/research/*
   
   # Launch dashboard
   ./bin/run
   
   # Expected: Documents button NOT visible in toolbar
   ```

2. **After documents are loaded:**
   ```bash
   # Add an agent document
   mkdir -p ~/lobs-control/state/reports
   echo "# Report\nTest content" > ~/lobs-control/state/reports/test.md
   
   # Refresh app (⌘R)
   
   # Expected: Documents button appears in toolbar
   ```

3. **Dynamic visibility:**
   ```bash
   # Delete all documents
   rm -rf ~/lobs-control/state/reports/*
   rm -rf ~/lobs-control/state/research/*
   
   # Refresh app (⌘R)
   
   # Expected: Documents button disappears from toolbar
   ```

## Build Status
✅ Compiles successfully: `swift build` → exit 0  
⚠️ Preview macro errors are pre-existing and unrelated

## Migration Notes
No migration needed - this is purely a UI visibility change. Existing documents are unaffected.

## Future Considerations
If documents loading time becomes an issue, consider:
- Adding a loading indicator to the Documents button
- Pre-loading documents on app launch (foreground instead of background)
- Caching document metadata for faster initial display

For now, the conditional visibility provides the cleanest UX.
