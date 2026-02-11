# Task Management UX Improvement Plan

**Version:** 1.0  
**Date:** 2026-02-11  
**Status:** Design Complete, Ready for Implementation

## Executive Summary

This document outlines a cohesive set of UX improvements to address current pain points in the lobs-dashboard task management interface. The improvements focus on four key areas:

1. **Enhanced Sync Visibility** — Make git/GitHub sync state immediately visible
2. **Improved Inbox Experience** — Streamline artifact review and triage workflows
3. **Markdown-Aware Task Notes** — Add preview and better editing for markdown content
4. **Keyboard Shortcut Discoverability** — Make power-user features more accessible

All improvements maintain the existing clean, native macOS aesthetic while adding meaningful productivity enhancements.

---

## Current Pain Points (Analysis)

### 1. Sync State Not Visible Enough

**Current Implementation:**
- Sync status shown in `SystemHealthStatusIcon` (small heart icon in toolbar)
- Requires clicking icon to see popover with details
- No at-a-glance indication of sync progress or issues
- Git operations happen in background with minimal feedback

**User Impact:**
- Users uncertain if changes are saved/pushed
- No visibility into ongoing sync operations
- Easy to miss sync errors or conflicts
- Uncertainty about whether remote is up-to-date

**Evidence in Code:**
- `SystemHealthStatusIcon.swift` shows status only in popover
- `AppViewModel.swift` has sync state but no persistent visual indicators
- Auto-sync runs silently in background

### 2. Inbox View Needs Work

**Current Implementation:**
- Basic filtering by read/unread status
- Triage filter (all/needs_response/resolved)
- Search functionality exists
- Thread-based organization

**User Impact:**
- Difficult to process large numbers of artifacts
- No bulk actions (mark all read, archive multiple)
- Thread UI can be overwhelming for long conversations
- No priority/importance indicators
- Unclear distinction between actionable vs. reference items

**Evidence in Code:**
- `InboxView.swift` has basic filtering but no bulk operations
- No visual priority system
- Thread expansion can make view cluttered

### 3. Task Notes Need Markdown Preview

**Current Implementation:**
- Plain text editing only
- Uses `SpellCheckingTextEditor.swift` (NSTextView wrapper)
- No formatting, preview, or markdown support
- Enter-to-send in some contexts (inbox) but not task notes

**User Impact:**
- Hard to read formatted content
- Can't easily include code snippets, lists, or structured notes
- Difficult to distinguish between different types of content
- Copy-paste from markdown sources loses formatting

**Evidence in Code:**
- Task model has `notes: String?` field
- No markdown parsing or rendering in UI
- `SpellCheckingTextEditor` is basic text view

### 4. Keyboard Shortcuts Missing/Hidden

**Current Implementation:**
- Shortcuts exist: ⌘K (command palette), ⌘N (new task), ⌘R (refresh), ⌘I (inbox), ⌘/ (help)
- Shown on hover in some toolbar buttons
- Help panel exists (`HelpPanelSheet.swift`) with documentation
- Command palette provides searchable actions

**User Impact:**
- New users don't discover keyboard shortcuts
- No quick reference visible in UI
- Shortcuts not shown consistently across all actions
- Hard to learn power-user workflows

**Evidence in Code:**
- `ContentView.swift` has keyboard shortcuts defined
- Tooltips show shortcuts on some buttons
- No dedicated shortcuts panel or cheat sheet
- `COMMAND_PALETTE.md` exists but not linked in UI

---

## Proposed Solutions

## 1. Enhanced Sync Visibility

### Overview
Transform sync status from hidden popover to always-visible inline indicator with real-time feedback.

### Design Approach

**Primary Status Bar** (always visible):
- Add dedicated sync status area in toolbar (next to existing health icon)
- Show current state at a glance: "Synced", "Syncing...", "Push pending", "Error"
- Use color coding: green (synced), blue (syncing), orange (pending), red (error)
- Include icon + short text label
- Timestamp of last successful sync ("Synced 2m ago")

**Live Sync Progress**:
- Show subtle progress indicator during git operations
- Display operation type: "Pulling...", "Pushing...", "Committing..."
- Include commit count when pushing ("Pushing 3 commits...")
- Show spinner or progress bar for long operations

**Enhanced Popover** (on click):
- Keep existing health details
- Add sync timeline: recent sync events with timestamps
- Show pending changes count with file breakdown
- Display current branch and remote tracking info
- Quick action: "Force sync now" button

**Error States**:
- Prominent error indicator when sync fails
- Show error message inline (truncated, full text in popover)
- Action buttons: "Retry", "View details", "Resolve conflict"
- Don't hide errors in popover — show in main UI

### Implementation Tasks

#### Task 1.1: Create SyncStatusView Component
**Priority:** High  
**Effort:** Medium (4-6 hours)  
**Files:** New `Sources/LobsDashboard/SyncStatusView.swift`

Create a new SwiftUI view that displays sync status inline in the toolbar.

**Requirements:**
- Display current sync state (synced, syncing, pending, error)
- Show operation progress (pulling, pushing, committing)
- Include last sync timestamp ("2m ago", "just now")
- Color-coded status (green/blue/orange/red)
- Icon + text label layout
- Tap to show detailed popover
- Animate transitions between states

**Technical Notes:**
- Use `@ObservedObject var vm: AppViewModel` for sync state
- Read from existing properties: `vm.isSyncing`, `vm.lastSyncTime`, `vm.pendingChangesCount`, `vm.lastPushError`
- Add new `vm.currentSyncOperation: String?` property to AppViewModel for live progress
- Use `TimelineView` for "X ago" formatting that updates automatically
- Follow existing `Theme.swift` patterns for colors/spacing

**Testing:**
- Manual sync (⌘R) shows "Syncing..." then "Synced"
- Pending commits show "Push pending (3)"
- Errors display inline with red color
- Click opens popover with details
- Auto-sync (30s) updates timestamp correctly

---

#### Task 1.2: Add Sync Operation Progress Tracking
**Priority:** High  
**Effort:** Medium (3-5 hours)  
**Files:** `Sources/LobsDashboard/AppViewModel.swift`, `Sources/LobsDashboard/Git.swift`

Add granular progress tracking for git operations.

**Requirements:**
- Track current operation type (pull, push, commit, none)
- Emit progress updates during long operations
- Calculate operation duration
- Store operation history for timeline view

**Technical Notes:**
- Add `@Published var currentSyncOperation: String? = nil` to AppViewModel
- Update in `syncRepoAsync()`, `pushNow()`, etc.
- Set operation at start: `currentSyncOperation = "Pulling from origin"`
- Clear on completion: `currentSyncOperation = nil`
- Add `syncOperationHistory: [SyncEvent]` array for timeline
- Create `SyncEvent` struct: `{ operation: String, timestamp: Date, success: Bool, error: String? }`

**Testing:**
- Start manual sync, verify UI shows "Pulling..."
- Complete sync, verify operation clears
- Trigger error, verify operation shows "Failed to push"
- Check history array populates correctly

---

#### Task 1.3: Enhanced Sync Popover with Timeline
**Priority:** Medium  
**Effort:** Medium (3-4 hours)  
**Files:** New `Sources/LobsDashboard/SyncStatusPopover.swift`, update `SystemHealthStatusIcon.swift`

Expand the sync popover to show detailed history and git info.

**Requirements:**
- Show last 10 sync events in timeline format
- Display current branch name and remote URL
- List pending changes by file (staged, unstaged)
- Quick actions: "Force sync", "View in Terminal", "Open repo"
- Handle empty states (no history, no pending changes)

**Technical Notes:**
- Create new `SyncStatusPopover` view separate from SystemHealthPopover
- Use `List` or `ScrollView` for timeline
- Format relative timestamps ("2m ago", "yesterday", "Feb 10")
- Add `openInTerminal()` action: `NSWorkspace.shared.openFile(repoPath, withApplication: "Terminal")`
- Read `vm.syncOperationHistory` for events
- Use existing `Git.swift` helpers for branch/status info

**Testing:**
- Timeline shows events in reverse chronological order
- Timestamps format correctly
- Empty states display properly
- Quick actions work (terminal opens, etc.)
- Popover width appropriate for content

---

#### Task 1.4: Integrate SyncStatusView into Toolbar
**Priority:** High  
**Effort:** Small (1-2 hours)  
**Files:** `Sources/LobsDashboard/ContentView.swift`

Add the new sync status view to the main toolbar.

**Requirements:**
- Place between refresh button and health icon
- Maintain proper spacing/alignment
- Show/hide based on repo being loaded
- Ensure doesn't crowd toolbar on smaller windows

**Technical Notes:**
- Add to `HStack` in toolbar section of ContentView
- Use `if vm.repoURL != nil` to conditionally show
- Apply consistent padding with other toolbar items
- Test with different window widths (min: 800pt)

**Testing:**
- Visible when repo loaded
- Hidden when no repo configured
- Spacing looks clean at various window sizes
- No layout shifts when status changes

---

## 2. Improved Inbox Experience

### Overview
Streamline the inbox view with bulk actions, better visual hierarchy, and priority indicators.

### Design Approach

**Visual Hierarchy**:
- Use card-based layout instead of plain list
- Add importance badges (AI-generated or manual)
- Color-code by category: artifacts, design docs, feedback, errors
- Show preview snippet in list view (first 100 chars)
- Add visual indicator for unread followups in thread

**Bulk Operations**:
- Multi-select mode with checkboxes
- Bulk actions toolbar: "Mark all as read", "Archive selected", "Delete selected"
- Keyboard shortcuts: `⌘A` (select all), `⌘⇧R` (mark all read)
- Smart selection: "Select all unread", "Select all in category"

**Improved Filtering**:
- Quick filter pills at top (All, Unread, Needs Response, Artifacts, Docs)
- Tag-based filtering (add tags to inbox items)
- Date range filter (Today, This week, This month)
- Sort options: Recent, Priority, Category

**Thread Improvements**:
- Collapsible thread UI (show only latest by default)
- Thread summary at top (# messages, last activity time)
- Quick reply without expanding full thread
- Mark thread as resolved / needs follow-up

### Implementation Tasks

#### Task 2.1: Card-Based Inbox List View
**Priority:** High  
**Effort:** Large (6-8 hours)  
**Files:** `Sources/LobsDashboard/InboxView.swift`

Redesign the inbox list to use card layout with better visual hierarchy.

**Requirements:**
- Replace plain List with card-based ScrollView
- Each card shows: title, category badge, snippet, timestamp, unread count
- Hover state with actions (mark read, archive, delete)
- Click to select/open detail view
- Visual distinction between read/unread
- Category color coding

**Technical Notes:**
- Create `InboxCardView` component
- Use `RoundedRectangle` background with shadow
- Category enum: `.artifact`, `.designDoc`, `.feedback`, `.error`, `.other`
- Add `category: InboxCategory?` field to `InboxItem` model
- Derive category from `artifactPath` or metadata
- Use `Theme.swift` colors for consistency

**Testing:**
- Cards render correctly for all inbox items
- Hover shows actions smoothly
- Click selects item and opens detail view
- Category badges display correct colors
- Performance with 100+ items

---

#### Task 2.2: Bulk Selection and Actions
**Priority:** Medium  
**Effort:** Medium (4-6 hours)  
**Files:** `Sources/LobsDashboard/InboxView.swift`, `Sources/LobsDashboard/AppViewModel.swift`

Add multi-select mode with bulk operations.

**Requirements:**
- Toggle multi-select mode with button in toolbar
- Show checkboxes when in multi-select mode
- Selection state managed per item
- Bulk actions toolbar at bottom: "Mark read", "Archive", "Delete"
- Keyboard shortcuts: ⌘A (select all), ⌘⇧R (mark all read)
- Cancel selection with Escape

**Technical Notes:**
- Add `@State private var isMultiSelectMode: Bool = false`
- Add `@State private var selectedItemIds: Set<String> = []`
- Create `BulkActionsToolbar` component
- Add methods to AppViewModel: `markInboxItemsAsRead(ids: [String])`, `deleteInboxItems(ids: [String])`
- Wrap operations in confirmations for destructive actions
- Update Config to persist read state for multiple items

**Testing:**
- Multi-select mode toggles on/off
- Checkboxes appear/disappear correctly
- Can select/deselect individual items
- Select all works (⌘A)
- Bulk mark read updates state correctly
- Bulk delete shows confirmation

---

#### Task 2.3: Quick Filter Pills UI
**Priority:** Medium  
**Effort:** Small (2-3 hours)  
**Files:** `Sources/LobsDashboard/InboxView.swift`

Add quick filter pills for common inbox views.

**Requirements:**
- Horizontal row of filter pills above inbox list
- Pills: All (default), Unread, Needs Response, Artifacts, Design Docs
- Active pill highlighted
- Click to toggle filter
- Show count badges on pills (e.g., "Unread (5)")

**Technical Notes:**
- Create `FilterPill` component (Capsule button with badge)
- Use `@State private var activeFilter: InboxFilter = .all`
- Filter enum: `.all`, `.unread`, `.needsResponse`, `.artifacts`, `.designDocs`
- Update `filteredItems` computed property to apply active filter
- Count badges use existing filter logic

**Testing:**
- Pills render in horizontal row
- Active pill highlighted correctly
- Click switches filter and updates list
- Count badges accurate
- Filters combine with search text correctly

---

#### Task 2.4: Collapsible Thread UI
**Priority:** Low  
**Effort:** Medium (4-5 hours)  
**Files:** `Sources/LobsDashboard/InboxView.swift`

Improve thread display with collapsible sections and summaries.

**Requirements:**
- Show thread summary at top (collapsed by default)
- Summary shows: message count, last activity, participants
- Click to expand/collapse thread
- Quick reply field without full expansion
- "Show all messages" button expands full thread

**Technical Notes:**
- Add `@State private var expandedThreads: Set<String> = []`
- Create `ThreadSummaryView` component
- Only render full thread messages when expanded
- Quick reply uses `EnterToSendTextView` (already exists)
- Persist expanded state in `@AppStorage`

**Testing:**
- Threads collapsed by default
- Summary shows accurate info
- Expand/collapse animates smoothly
- Quick reply submits correctly
- Full thread renders when expanded

---

## 3. Markdown-Aware Task Notes

### Overview
Add markdown preview and better editing for task notes field.

### Design Approach

**Split View Editor**:
- Side-by-side edit/preview panes for task notes
- Live preview updates as you type
- Toggle between edit-only, preview-only, split view
- Syntax highlighting in edit pane (optional)

**Markdown Toolbar**:
- Quick insert buttons for common markdown: headers, bold, italic, lists, code blocks
- Keyboard shortcuts for formatting: ⌘B (bold), ⌘I (italic), ⌘K (link)
- Template snippets: checklist, code block, table

**Preview Rendering**:
- Use SwiftUI markdown rendering (AttributedString with markdown)
- Support GitHub-flavored markdown (tables, task lists, code highlighting)
- Clickable links in preview
- Copy rendered HTML to clipboard

**Context Menu**:
- Right-click in editor: Insert template, Format as..., Copy as HTML
- Right-click in preview: Copy markdown source, Export as PDF

### Implementation Tasks

#### Task 3.1: Markdown Preview Component
**Priority:** High  
**Effort:** Medium (4-6 hours)  
**Files:** New `Sources/LobsDashboard/MarkdownPreview.swift`

Create a reusable markdown preview component.

**Requirements:**
- Render markdown string to formatted SwiftUI view
- Support common markdown: headers, lists, bold, italic, code blocks, links, images
- Clickable links open in browser
- Scrollable content area
- Handle empty/nil input gracefully

**Technical Notes:**
- Use `AttributedString(markdown:)` for parsing (macOS 12+)
- Wrap in `ScrollView` + `Text` with markdown-rendered AttributedString
- For code blocks, use monospaced font with background color
- For links, use `.link()` modifier or custom gesture
- Add error handling for invalid markdown
- Follow `Theme.swift` for colors/fonts

**Testing:**
- Common markdown renders correctly
- Long content scrolls properly
- Links clickable and open in browser
- Code blocks formatted with monospace font
- Empty input shows placeholder

---

#### Task 3.2: Split View Markdown Editor
**Priority:** High  
**Effort:** Large (6-8 hours)  
**Files:** New `Sources/LobsDashboard/MarkdownEditor.swift`

Create split-view editor with live markdown preview.

**Requirements:**
- Three-pane toggle: Edit only, Split view, Preview only
- Edit pane uses existing `SpellCheckingTextEditor`
- Preview pane uses new `MarkdownPreview` component
- Live update (debounced 300ms)
- Resizable split divider (optional, nice-to-have)
- Toggle button in toolbar

**Technical Notes:**
- Create `MarkdownEditor` view with `@Binding var text: String`
- Use `@State private var viewMode: EditorMode = .split` (.edit, .split, .preview)
- `HStack` with conditional views based on `viewMode`
- Add divider between panes in split mode
- Debounce preview updates using `onChange` with delay
- Picker for view mode in toolbar

**Testing:**
- Switch between view modes
- Edit updates preview with ~300ms delay
- Both panes scroll independently
- Text binding works correctly
- No performance issues with large documents (>10KB)

---

#### Task 3.3: Markdown Formatting Toolbar
**Priority:** Medium  
**Effort:** Medium (3-5 hours)  
**Files:** `Sources/LobsDashboard/MarkdownEditor.swift`

Add formatting toolbar with quick insert buttons.

**Requirements:**
- Toolbar above editor with formatting buttons
- Buttons: H1, H2, Bold, Italic, Link, Code block, Bullet list, Numbered list
- Insert markdown syntax at cursor position
- Keyboard shortcuts: ⌘B (bold), ⌘I (italic), ⌘K (link)
- Selection formatting (wrap selected text)

**Technical Notes:**
- Create `MarkdownToolbar` component
- Access NSTextView's `selectedRange` from `SpellCheckingTextEditor`
- Insert methods: `insertMarkdown(prefix: String, suffix: String)`, `wrapSelection(prefix:, suffix:)`
- Keyboard shortcuts use `.keyboardShortcut()` modifier
- For link: show popover to enter URL
- For code block: insert triple backticks with newlines

**Testing:**
- Buttons insert correct markdown syntax
- Keyboard shortcuts work (⌘B, ⌘I, ⌘K)
- Selection wrapping works correctly
- Cursor position correct after insertion
- Link popover shows and inserts properly

---

#### Task 3.4: Integrate Markdown Editor into Task Edit Sheet
**Priority:** High  
**Effort:** Small (2-3 hours)  
**Files:** `Sources/LobsDashboard/ContentView.swift` (or wherever task edit sheet is)

Replace plain text notes field with new markdown editor.

**Requirements:**
- Swap `SpellCheckingTextEditor` for `MarkdownEditor` in task edit sheet
- Maintain existing autosave behavior
- Set reasonable default height (300pt)
- Show/hide based on whether notes exist
- Add "Add notes" button if notes field is empty

**Technical Notes:**
- Find task edit sheet view (likely in ContentView or separate sheet)
- Replace notes TextField/TextEditor with `MarkdownEditor(text: $task.notes ?? "")`
- Ensure binding updates task model correctly
- Test with existing tasks that have notes
- Preserve any existing note content

**Testing:**
- Edit existing task notes, verify markdown renders
- Create new task, add notes with markdown
- Formatting toolbar works in context
- Changes save correctly to task model
- Preview updates live during editing

---

## 4. Keyboard Shortcut Discoverability

### Overview
Make keyboard shortcuts more discoverable through better UI hints and a dedicated reference panel.

### Design Approach

**Always-Visible Hints**:
- Show keyboard shortcuts on ALL toolbar buttons (currently only some)
- Add shortcut badges to context menu items
- Display shortcuts in command palette results
- Highlight shortcuts in help text

**Keyboard Shortcuts Panel**:
- Dedicated panel (⌘/) showing all shortcuts organized by category
- Categories: Navigation, Tasks, Projects, Inbox, General
- Searchable shortcut list
- Visual keyboard diagram for common shortcuts (optional)
- "Print cheat sheet" button

**First-Run Onboarding**:
- Add keyboard shortcuts step to onboarding wizard
- Highlight 5 most important shortcuts for new users
- "Skip" option for power users
- Link to full shortcuts panel

**Contextual Hints**:
- Show relevant shortcuts in empty states ("Press ⌘N to create your first task")
- Tooltip improvements: include shortcut + description
- Inline hints in UI ("⌘K to search")

### Implementation Tasks

#### Task 4.1: Keyboard Shortcuts Reference Panel
**Priority:** High  
**Effort:** Medium (4-6 hours)  
**Files:** New `Sources/LobsDashboard/KeyboardShortcutsPanel.swift`, update `ContentView.swift`

Create a dedicated panel showing all keyboard shortcuts.

**Requirements:**
- Sheet that appears on ⌘/ (or ⌘?)
- Organized by category: Navigation, Tasks, Projects, Inbox, Editing, General
- Each shortcut shows: key combo, description, icon (optional)
- Search filter at top
- "Close" button (or Escape to dismiss)

**Technical Notes:**
- Create `KeyboardShortcut` struct: `{ keys: String, description: String, category: ShortcutCategory }`
- Define all shortcuts in static array
- Use `List` with section headers for categories
- Search filters by description or keys
- Style similar to macOS System Preferences keyboard shortcuts
- Monospaced font for key combos (⌘K, ⌘⇧N, etc.)

**Testing:**
- Panel opens on ⌘/
- All shortcuts listed correctly
- Categories organized logically
- Search filters correctly
- Panel dismisses on Escape or close button

---

#### Task 4.2: Add Shortcuts to All Toolbar Buttons
**Priority:** Medium  
**Effort:** Small (2-3 hours)  
**Files:** `Sources/LobsDashboard/ContentView.swift`

Ensure all toolbar buttons show keyboard shortcuts in tooltips.

**Requirements:**
- Audit all toolbar buttons
- Add shortcut hints to any missing
- Consistent format: "Action (⌘X)"
- Update existing `ToolbarButton` and `HoverIconButton` components

**Technical Notes:**
- Use `.help()` modifier for tooltips
- Format: `Button(...).help("Refresh (⌘R)")`
- Review ContentView toolbar section
- Check that shortcuts match actual keyboard shortcuts defined
- Ensure no duplicate shortcuts

**Testing:**
- Hover over all toolbar buttons
- Verify tooltips show shortcuts
- Shortcuts match actual behavior
- Format consistent across all buttons

---

#### Task 4.3: Shortcuts in Command Palette Results
**Priority:** Medium  
**Effort:** Small (2-3 hours)  
**Files:** `Sources/LobsDashboard/CommandPaletteView.swift`

Display keyboard shortcuts in command palette results.

**Requirements:**
- Show shortcut badge in result row (right-aligned)
- Only for results that have shortcuts
- Subtle styling (gray text, monospace font)
- Don't crowd the result title

**Technical Notes:**
- Update `CommandResult` struct to include `shortcut: String?` field
- Modify result generators to populate shortcut field
- In result row view, add shortcut badge in trailing position
- Use `.font(.system(.caption, design: .monospaced))`
- Color: `.secondary` or `.tertiary`

**Testing:**
- Command palette shows shortcuts for actions
- Shortcuts right-aligned and don't overlap title
- Null shortcuts don't show empty badge
- Styling matches rest of palette

---

#### Task 4.4: Onboarding Keyboard Shortcuts Step
**Priority:** Low  
**Effort:** Medium (3-4 hours)  
**Files:** Update onboarding flow (check `FirstTaskWalkthroughSheet.swift` or similar)

Add keyboard shortcuts introduction to first-run onboarding.

**Requirements:**
- New onboarding step after repo setup
- Show 5 essential shortcuts: ⌘N (new task), ⌘K (command palette), ⌘R (refresh), ⌘I (inbox), ⌘/ (shortcuts)
- Visual presentation (icons + key combos + descriptions)
- "Skip" and "Next" buttons
- Link to full shortcuts panel
- Mark as completed in user settings

**Technical Notes:**
- Add new view: `KeyboardShortcutsOnboardingView`
- Insert into onboarding flow sequence
- Use grid layout for 5 shortcuts (2 columns)
- Large, friendly icons from SF Symbols
- Store completion in `Config`: `settings.hasSeenKeyboardShortcutsOnboarding`
- Skip button sets completion flag

**Testing:**
- Appears for new users after repo setup
- Shows 5 shortcuts clearly
- Skip and Next buttons work
- Doesn't appear on subsequent launches
- Link to full panel works

---

## 5. Additional Quality-of-Life Improvements

### Quick Wins (Low Effort, High Impact)

#### Task 5.1: Task Quick Actions Menu
**Priority:** Medium  
**Effort:** Small (2-3 hours)

Add right-click context menu to tasks with common actions.

**Requirements:**
- Right-click on task shows menu
- Actions: Edit, Duplicate, Move to project, Change status, Delete
- Keyboard shortcuts shown in menu
- Dividers between action groups

---

#### Task 5.2: Project Color Coding
**Priority:** Low  
**Effort:** Small (1-2 hours)

Add optional color labels to projects for visual organization.

**Requirements:**
- Color picker in project settings
- Colored accent bar in project cards
- Color dot in sidebar project list
- Persist in project model

---

#### Task 5.3: Keyboard Navigation in Lists
**Priority:** Medium  
**Effort:** Medium (3-4 hours)

Add arrow key navigation for task lists, inbox, etc.

**Requirements:**
- ↑/↓ to navigate lists
- Enter to open selected item
- Space to toggle selection (multi-select mode)
- Visual focus indicator

---

## Implementation Roadmap

### Phase 1: Foundation (Week 1-2)
**Goal:** Core visibility and discoverability improvements

Priority Tasks:
1. Task 1.1: SyncStatusView Component ⭐
2. Task 1.2: Sync Operation Progress Tracking ⭐
3. Task 4.1: Keyboard Shortcuts Panel ⭐
4. Task 4.2: Shortcuts on Toolbar Buttons

**Deliverable:** Users can see sync status at a glance and discover keyboard shortcuts easily.

### Phase 2: Enhanced Editing (Week 2-3)
**Goal:** Markdown support for better note-taking

Priority Tasks:
1. Task 3.1: Markdown Preview Component ⭐
2. Task 3.2: Split View Markdown Editor ⭐
3. Task 3.3: Markdown Formatting Toolbar
4. Task 3.4: Integrate into Task Edit

**Deliverable:** Task notes support full markdown editing and preview.

### Phase 3: Inbox Improvements (Week 3-4)
**Goal:** Streamline artifact review workflow

Priority Tasks:
1. Task 2.1: Card-Based Inbox List ⭐
2. Task 2.2: Bulk Selection and Actions
3. Task 2.3: Quick Filter Pills
4. Task 1.3: Enhanced Sync Popover

**Deliverable:** Inbox is easier to scan, triage, and process in bulk.

### Phase 4: Polish (Week 4-5)
**Goal:** Finish remaining improvements and polish

Priority Tasks:
1. Task 1.4: Integrate Sync Status into Toolbar
2. Task 4.3: Shortcuts in Command Palette
3. Task 5.1: Task Quick Actions Menu
4. Task 2.4: Collapsible Thread UI (if time allows)

**Deliverable:** All improvements shipped and polished.

### Phase 5: Optional Enhancements
**Goal:** Nice-to-have features if time permits

- Task 4.4: Onboarding Shortcuts Step
- Task 5.2: Project Color Coding
- Task 5.3: Keyboard Navigation in Lists

---

## Success Metrics

### Quantitative
- **Sync visibility:** Sync state visible without clicks (0 clicks vs. 1 click currently)
- **Inbox efficiency:** Average time to process 10 items reduced by 30%
- **Markdown adoption:** % of tasks with markdown-formatted notes
- **Shortcut discovery:** % of users who open shortcuts panel in first week

### Qualitative
- Users report feeling confident about sync status
- Inbox feels less overwhelming with bulk actions
- Task notes are more organized and readable
- New users discover keyboard shortcuts faster

### User Feedback
- "I always know if my changes are synced"
- "Bulk marking inbox items as read saves so much time"
- "Markdown preview makes my task notes actually useful"
- "I learned all the shortcuts in my first session"

---

## Technical Considerations

### Performance
- **Markdown rendering:** Use `AttributedString(markdown:)` — efficient for macOS 12+
- **Live preview:** Debounce updates (300ms) to avoid re-rendering on every keystroke
- **Inbox cards:** Use lazy loading for large item counts (100+)
- **Sync status:** Update only on state change, not continuous polling

### Backwards Compatibility
- **Model changes:** All new fields optional, default values provided
- **Config migration:** Add new settings fields with defaults
- **Existing data:** No breaking changes to task/project JSON schema

### Testing Strategy
- **Unit tests:** Markdown parsing, sync status logic
- **Manual testing:** Full user flows for each feature
- **Performance testing:** Large repos (1000+ tasks), long markdown docs
- **Edge cases:** Empty states, error conditions, network failures

### Accessibility
- **Keyboard navigation:** All features usable without mouse
- **VoiceOver:** Proper labels for new UI elements
- **High contrast:** Use semantic colors from Theme.swift
- **Dynamic type:** Support system font size preferences

---

## Appendix A: Design Mockups

*Note: Mockups to be added by designer. Placeholders below indicate needed mockups.*

### Mockup 1: Sync Status Toolbar Integration
- Show sync status view in toolbar
- States: Synced (green), Syncing (blue), Error (red)
- Popover expanded view

### Mockup 2: Inbox Card Layout
- Card-based list view
- Category badges
- Bulk actions toolbar

### Mockup 3: Markdown Split Editor
- Side-by-side edit/preview
- Formatting toolbar
- View mode toggle

### Mockup 4: Keyboard Shortcuts Panel
- Categorized list
- Search bar
- Organized layout

---

## Appendix B: Related Documentation

- `COMMAND_PALETTE.md` — Command palette features and usage
- `PERFORMANCE_FIXES.md` — Background loading and async patterns
- `SETTINGS_MIGRATION.md` — Config management patterns
- `README.md` — App architecture and data flow

---

## Appendix C: Open Questions

1. **Markdown flavor:** GitHub-flavored vs. CommonMark? (Recommendation: GFM for task lists)
2. **Sync frequency:** Should we add manual control over auto-sync interval in settings?
3. **Inbox categories:** Manually assigned or auto-detected from metadata?
4. **Keyboard customization:** Allow users to remap shortcuts? (Future consideration)

---

## Revision History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-02-11 | Initial design complete | Programmer Agent |

---

**Next Steps:**
1. Review plan with project owner (Rafe)
2. Prioritize tasks based on feedback
3. Create GitHub issues for each implementation task
4. Begin Phase 1 implementation
