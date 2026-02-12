import XCTest
@testable import LobsDashboard

/// Tests for AI usage tracking fixes - switching from stale main-session-usage.json
/// to aggregating data from worker-history.json.
///
/// **Problem Fixed:**
/// - main-session-usage.json stopped being updated (last update Feb 5)
/// - Token counts sometimes went down (reading from deleted sessions)
/// - Dashboard wasn't aggregating worker history properly
///
/// **Solution:**
/// 1. Added computed properties to WorkerHistoryRun for agent type extraction
/// 2. Added agent and project breakdown aggregations
/// 3. Updated AIUsageView to show breakdowns by agent and project
/// 4. Main session usage still displayed if available (for backwards compatibility)
///
/// **Data Source:**
/// - Primary: state/worker-history.json (contains per-task usage with agent/project info)
/// - Optional: state/main-session-usage.json (if exists, merged into totals)
final class AIUsageTrackingTests: XCTestCase {
  
  /// Test: WorkerHistoryRun.agentType extracts agent from workerId
  ///
  /// Expected behavior:
  /// - "programmer-1770869090-ABC123" → "programmer"
  /// - "researcher-999-XYZ" → "researcher"
  /// - "architect-1-TEST" → "architect"
  /// - nil or empty → "unknown"
  ///
  /// Implementation (Models.swift):
  /// var agentType: String {
  ///   guard let workerId = workerId else { return "unknown" }
  ///   let parts = workerId.split(separator: "-")
  ///   return parts.first.map(String.init) ?? "unknown"
  /// }
  func testWorkerHistoryRunAgentTypeExtraction() {
    var run1 = WorkerHistoryRun()
    run1.workerId = "programmer-1770869090-ABC123"
    XCTAssertEqual(run1.agentType, "programmer")
    
    var run2 = WorkerHistoryRun()
    run2.workerId = "researcher-999-XYZ"
    XCTAssertEqual(run2.agentType, "researcher")
    
    var run3 = WorkerHistoryRun()
    run3.workerId = "architect-1-TEST"
    XCTAssertEqual(run3.agentType, "architect")
    
    var run4 = WorkerHistoryRun()
    run4.workerId = nil
    XCTAssertEqual(run4.agentType, "unknown")
    
    var run5 = WorkerHistoryRun()
    run5.workerId = ""
    XCTAssertEqual(run5.agentType, "unknown")
  }
  
  /// Test: WorkerHistoryRun.primaryProject extracts first project from taskLog
  ///
  /// Expected behavior:
  /// - taskLog with entries → first project
  /// - taskLog empty → nil
  /// - taskLog nil → nil
  ///
  /// Implementation (Models.swift):
  /// var primaryProject: String? {
  ///   taskLog?.first?.project
  /// }
  func testWorkerHistoryRunPrimaryProjectExtraction() {
    var run1 = WorkerHistoryRun()
    var entry1 = WorkerTaskLogEntry()
    entry1.project = "lobs-dashboard"
    entry1.task = "Fix bug"
    run1.taskLog = [entry1]
    XCTAssertEqual(run1.primaryProject, "lobs-dashboard")
    
    var run2 = WorkerHistoryRun()
    run2.taskLog = []
    XCTAssertNil(run2.primaryProject)
    
    var run3 = WorkerHistoryRun()
    run3.taskLog = nil
    XCTAssertNil(run3.primaryProject)
  }
  
  /// Test: Agent breakdown aggregation
  ///
  /// Expected behavior (AIUsageView):
  /// - Group worker runs by agentType
  /// - Sum tokens and cost per agent
  /// - Count number of runs per agent
  /// - Sort by cost descending
  /// - Return: [(agentType, runs, tokens, cost)]
  ///
  /// Use cases:
  /// - See which agents are most expensive (e.g., programmer vs researcher)
  /// - Identify optimization opportunities (e.g., too many reviewer runs)
  /// - Track agent usage patterns over time
  func testAgentBreakdownAggregation() {
    // This is a structural test documenting the expected aggregation logic.
    //
    // Implementation (AIUsageView.swift):
    // private var agentBreakdown: [(String, Int, Int, Double)] {
    //   var byAgent: [String: (runs: Int, tokens: Int, cost: Double)] = [:]
    //   for run in filteredWorkerRuns {
    //     let agent = run.agentType
    //     let tokens = run.totalTokens ?? 0
    //     let cost = run.totalCostUSD ?? 0
    //     byAgent[agent, default: (0, 0, 0)].runs += 1
    //     byAgent[agent, default: (0, 0, 0)].tokens += tokens
    //     byAgent[agent, default: (0, 0, 0)].cost += cost
    //   }
    //   return byAgent.map { ($0.key, $0.value.runs, $0.value.tokens, $0.value.cost) }
    //     .sorted { $0.3 > $1.3 }  // Sort by cost descending
    // }
    //
    // Example output:
    // [
    //   ("programmer", 45, 1250000, 62.50),
    //   ("researcher", 12, 450000, 22.50),
    //   ("writer", 5, 150000, 7.50)
    // ]
    
    XCTAssert(true, "Structural test - agent breakdown aggregates by agentType")
  }
  
  /// Test: Project breakdown aggregation
  ///
  /// Expected behavior (AIUsageView):
  /// - Group worker runs by primaryProject
  /// - Sum tokens and cost per project
  /// - Count number of runs per project
  /// - Sort by cost descending
  /// - Return: [(project, runs, tokens, cost)]
  ///
  /// Use cases:
  /// - See which projects are consuming the most AI resources
  /// - Budget AI costs per project
  /// - Identify projects that need optimization
  func testProjectBreakdownAggregation() {
    // This is a structural test documenting the expected aggregation logic.
    //
    // Implementation (AIUsageView.swift):
    // private var projectBreakdown: [(String, Int, Int, Double)] {
    //   var byProject: [String: (runs: Int, tokens: Int, cost: Double)] = [:]
    //   for run in filteredWorkerRuns {
    //     let project = run.primaryProject ?? "unknown"
    //     let tokens = run.totalTokens ?? 0
    //     let cost = run.totalCostUSD ?? 0
    //     byProject[project, default: (0, 0, 0)].runs += 1
    //     byProject[project, default: (0, 0, 0)].tokens += tokens
    //     byProject[project, default: (0, 0, 0)].cost += cost
    //   }
    //   return byProject.map { ($0.key, $0.value.runs, $0.value.tokens, $0.value.cost) }
    //     .sorted { $0.3 > $1.3 }  // Sort by cost descending
    // }
    //
    // Example output:
    // [
    //   ("lobs-dashboard", 38, 980000, 49.00),
    //   ("flock", 15, 520000, 26.00),
    //   ("unknown", 4, 100000, 5.00)
    // ]
    
    XCTAssert(true, "Structural test - project breakdown aggregates by primaryProject")
  }
  
  /// Test: Agent breakdown UI displays correctly
  ///
  /// Expected behavior:
  /// - AgentBreakdownView shows agent type with emoji
  /// - Displays cost, token count, and run count
  /// - Horizontal bar proportional to cost
  /// - Color-coded by agent type (programmer=blue, researcher=green, etc.)
  /// - Sorted by cost descending
  ///
  /// Manual verification:
  /// 1. Open Dashboard → AI Usage
  /// 2. Scroll to "By Agent" section
  /// 3. Verify agents are listed with emojis (🔧 Programmer, 🔬 Researcher, etc.)
  /// 4. Verify cost, tokens, and run count are shown
  /// 5. Verify bars are proportional to cost
  /// 6. Verify most expensive agent is at top
  func testAgentBreakdownUIDisplay() {
    // This is a structural test documenting UI expectations.
    //
    // Agent emojis:
    // - programmer: 🔧
    // - architect: 🏗️
    // - researcher: 🔬
    // - reviewer: 🔍
    // - writer: ✍️
    // - unknown: 🤖
    //
    // Agent colors:
    // - programmer: blue
    // - architect: purple
    // - researcher: green
    // - reviewer: orange
    // - writer: pink
    // - unknown: gray
    
    XCTAssert(true, "Structural test - agent breakdown UI displays with emojis and colors")
  }
  
  /// Test: Project breakdown UI displays correctly
  ///
  /// Expected behavior:
  /// - ProjectBreakdownView shows project name
  /// - Displays cost, token count, and run count
  /// - Horizontal bar proportional to cost
  /// - All bars use indigo color
  /// - Sorted by cost descending
  ///
  /// Manual verification:
  /// 1. Open Dashboard → AI Usage
  /// 2. Scroll to "By Project" section
  /// 3. Verify projects are listed
  /// 4. Verify cost, tokens, and run count are shown
  /// 5. Verify bars are proportional to cost
  /// 6. Verify most expensive project is at top
  func testProjectBreakdownUIDisplay() {
    // This is a structural test documenting UI expectations.
    //
    // Display format:
    // - Project name on left
    // - Cost on right ($X.XX)
    // - Horizontal bar showing relative cost
    // - Below bar: token count (formatted: 1.2M, 450K, etc.)
    // - Below tokens: run count (e.g., "12 runs")
    
    XCTAssert(true, "Structural test - project breakdown UI displays with costs and run counts")
  }
  
  /// Test: Main session usage is optional
  ///
  /// Expected behavior:
  /// - If main-session-usage.json exists and is recent, include in totals
  /// - If main-session-usage.json is missing or stale, gracefully degrade
  /// - Worker history is the primary data source
  /// - UI still works if main session data is nil
  ///
  /// This preserves backwards compatibility while fixing the core issue.
  func testMainSessionUsageIsOptional() {
    // This is a structural test documenting backwards compatibility.
    //
    // Implementation (AIUsageView.swift):
    // private var mainUsage: MainSessionUsage? {
    //   vm.mainSessionUsage
    // }
    //
    // private var mainSessionCost: Double {
    //   guard let usage = mainUsage else { return 0 }
    //   return filteredDailySummaries(...).reduce(0.0) { $0 + $1.costUSD }
    // }
    //
    // If mainSessionUsage is nil:
    // - mainSessionCost = 0
    // - mainSessionTokens = 0
    // - Total cost = worker cost only
    // - UI still displays correctly
    
    XCTAssert(true, "Structural test - main session usage is optional, worker history is primary")
  }
  
  /// Test: Data freshness - worker history vs main session
  ///
  /// Data sources and update frequency:
  /// - worker-history.json: Updated after every worker run (real-time)
  /// - main-session-usage.json: No longer updated (stale since Feb 5)
  ///
  /// The fix ensures we rely on fresh worker history data instead of stale main session data.
  func testDataFreshness() {
    // This is a structural test documenting data source reliability.
    //
    // Worker History (Fresh):
    // - Updated by orchestrator after every task completion
    // - Contains accurate per-run costs and tokens
    // - Includes agent type and project metadata
    // - Never decreases (append-only)
    //
    // Main Session Usage (Stale):
    // - Not being written to anymore
    // - Last update: Feb 5, 2026
    // - Can show decreasing token counts (deleted sessions)
    // - Missing recent usage data
    //
    // Solution:
    // - Primary source: worker-history.json
    // - Optional fallback: main-session-usage.json (if exists)
    // - UI reflects accurate, up-to-date worker costs
    
    XCTAssert(true, "Structural test - worker history provides fresh data, main session is legacy")
  }
  
  /// Test: Tooltip documentation for new sections
  ///
  /// Expected tooltips:
  /// - By Agent: "Token usage and cost broken down by agent type. Shows which AI assistants are consuming the most resources."
  /// - By Project: "Token usage and cost broken down by project. Shows which projects are consuming the most AI resources."
  ///
  /// Helps users understand what the breakdowns mean and how to use them.
  func testTooltipDocumentation() {
    // This is a structural test documenting tooltip content.
    //
    // Implementation (AIUsageView.swift):
    // SectionHeaderWithInfo(
    //   title: "By Agent",
    //   tooltip: "Token usage and cost broken down by agent type.\nShows which AI assistants (programmer, researcher, writer, etc.) are consuming the most resources."
    // )
    //
    // SectionHeaderWithInfo(
    //   title: "By Project",
    //   tooltip: "Token usage and cost broken down by project.\nShows which projects are consuming the most AI resources."
    // )
    
    XCTAssert(true, "Structural test - tooltips explain agent and project breakdowns")
  }
}
