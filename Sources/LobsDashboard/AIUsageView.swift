import SwiftUI

private typealias ATheme = Theme

/// Cumulative/daily AI usage view combining worker runs and main session usage.
struct AIUsageView: View {
  @ObservedObject var vm: AppViewModel
  @Environment(\.dismiss) private var dismiss

  @State private var selectedRange: DateRange = .week

  enum DateRange: String, CaseIterable {
    case today = "Today"
    case week = "Week"
    case month = "Month"
    case allTime = "All Time"
  }

  // MARK: - Computed Data

  private var workerRuns: [WorkerHistoryRun] {
    vm.workerHistory?.runs ?? []
  }

  private var mainUsage: MainSessionUsage? {
    vm.mainSessionUsage
  }

  private var dateFilter: (Date) -> Bool {
    let cal = Calendar.current
    let now = Date()
    switch selectedRange {
    case .today:
      return { cal.isDateInToday($0) }
    case .week:
      let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? .distantPast
      return { $0 >= start }
    case .month:
      let start = cal.dateInterval(of: .month, for: now)?.start ?? .distantPast
      return { $0 >= start }
    case .allTime:
      return { _ in true }
    }
  }

  private var filteredWorkerRuns: [WorkerHistoryRun] {
    workerRuns.filter { run in
      guard let ended = run.endedAt else { return false }
      return dateFilter(ended)
    }
  }

  private var workerTotalCost: Double {
    filteredWorkerRuns.reduce(0.0) { $0 + ($1.totalCostUSD ?? 0) }
  }

  private var workerTotalTokens: Int {
    filteredWorkerRuns.reduce(0) { $0 + ($1.totalTokens ?? (($1.inputTokens ?? 0) + ($1.outputTokens ?? 0))) }
  }

  private var workerInputTokens: Int {
    filteredWorkerRuns.reduce(0) { $0 + ($1.inputTokens ?? 0) }
  }

  private var workerOutputTokens: Int {
    filteredWorkerRuns.reduce(0) { $0 + ($1.outputTokens ?? 0) }
  }

  /// Main session cost for the selected period, derived from daily summaries.
  private var mainSessionCost: Double {
    guard let usage = mainUsage else { return 0 }
    return filteredDailySummaries(from: usage.dailySummaries).values.reduce(0.0) { $0 + $1.costUSD }
  }

  private var mainSessionTokens: Int {
    guard let usage = mainUsage else { return 0 }
    return filteredDailySummaries(from: usage.dailySummaries).values.reduce(0) { $0 + $1.inputTokens + $1.outputTokens }
  }

  private var mainSessionInputTokens: Int {
    guard let usage = mainUsage else { return 0 }
    return filteredDailySummaries(from: usage.dailySummaries).values.reduce(0) { $0 + $1.inputTokens }
  }

  private var mainSessionOutputTokens: Int {
    guard let usage = mainUsage else { return 0 }
    return filteredDailySummaries(from: usage.dailySummaries).values.reduce(0) { $0 + $1.outputTokens }
  }

  private var totalCost: Double { workerTotalCost + mainSessionCost }
  private var totalTokens: Int { workerTotalTokens + mainSessionTokens }

  /// Daily cost data combining worker + main session.
  private var dailyCosts: [DailyUsagePoint] {
    var byDay: [String: (worker: Double, main: Double, workerTokens: Int, mainTokens: Int)] = [:]

    // Worker runs grouped by day
    for run in filteredWorkerRuns {
      guard let ended = run.endedAt else { continue }
      let day = dayKey(ended)
      byDay[day, default: (0, 0, 0, 0)].worker += run.totalCostUSD ?? 0
      byDay[day, default: (0, 0, 0, 0)].workerTokens += run.totalTokens ?? 0
    }

    // Main session daily summaries
    if let usage = mainUsage {
      for (day, summary) in filteredDailySummaries(from: usage.dailySummaries) {
        byDay[day, default: (0, 0, 0, 0)].main += summary.costUSD
        byDay[day, default: (0, 0, 0, 0)].mainTokens += summary.inputTokens + summary.outputTokens
      }
    }

    return byDay.map { day, data in
      DailyUsagePoint(day: day, workerCost: data.worker, mainCost: data.main, workerTokens: data.workerTokens, mainTokens: data.mainTokens)
    }
    .sorted { $0.day < $1.day }
  }

  /// Model breakdown from worker runs.
  private var modelBreakdown: [(String, Int, Double)] {
    var byModel: [String: (tokens: Int, cost: Double)] = [:]
    for run in filteredWorkerRuns {
      let model = run.model ?? "unknown"
      let tokens = run.totalTokens ?? 0
      let cost = run.totalCostUSD ?? 0
      byModel[model, default: (0, 0)].tokens += tokens
      byModel[model, default: (0, 0)].cost += cost
    }
    // Add main session (always opus for now)
    if mainSessionTokens > 0 {
      byModel["claude-opus-4-5 (main)", default: (0, 0)].tokens += mainSessionTokens
      byModel["claude-opus-4-5 (main)", default: (0, 0)].cost += mainSessionCost
    }
    return byModel.map { ($0.key, $0.value.tokens, $0.value.cost) }
      .sorted { $0.2 > $1.2 }
  }

  // MARK: - Helpers

  private func dayKey(_ date: Date) -> String {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    df.timeZone = TimeZone(identifier: "America/New_York")
    return df.string(from: date)
  }

  private func filteredDailySummaries(from summaries: [String: MainSessionDailySummary]) -> [String: MainSessionDailySummary] {
    let cal = Calendar.current
    let now = Date()
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    df.timeZone = TimeZone(identifier: "America/New_York")

    return summaries.filter { day, _ in
      guard let date = df.date(from: day) else { return false }
      return dateFilter(date)
    }
  }

  private func shortDay(_ day: String) -> String {
    // "2026-02-03" → "Feb 3"
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    guard let date = df.date(from: day) else { return day }
    let out = DateFormatter()
    out.dateFormat = "MMM d"
    return out.string(from: date)
  }

  // MARK: - Body

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        // Header
        HStack(spacing: 12) {
          Image(systemName: "chart.line.uptrend.xyaxis")
            .font(.title)
            .foregroundStyle(.linearGradient(
              colors: [.purple, .pink],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ))
          Text("AI Usage")
            .font(.title)
            .fontWeight(.bold)

          Spacer()

          Picker("Period", selection: $selectedRange) {
            ForEach(DateRange.allCases, id: \.self) { r in
              Text(r.rawValue).tag(r)
            }
          }
          .pickerStyle(.segmented)
          .frame(maxWidth: 320)
        }

        // Summary cards
        HStack(spacing: 16) {
          UsageSummaryCard(title: "Total Cost", value: String(format: "$%.2f", totalCost), icon: "dollarsign.circle.fill", color: .green,
            tooltip: "Estimated total cost based on model pricing.\nOpus: $15/$75 per 1M in/out\nSonnet: $3/$15 per 1M in/out")
          UsageSummaryCard(title: "Total Tokens", value: formatTokens(totalTokens), icon: "cpu", color: .purple,
            tooltip: "Combined input + output tokens across all sessions")
          UsageSummaryCard(title: "Worker Cost", value: String(format: "$%.2f", workerTotalCost), icon: "bolt.fill", color: .orange,
            tooltip: "Cost from task-runner sub-agents — code implementation, research, file operations")
          UsageSummaryCard(title: "Main Session", value: String(format: "$%.2f", mainSessionCost), icon: "bubble.left.fill", color: .blue,
            tooltip: "Cost from Lobs main session — heartbeat checks, conversations, task spawning and coordination")
          UsageSummaryCard(title: "Worker Runs", value: "\(filteredWorkerRuns.count)", icon: "arrow.triangle.2.circlepath", color: .indigo,
            tooltip: "Number of task-runner sub-agent sessions in this period")
        }

        // Daily usage chart
        if !dailyCosts.isEmpty {
          DailyUsageChart(data: dailyCosts, shortDay: shortDay)
        }

        HStack(alignment: .top, spacing: 24) {
          // Main vs Worker split
          UsageSplitView(
            workerCost: workerTotalCost,
            mainCost: mainSessionCost,
            workerTokens: workerTotalTokens,
            mainTokens: mainSessionTokens,
            workerInput: workerInputTokens,
            workerOutput: workerOutputTokens,
            mainInput: mainSessionInputTokens,
            mainOutput: mainSessionOutputTokens
          )

          // Model breakdown
          ModelBreakdownView(models: modelBreakdown)
        }
      }
      .padding(32)
    }
    .background(ATheme.boardBg)
  }
}

// MARK: - Data Types

private struct DailyUsagePoint: Identifiable {
  let day: String
  let workerCost: Double
  let mainCost: Double
  let workerTokens: Int
  let mainTokens: Int

  var totalCost: Double { workerCost + mainCost }
  var totalTokens: Int { workerTokens + mainTokens }
  var id: String { day }
}

// MARK: - Summary Card

private struct UsageSummaryCard: View {
  let title: String
  let value: String
  let icon: String
  let color: Color
  var tooltip: String? = nil

  var body: some View {
    VStack(spacing: 10) {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .font(.system(size: 12))
          .foregroundStyle(color)
        Text(title)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.secondary)
        if tooltip != nil {
          Image(systemName: "info.circle")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        }
      }
      Text(value)
        .font(.title2)
        .fontWeight(.bold)
        .foregroundStyle(color)
    }
    .frame(minWidth: 130, maxWidth: .infinity)
    .padding(.horizontal, 18)
    .padding(.vertical, 16)
    .help(tooltip ?? "")
    .background(ATheme.cardBg)
    .clipShape(RoundedRectangle(cornerRadius: ATheme.cardRadius))
    .overlay(
      RoundedRectangle(cornerRadius: ATheme.cardRadius)
        .stroke(ATheme.border, lineWidth: 0.5)
    )
  }
}

// MARK: - Daily Usage Chart

private struct DailyUsageChart: View {
  let data: [DailyUsagePoint]
  let shortDay: (String) -> String

  private var maxCost: Double {
    max(data.map(\.totalCost).max() ?? 1, 0.01)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      SectionHeaderWithInfo(
        title: "Daily Spend",
        tooltip: "Daily cost breakdown showing Main Session (blue) and Worker (orange) spending. Stacked bars show relative proportions."
      )

      // Stacked bar chart
      HStack(alignment: .bottom, spacing: max(3, 10 - CGFloat(data.count) / 4)) {
        ForEach(data) { point in
          VStack(spacing: 5) {
            // Cost label
            if point.totalCost > 0 {
              Text(String(format: "$%.2f", point.totalCost))
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
            }

            // Stacked bar
            VStack(spacing: 0) {
              // Main session (top, blue)
              if point.mainCost > 0 {
                RoundedRectangle(cornerRadius: 3)
                  .fill(Color.blue.opacity(0.7))
                  .frame(height: max(3, CGFloat(point.mainCost / maxCost) * 180))
              }
              // Worker (bottom, orange)
              if point.workerCost > 0 {
                RoundedRectangle(cornerRadius: 3)
                  .fill(Color.orange.opacity(0.7))
                  .frame(height: max(3, CGFloat(point.workerCost / maxCost) * 180))
              }
            }
            .frame(maxWidth: 48)

            // Day label
            Text(shortDay(point.day))
              .font(.system(size: 10))
              .foregroundStyle(.tertiary)
          }
          .frame(minWidth: 36, maxWidth: .infinity)
        }
      }
      .frame(minHeight: 220)
      .padding(.horizontal, 10)

      // Legend
      HStack(spacing: 20) {
        HStack(spacing: 6) {
          RoundedRectangle(cornerRadius: 3)
            .fill(Color.orange.opacity(0.7))
            .frame(width: 14, height: 14)
          Text("Worker")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        HStack(spacing: 6) {
          RoundedRectangle(cornerRadius: 3)
            .fill(Color.blue.opacity(0.7))
            .frame(width: 14, height: 14)
          Text("Main Session")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.leading, 10)
    }
    .padding(20)
    .background(ATheme.cardBg)
    .clipShape(RoundedRectangle(cornerRadius: ATheme.cardRadius))
    .overlay(
      RoundedRectangle(cornerRadius: ATheme.cardRadius)
        .stroke(ATheme.border, lineWidth: 0.5)
    )
  }
}

// MARK: - Usage Split View

private struct UsageSplitView: View {
  let workerCost: Double
  let mainCost: Double
  let workerTokens: Int
  let mainTokens: Int
  let workerInput: Int
  let workerOutput: Int
  let mainInput: Int
  let mainOutput: Int

  private var total: Double { workerCost + mainCost }
  private var workerPct: Double { total > 0 ? workerCost / total : 0 }
  private var mainPct: Double { total > 0 ? mainCost / total : 0 }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      SectionHeaderWithInfo(
        title: "Usage Breakdown",
        tooltip: "Main Session: Lobs heartbeat checks, conversations, task spawning and coordination.\nWorkers: Task-runner sub-agents that handle code implementation, research, and file operations."
      )

      if total > 0 {
        // Proportional cost bar
        GeometryReader { geo in
          HStack(spacing: 1) {
            RoundedRectangle(cornerRadius: 4)
              .fill(Color.blue.opacity(0.7))
              .frame(width: max(4, geo.size.width * mainPct))
            RoundedRectangle(cornerRadius: 4)
              .fill(Color.orange.opacity(0.7))
              .frame(width: max(4, geo.size.width * workerPct))
          }
        }
        .frame(height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 6))

        // Two side-by-side cards for Main and Worker
        HStack(alignment: .top, spacing: 14) {
          // Main Session card
          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
              Image(systemName: "bubble.left.fill")
                .font(.system(size: 12))
                .foregroundStyle(.blue)
              Text("Main Session")
                .font(.system(size: 13, weight: .semibold))
            }
            Text("Heartbeats, conversations, task spawning")
              .font(.system(size: 10))
              .foregroundStyle(.tertiary)
              .lineLimit(2)

            Divider()

            VStack(alignment: .leading, spacing: 3) {
              Text(String(format: "$%.2f", mainCost))
                .font(.title3.monospacedDigit())
                .fontWeight(.bold)
                .foregroundStyle(.blue)
              Text(String(format: "%.0f%% of total", mainPct * 100))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
              Text("\(formatTokens(mainTokens)) tokens")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.tertiary)
              Text("\(formatTokens(mainInput)) in / \(formatTokens(mainOutput)) out")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.tertiary)
            }
          }
          .padding(14)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.blue.opacity(0.04))
          .clipShape(RoundedRectangle(cornerRadius: 10))
          .overlay(
            RoundedRectangle(cornerRadius: 10)
              .stroke(Color.blue.opacity(0.15), lineWidth: 1)
          )

          // Worker card
          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
              Image(systemName: "bolt.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
              Text("Workers")
                .font(.system(size: 13, weight: .semibold))
            }
            Text("Task-runner sub-agents, code & research")
              .font(.system(size: 10))
              .foregroundStyle(.tertiary)
              .lineLimit(2)

            Divider()

            VStack(alignment: .leading, spacing: 3) {
              Text(String(format: "$%.2f", workerCost))
                .font(.title3.monospacedDigit())
                .fontWeight(.bold)
                .foregroundStyle(.orange)
              Text(String(format: "%.0f%% of total", workerPct * 100))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
              Text("\(formatTokens(workerTokens)) tokens")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.tertiary)
              Text("\(formatTokens(workerInput)) in / \(formatTokens(workerOutput)) out")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.tertiary)
            }
          }
          .padding(14)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.orange.opacity(0.04))
          .clipShape(RoundedRectangle(cornerRadius: 10))
          .overlay(
            RoundedRectangle(cornerRadius: 10)
              .stroke(Color.orange.opacity(0.15), lineWidth: 1)
          )
        }
      } else {
        Text("No usage data yet")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .padding(.vertical, 8)
      }
    }
    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    .padding(20)
    .background(ATheme.cardBg)
    .clipShape(RoundedRectangle(cornerRadius: ATheme.cardRadius))
    .overlay(
      RoundedRectangle(cornerRadius: ATheme.cardRadius)
        .stroke(ATheme.border, lineWidth: 0.5)
    )
  }
}

// MARK: - Model Breakdown View

private struct ModelBreakdownView: View {
  let models: [(String, Int, Double)]

  private var maxCost: Double {
    max(models.map(\.2).max() ?? 1, 0.01)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      SectionHeaderWithInfo(
        title: "By Model",
        tooltip: "Token usage and estimated cost broken down by AI model.\nOpus: $15/$75 per 1M input/output tokens\nSonnet: $3/$15 per 1M input/output tokens"
      )

      if models.isEmpty {
        Text("No model data yet")
          .font(.footnote)
          .foregroundStyle(.secondary)
      } else {
        ForEach(models, id: \.0) { model, tokens, cost in
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(model)
                .font(.footnote)
                .fontWeight(.medium)
                .lineLimit(1)
              Spacer()
              Text(String(format: "$%.2f", cost))
                .font(.footnote.monospacedDigit())
                .fontWeight(.medium)
            }
            HStack(spacing: 8) {
              GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                  .fill(modelColor(model).opacity(0.5))
                  .frame(width: max(4, geo.size.width * CGFloat(cost / maxCost)))
              }
              .frame(height: 8)

              Text(formatTokens(tokens))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 50, alignment: .trailing)
            }
          }
          if model != models.last?.0 {
            Divider()
          }
        }
      }
    }
    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    .padding(20)
    .background(ATheme.cardBg)
    .clipShape(RoundedRectangle(cornerRadius: ATheme.cardRadius))
    .overlay(
      RoundedRectangle(cornerRadius: ATheme.cardRadius)
        .stroke(ATheme.border, lineWidth: 0.5)
    )
  }

  private func modelColor(_ model: String) -> Color {
    if model.contains("opus") { return .purple }
    if model.contains("sonnet") { return .blue }
    if model.contains("haiku") { return .green }
    if model.contains("gpt") { return .orange }
    return .gray
  }
}

// MARK: - Section Header With Info Tooltip

private struct SectionHeaderWithInfo: View {
  let title: String
  let tooltip: String

  @State private var showingPopover = false

  var body: some View {
    HStack(spacing: 6) {
      Text(title)
        .font(.headline)
        .fontWeight(.bold)

      Button {
        showingPopover.toggle()
      } label: {
        Image(systemName: "info.circle")
          .font(.system(size: 12))
          .foregroundStyle(.tertiary)
      }
      .buttonStyle(.plain)
      .help(tooltip)
      .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
        Text(tooltip)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .padding(12)
          .frame(maxWidth: 300)
      }
    }
  }
}

// MARK: - Token Formatter

private func formatTokens(_ count: Int) -> String {
  if count >= 1_000_000 {
    return String(format: "%.1fM", Double(count) / 1_000_000)
  } else if count >= 1_000 {
    return String(format: "%.0fK", Double(count) / 1_000)
  }
  return "\(count)"
}
