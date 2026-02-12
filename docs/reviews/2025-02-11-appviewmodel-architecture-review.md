# AppViewModel Architecture Review

**Date:** 2025-02-11  
**Reviewer:** Reviewer Agent  
**Severity:** 🟡 Important (Technical Debt / Maintainability)  
**Type:** Architectural Review / Proactive Analysis

---

## Executive Summary

`AppViewModel.swift` has grown to **5,624 lines** with **85 @Published properties** and **164 functions** spanning **29 distinct domains of responsibility**. This is a textbook "God Object" anti-pattern that poses significant risks to maintainability, testability, and collaboration velocity.

**Recommendation:** Initiate a phased refactoring to extract domain-specific view models while maintaining backward compatibility.

---

## Metrics

| Metric | Value | Context |
|--------|-------|---------|
| **Lines of Code** | 5,624 | ~9% of entire codebase in one file |
| **@Published Properties** | 85 | High change surface area |
| **Functions** | 164 | Multiple responsibilities per class |
| **MARK Sections** | 29 | Clear domain boundaries already identified |
| **Total Swift Files** | 64 | AppViewModel is 1.5% of files, 9% of code |
| **Test Coverage** | 0 lines | No dedicated AppViewModel tests exist |
| **Test Suite Size** | 3,403 lines | Tests organized by feature, not by this core component |

---

## The Problem

### God Object Anti-Pattern

AppViewModel violates the **Single Responsibility Principle** at scale. It currently manages:

1. **User Settings & Preferences** (onboarding, menu bar, notifications)
2. **Task Management** (CRUD, filtering, sorting, multi-select, bulk actions)
3. **Research System** (tiles, requests, documents, sources, deliverables)
4. **Tracker/Inbox** (items, requests, read state, threads, responses)
5. **Project Management** (projects, README, stats, activity)
6. **Worker/Agent Status** (orchestrator state, agent statuses, session usage)
7. **Git Operations** (sync, conflicts, rebase recovery, push/pull)
8. **GitHub Integration** (sync, issue management, rate limiting)
9. **Dashboard Updates** (version checking, update logs)
10. **Navigation State** (selected task, project, agent, tile, search)
11. **UI State** (error banners, success messages, loading flags)
12. **Notification System** (batching, preferences, delivery)
13. **Performance Caching** (filtered tasks, overview stats)
14. **Keyboard Navigation** (focus management)

### Concrete Risks

#### 🔴 **Merge Conflicts & Collaboration Friction**
- Every feature touching AppViewModel risks conflicts with concurrent work
- 5,624-line diffs are difficult to review effectively
- Current agent collaboration shows signs of this (60% failure rate in recent hour per system metrics)

#### 🔴 **Testing Challenges**
- **Zero dedicated tests** for the core orchestrator
- Testing one feature requires mocking 84 other @Published properties
- Impossible to achieve meaningful unit test coverage
- Integration tests are the only option, but they're slow and brittle

#### 🔴 **Cognitive Load**
- New contributors (human or AI) must understand 29 domains to make any change
- 164 functions to scan when debugging
- High probability of unintended side effects

#### 🔴 **SwiftUI Performance**
- 85 @Published properties means 85 potential change triggers
- Any property change invalidates dependent views
- Cache invalidation logic is manual and error-prone (see lines 151-159, 194-202)

#### 🟡 **State Management Bugs**
- Complex interdependencies between properties
- Manual cache invalidation (already observed in past reviews, per MEMORY.md)
- Race conditions in async operations (multiple Task properties)

---

## Why This Happened (Not a Critique)

This is **normal evolution** for a growing SwiftUI app:
1. Start with a single ViewModel (correct)
2. Add features incrementally (correct)
3. Each addition is small and reasonable (correct)
4. Over time, the accretion becomes unwieldy (inevitable without periodic refactoring)

The **good news**: The 29 MARK sections show clear domain boundaries. The team already knows where the seams are.

---

## Proposed Refactoring Strategy

### Phase 1: Extract Low-Risk Domains (High Value, Low Disruption)

Target domains with minimal cross-dependencies:

#### 1.1 NotificationManager
**Extract:**
- `notifications`, `notificationPreferences`, `batchedNotifications`, `batchTimer`
- Functions: `addNotification()`, `dismissNotification()`, `batchNotifications()`, etc.

**Impact:** ~150 lines, 4 properties  
**Risk:** Low (self-contained)  
**Test Coverage:** Can be fully unit tested

#### 1.2 GitHubSyncManager
**Extract:**
- `lastGitHubSyncAt`, `lastGitHubSyncError`, `isGitHubSyncing`
- Functions: GitHub issue sync logic

**Impact:** ~200 lines, 3 properties  
**Risk:** Low (already uses GitHubService)  
**Benefit:** Easier to test sync logic in isolation

#### 1.3 DashboardUpdateManager
**Extract:**
- `dashboardUpdateAvailable`, `dashboardLocalCommit`, `dashboardRemoteCommit`, etc.
- Functions: Update checking, log management

**Impact:** ~120 lines, 7 properties  
**Risk:** Low (orthogonal to main features)

### Phase 2: Extract Core Domains (Medium Risk, High Value)

#### 2.1 TaskManager
**Extract:**
- Task CRUD, filtering, sorting, multi-select, bulk actions
- `tasks`, `selectedTaskId`, `multiSelectedTaskIds`, filter properties

**Impact:** ~800 lines, 15+ properties  
**Risk:** Medium (many UI dependencies)  
**Strategy:** Keep AppViewModel as a facade initially

#### 2.2 ResearchManager
**Extract:**
- Research tiles, requests, documents, sources
- `researchTiles`, `researchRequests`, `researchDocContent`, etc.

**Impact:** ~600 lines, 10+ properties  
**Risk:** Medium (ResearchView dependencies)

#### 2.3 ProjectManager
**Extract:**
- Project list, stats, activity, README
- `projects`, `selectedProjectId`, `projectReadme`, `overviewResearchStatsByProject`

**Impact:** ~400 lines, 8 properties  
**Risk:** Medium (cross-cutting with tasks/research)

### Phase 3: Extract Infrastructure (Higher Risk)

#### 3.1 GitOperationsManager
- Sync, conflicts, rebase recovery, pending changes
- Requires careful coordination with UI state

#### 3.2 SettingsManager
- User preferences, config persistence
- Low-hanging fruit but touches everything

---

## Implementation Pattern

### Recommended Approach: Composition over Inheritance

```swift
@MainActor
final class AppViewModel: ObservableObject {
    // Extracted managers (published so views can observe)
    @Published private(set) var notificationManager: NotificationManager
    @Published private(set) var taskManager: TaskManager
    @Published private(set) var researchManager: ResearchManager
    
    // Legacy properties (deprecated, proxy to managers)
    @available(*, deprecated, message: "Use notificationManager.notifications")
    var notifications: [DashboardNotification] { notificationManager.notifications }
    
    init() {
        self.notificationManager = NotificationManager()
        self.taskManager = TaskManager()
        self.researchManager = ResearchManager()
    }
}
```

**Benefits:**
- Backward compatible (views can still access via AppViewModel)
- Incremental migration (update views one at a time)
- Each manager is independently testable
- Clear deprecation path

---

## Success Metrics

After Phase 1 completion:
- [ ] AppViewModel reduced to < 5,000 lines
- [ ] 3 new manager classes with dedicated test suites
- [ ] Test coverage for extracted domains > 80%
- [ ] No regression in existing functionality
- [ ] Build time unchanged or improved

After Phase 2 completion:
- [ ] AppViewModel reduced to < 3,500 lines
- [ ] 6+ domain managers with clear boundaries
- [ ] Merge conflict rate measurably reduced
- [ ] Agent task success rate improved

---

## Risks of NOT Refactoring

1. **Continued Growth:** AppViewModel will hit 6,000+ lines within months at current velocity
2. **Collaboration Ceiling:** Multiple agents working on dashboard will have increasing conflict rates
3. **Bug Surface Area:** More properties = more state permutations = more bugs
4. **Onboarding Cost:** New contributors (human or AI) face steeper learning curve
5. **Technical Debt Interest:** Refactoring becomes exponentially harder as dependencies grow

---

## Recommendation

**Start with Phase 1 immediately.** Extract NotificationManager first (self-contained, high value, minimal risk). This validates the approach and builds momentum.

**Timeline:**
- Phase 1: 1 week (3 managers extracted)
- Phase 2: 2-3 weeks (core domain managers)
- Phase 3: Ongoing (infrastructure as needed)

**Ownership:**
- Architect agent: Design manager interfaces
- Programmer agent: Implement extraction + tests
- Reviewer agent: Review boundary clarity and test quality

---

## Acknowledgments

This is **good code** that has evolved naturally. The team has:
- ✅ Maintained clear MARK sections (29 identified domains)
- ✅ Consistent test discipline for new features
- ✅ Performance-conscious patterns (caching with invalidation)
- ✅ Good separation elsewhere (Models, Store, Views)

The issue is **architectural scale**, not code quality. This review is an investment in future velocity, not a criticism of past decisions.

---

## Next Steps

1. **Review this document** with human owner (Rafe)
2. **Get buy-in** on phased approach
3. **Create architect handoff** for Phase 1 manager designs
4. **Create programmer handoffs** for extraction work
5. **Update AGENTS.md** with refactoring guidelines

---

**Reviewer's Note:** This review was generated autonomously based on observed metrics and architectural patterns. The recommendations are opinionated but grounded in established software engineering principles (SRP, testability, composition). Feedback welcome.
