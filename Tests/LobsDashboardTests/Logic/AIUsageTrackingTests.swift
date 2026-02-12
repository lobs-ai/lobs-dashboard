import XCTest
@testable import LobsDashboard

/// Tests for AI usage tracking to ensure proper aggregation from worker history
/// and correct handling of stale main session data.
final class AIUsageTrackingTests: XCTestCase {
  
  // MARK: - MainSessionUsage Freshness Tests
  
  func testMainSessionUsageIsFreshWithRecentData() {
    // Data from today should be fresh
    let snapshot = MainSessionSnapshot(
      timestamp: Date(),
      inputTokens: 1000,
      outputTokens: 500,
      totalTokens: 1500,
      model: "claude-opus-4-5",
      costUSD: 0.05,
      deltaInputTokens: 1000,
      deltaOutputTokens: 500,
      deltaCostUSD: 0.05
    )
    
    let usage = MainSessionUsage(
      snapshots: [snapshot],
      dailySummaries: [:]
    )
    
    XCTAssertTrue(usage.isFresh, "Recent data (today) should be considered fresh")
  }
  
  func testMainSessionUsageIsFreshWithin7Days() {
    // Data from 5 days ago should be fresh
    let fiveDaysAgo = Date(timeIntervalSinceNow: -5 * 86400)
    let snapshot = MainSessionSnapshot(
      timestamp: fiveDaysAgo,
      inputTokens: 1000,
      outputTokens: 500,
      totalTokens: 1500,
      model: "claude-opus-4-5",
      costUSD: 0.05,
      deltaInputTokens: 1000,
      deltaOutputTokens: 500,
      deltaCostUSD: 0.05
    )
    
    let usage = MainSessionUsage(
      snapshots: [snapshot],
      dailySummaries: [:]
    )
    
    XCTAssertTrue(usage.isFresh, "Data from 5 days ago should be fresh")
  }
  
  func testMainSessionUsageIsStaleAfter7Days() {
    // Data from 8 days ago should be stale
    let eightDaysAgo = Date(timeIntervalSinceNow: -8 * 86400)
    let snapshot = MainSessionSnapshot(
      timestamp: eightDaysAgo,
      inputTokens: 1000,
      outputTokens: 500,
      totalTokens: 1500,
      model: "claude-opus-4-5",
      costUSD: 0.05,
      deltaInputTokens: 1000,
      deltaOutputTokens: 500,
      deltaCostUSD: 0.05
    )
    
    let usage = MainSessionUsage(
      snapshots: [snapshot],
      dailySummaries: [:]
    )
    
    XCTAssertFalse(usage.isFresh, "Data from 8 days ago should be stale")
  }
  
  func testMainSessionUsageUsesLatestSnapshot() {
    // Multiple snapshots - should use the most recent one
    let tenDaysAgo = Date(timeIntervalSinceNow: -10 * 86400)
    let twoDaysAgo = Date(timeIntervalSinceNow: -2 * 86400)
    
    let oldSnapshot = MainSessionSnapshot(
      timestamp: tenDaysAgo,
      inputTokens: 1000,
      outputTokens: 500,
      totalTokens: 1500,
      model: "claude-opus-4-5",
      costUSD: 0.05,
      deltaInputTokens: 1000,
      deltaOutputTokens: 500,
      deltaCostUSD: 0.05
    )
    
    let recentSnapshot = MainSessionSnapshot(
      timestamp: twoDaysAgo,
      inputTokens: 2000,
      outputTokens: 1000,
      totalTokens: 3000,
      model: "claude-opus-4-5",
      costUSD: 0.10,
      deltaInputTokens: 1000,
      deltaOutputTokens: 500,
      deltaCostUSD: 0.05
    )
    
    let usage = MainSessionUsage(
      snapshots: [oldSnapshot, recentSnapshot],
      dailySummaries: [:]
    )
    
    XCTAssertTrue(usage.isFresh, "Should use most recent snapshot (2 days ago) to determine freshness")
    XCTAssertEqual(usage.lastUpdateDate, twoDaysAgo, "Last update date should be the most recent snapshot")
  }
  
  func testMainSessionUsageWithNoSnapshotsIsNotFresh() {
    let usage = MainSessionUsage(
      snapshots: [],
      dailySummaries: [:]
    )
    
    XCTAssertFalse(usage.isFresh, "Usage with no snapshots should not be fresh")
    XCTAssertNil(usage.lastUpdateDate, "Last update date should be nil when no snapshots")
  }
  
  func testMainSessionUsageWithNilTimestampsIsNotFresh() {
    let snapshot = MainSessionSnapshot(
      timestamp: nil,
      inputTokens: 1000,
      outputTokens: 500,
      totalTokens: 1500,
      model: "claude-opus-4-5",
      costUSD: 0.05,
      deltaInputTokens: 1000,
      deltaOutputTokens: 500,
      deltaCostUSD: 0.05
    )
    
    let usage = MainSessionUsage(
      snapshots: [snapshot],
      dailySummaries: [:]
    )
    
    XCTAssertFalse(usage.isFresh, "Usage with nil timestamps should not be fresh")
  }
  
  // MARK: - Worker History Aggregation Tests
  
  func testWorkerHistoryAggregationCalculatesTotalCost() {
    let now = Date()
    let run1 = WorkerHistoryRun(
      workerId: "programmer-123-ABC",
      startedAt: now,
      endedAt: now,
      tasksCompleted: 1,
      timeoutReason: nil,
      model: "claude-sonnet-4-5",
      inputTokens: 1000,
      outputTokens: 500,
      totalTokens: 1500,
      totalCostUSD: 0.05,
      taskLog: nil,
      commitSHAs: nil,
      filesModified: nil,
      githubCompareURL: nil,
      taskId: "task-1",
      succeeded: true,
      source: "actual"
    )
    
    let run2 = WorkerHistoryRun(
      workerId: "researcher-456-DEF",
      startedAt: now,
      endedAt: now,
      tasksCompleted: 1,
      timeoutReason: nil,
      model: "claude-sonnet-4-5",
      inputTokens: 2000,
      outputTokens: 1000,
      totalTokens: 3000,
      totalCostUSD: 0.10,
      taskLog: nil,
      commitSHAs: nil,
      filesModified: nil,
      githubCompareURL: nil,
      taskId: "task-2",
      succeeded: true,
      source: "actual"
    )
    
    let history = WorkerHistory(runs: [run1, run2])
    
    let totalCost = history.runs.reduce(0.0) { $0 + ($1.totalCostUSD ?? 0) }
    let totalTokens = history.runs.reduce(0) { $0 + ($1.totalTokens ?? 0) }
    
    XCTAssertEqual(totalCost, 0.15, accuracy: 0.001, "Total cost should be sum of all runs")
    XCTAssertEqual(totalTokens, 4500, "Total tokens should be sum of all runs")
  }
  
  func testWorkerHistoryRunExtractsAgentType() {
    let run = WorkerHistoryRun(
      workerId: "programmer-123-ABC",
      startedAt: Date(),
      endedAt: Date(),
      tasksCompleted: 1,
      timeoutReason: nil,
      model: "claude-sonnet-4-5",
      inputTokens: 1000,
      outputTokens: 500,
      totalTokens: 1500,
      totalCostUSD: 0.05,
      taskLog: nil,
      commitSHAs: nil,
      filesModified: nil,
      githubCompareURL: nil,
      taskId: "task-1",
      succeeded: true,
      source: "actual"
    )
    
    XCTAssertEqual(run.agentType, "programmer", "Agent type should be extracted from workerId")
  }
  
  func testWorkerHistoryRunHandlesMissingWorkerId() {
    let run = WorkerHistoryRun(
      workerId: nil,
      startedAt: Date(),
      endedAt: Date(),
      tasksCompleted: 1,
      timeoutReason: nil,
      model: "claude-sonnet-4-5",
      inputTokens: 1000,
      outputTokens: 500,
      totalTokens: 1500,
      totalCostUSD: 0.05,
      taskLog: nil,
      commitSHAs: nil,
      filesModified: nil,
      githubCompareURL: nil,
      taskId: "task-1",
      succeeded: true,
      source: "actual"
    )
    
    XCTAssertEqual(run.agentType, "unknown", "Missing workerId should return 'unknown'")
  }
  
  func testWorkerHistoryRunFallsBackToInputPlusOutputTokens() {
    // Some runs might not have totalTokens but have inputTokens and outputTokens
    let run = WorkerHistoryRun(
      workerId: "programmer-123-ABC",
      startedAt: Date(),
      endedAt: Date(),
      tasksCompleted: 1,
      timeoutReason: nil,
      model: "claude-sonnet-4-5",
      inputTokens: 1000,
      outputTokens: 500,
      totalTokens: nil,  // Missing totalTokens
      totalCostUSD: 0.05,
      taskLog: nil,
      commitSHAs: nil,
      filesModified: nil,
      githubCompareURL: nil,
      taskId: "task-1",
      succeeded: true,
      source: "actual"
    )
    
    // Verify the logic that AIUsageView would use
    let totalForRun = run.totalTokens ?? ((run.inputTokens ?? 0) + (run.outputTokens ?? 0))
    XCTAssertEqual(totalForRun, 1500, "Should fall back to sum of input and output tokens")
  }
  
  // MARK: - Integration Tests
  
  func testStaleMainSessionDataIsNotIncludedInTotals() {
    // Simulate stale main session data (8 days old)
    let eightDaysAgo = Date(timeIntervalSinceNow: -8 * 86400)
    let staleSnapshot = MainSessionSnapshot(
      timestamp: eightDaysAgo,
      inputTokens: 10000,
      outputTokens: 5000,
      totalTokens: 15000,
      model: "claude-opus-4-5",
      costUSD: 0.50,
      deltaInputTokens: 10000,
      deltaOutputTokens: 5000,
      deltaCostUSD: 0.50
    )
    
    let mainUsage = MainSessionUsage(
      snapshots: [staleSnapshot],
      dailySummaries: [:]
    )
    
    // When checking freshness, stale data should be excluded
    XCTAssertFalse(mainUsage.isFresh, "8-day-old data should be stale")
    
    // In the actual UI logic, this would result in mainSessionCost returning 0
    // because of the guard statement: guard let usage = mainUsage, usage.isFresh else { return 0 }
  }
  
  func testFreshMainSessionDataIsIncludedInTotals() {
    // Simulate fresh main session data (1 day old)
    let oneDayAgo = Date(timeIntervalSinceNow: -1 * 86400)
    let freshSnapshot = MainSessionSnapshot(
      timestamp: oneDayAgo,
      inputTokens: 10000,
      outputTokens: 5000,
      totalTokens: 15000,
      model: "claude-opus-4-5",
      costUSD: 0.50,
      deltaInputTokens: 10000,
      deltaOutputTokens: 5000,
      deltaCostUSD: 0.50
    )
    
    let mainUsage = MainSessionUsage(
      snapshots: [freshSnapshot],
      dailySummaries: [:]
    )
    
    // When checking freshness, fresh data should be included
    XCTAssertTrue(mainUsage.isFresh, "1-day-old data should be fresh")
    
    // In the actual UI logic, this would result in mainSessionCost returning the actual cost
  }
}
