# Test Verification Guide: Inbox Unread Count Fix

## Issue Fixed
The inbox was showing unread counts for items from `state/inbox/` (system alerts/suggestions) that weren't visible in the InboxView, causing confusion where the badge count didn't match the visible items.

## Change Made
Updated `unreadInboxCount` computed property in `AppViewModel.swift` to only count items from `inbox/` directory, matching InboxView's filter logic.

### Before
```swift
var unreadInboxCount: Int {
  inboxItems.filter { item in
    !item.relativePath.hasPrefix("artifacts/") &&  // Excluded artifacts
    (!item.isRead || unreadFollowupCount(docId: item.id) > 0)
  }.count
}
// This included state/inbox/ items that InboxView doesn't display
```

### After
```swift
var unreadInboxCount: Int {
  inboxItems.filter { item in
    item.relativePath.hasPrefix("inbox/") &&  // Only inbox/ items
    (!item.isRead || unreadFollowupCount(docId: item.id) > 0)
  }.count
}
// Now matches InboxView filter exactly
```

## Test Files Updated
- `Tests/LobsDashboardTests/InboxUnreadCountTests.swift` - Updated all tests to expect only `inbox/` items
- Added new test: `testStateInboxItemsCompletelyExcluded()`
- Added new test: `testMixedInboxPrefixesFilteredCorrectly()`

## Manual Verification Steps

### Setup Test Scenario
1. Create test files in lobs-control repo:
   ```bash
   mkdir -p ~/lobs-control/inbox
   mkdir -p ~/lobs-control/state/inbox
   mkdir -p ~/lobs-control/artifacts
   
   # Create inbox item (should be counted)
   echo "# Action Needed\nPlease review" > ~/lobs-control/inbox/action-item.md
   
   # Create state/inbox item (should NOT be counted)
   echo '{"type":"suggestion"}' > ~/lobs-control/state/inbox/system-alert.json
   
   # Create artifact (should NOT be counted)
   echo "# Artifact\nGenerated content" > ~/lobs-control/artifacts/report.md
   ```

2. Launch lobs-dashboard and open Inbox (⌘I)

### Expected Behavior
- **Badge count**: Shows "1 new" (only the inbox/action-item.md)
- **InboxView display**: Shows only the inbox/action-item.md
- **NOT shown**: state/inbox/system-alert.json (but no badge for it either)
- **NOT shown**: artifacts/report.md (no badge for it either)

### Verification Checklist
- [ ] Badge count matches number of visible items in InboxView
- [ ] Mark all as read → badge shows "0 new"
- [ ] Add more inbox/ items → badge count increases correctly
- [ ] Add state/inbox/ items → badge count stays unchanged
- [ ] Add artifacts/ items → badge count stays unchanged

## Test Suite Execution

When SPM build issues are resolved, run:
```bash
cd /Users/lobs/lobs-dashboard
rm -rf .build
swift test --filter InboxUnreadCountTests
```

Expected: All 8 tests pass
- testUnreadCountOnlyCountsInboxItems
- testUnreadCountExcludesStateInboxItems
- testUnreadCountRespectsReadStatus
- testInboxViewFilterMatchesUnreadCountFilter
- testArtifactsCompletelyExcluded
- testStateInboxItemsCompletelyExcluded
- testMixedInboxPrefixesFilteredCorrectly

## Build Status
✅ Main build passes: `swift build` exits 0
⚠️ Test suite has SPM "multiple producers" issue (unrelated to this change)

## Files Modified
1. `Sources/LobsDashboard/AppViewModel.swift` - Fixed unreadInboxCount filter
2. `Tests/LobsDashboardTests/InboxUnreadCountTests.swift` - Updated test expectations
3. `TEST_VERIFICATION.md` - This file

## Related Code Patterns
InboxView.swift already had the correct filter:
```swift
items = items.filter { item in
  item.relativePath.hasPrefix("inbox/")
}
```

Now AppViewModel.unreadInboxCount uses the same filter logic.
