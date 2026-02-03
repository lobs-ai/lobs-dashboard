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
      VStack(alignment: .leading, spacing: 20) {
        // Header
        HStack(spacing: 10) {
          Image(systemName: "chart.line.uptrend.xyaxis")
            .font(.title2)
            .foregroundStyle(.linearGradient(
              colors: [.purple, .pink],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ))
          Text("AI Usage")
            .font(.title2)
            .fontWeight(.bold)

          Spacer()

          Picker("Period", selection: $selectedRange) {
            ForEach(DateRange.allCases, id: \.self) { r in
              Text(r.rawValue).tag(r)
            }
          }
          .pickerStyle(.segmented)
          .frame(maxWidth: 300)
        }

        // Summary cards
        HStack(spacing: 14) {
          UsageSummaryCard(title: "Total Cost", value: String(format: "$%.2f", totalCost), icon: "dollarsign.circle.fill", color: .green)
          UsageSummaryCard(title: "Total Tokens", value: formatTokens(totalTokens), icon: "cpu", color: .purple)
          UsageSummaryCard(title: "Worker Cost", value: String(format: "$%.2f", workerTotalCost), icon: "bolt.fill", color: .orange)
          UsageSummaryCard(title: "Main Session Cost", value: String(format: "$%.2f", mainSessionCost), icon: "bubble.left.fill", color: .blue)
          UsageSummaryCard(title: "Worker Runs", value: "\(filteredWorkerRuns.count)", icon: "arrow.triangle.2.circlepath", color: .indigo)
        }

        // Daily usage chart
        if !dailyCosts.isEmpty {
          DailyUsageChart(data: dailyCosts, shortDay: shortDay)
        }

        HStack(alignment: .top, spacing: 20) {
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
      .padding(24)
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

  var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 5) {
        Image(systemName: icon)
          .font(.footnote)
          .foregroundStyle(color)
        Text(title)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      Text(value)
        .font(.title2)
        .fontWeight(.bold)
        .foregroundStyle(color)
    }
    .frame(minWidth: 120)
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
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
    VStack(alignment: .leading, spacing: 12) {
      Text("Daily Spend")
        .font(.headline)
        .fontWeight(.bold)

      // Stacked bar chart
      HStack(alignment: .bottom, spacing: max(2, 8 - CGFloat(data.count) / 4)) {
        ForEach(data) { point in
          VStack(spacing: 4) {
            // Cost label
            if point.totalCost > 0 {
              Text(String(format: "$%.2f", point.totalCost))
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
            }

            // Stacked bar
            VStack(spacing: 0) {
              // Main session (top, blue)
              if point.mainCost > 0 {
                RoundedRectangle(cornerRadius: 2)
                  .fill(Color.blue.opacity(0.7))
                  .frame(height: max(2, CGFloat(point.mainCost / maxCost) * 120))
              }
              // Worker (bottom, orange)
              if point.workerCost > 0 {
                RoundedRectangle(cornerRadius: 2)
                  .fill(Color.orange.opacity(0.7))
                  .frame(height: max(2, CGFloat(point.workerCost / maxCost) * 120))
              }
            }
            .frame(maxWidth: 40)

            // Day label
            Text(shortDay(point.day))
              .font(.system(size: 10))
              .foregroundStyle(.tertiary)
          }
          .frame(minWidth: 30, maxWidth: .infinity)
        }
      }
      .frame(minHeight: 160)
      .padding(.horizontal, 8)

      // Legend
      HStack(spacing: 16) {
        HStack(spacing: 4) {
          RoundedRectangle(cornerRadius: 2)
            .fill(Color.orange.opacity(0.7))
            .frame(width: 12, height: 12)
          Text("Worker")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        HStack(spacing: 4) {
          RoundedRectangle(cornerRadius: 2)
            .fill(Color.blue.opacity(0.7))
            .frame(width: 12, height: 12)
          Text("Main Session")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.leading, 8)
    }
    .padding(16)
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
    VStack(alignment: .leading, spacing: 14) {
      Text("Main vs Worker")
        .font(.headline)
        .fontWeight(.bold)

      if total > 0 {
        // Cost bar
        GeometryReader { geo in
          HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 4)
              .fill(Color.orange.opacity(0.7))
              .frame(width: max(4, geo.size.width * workerPct))
            RoundedRectangle(cornerRadius: 4)
              .fill(Color.blue.opacity(0.7))
              .frame(width: max(4, geo.size.width * mainPct))
          }
        }
        .frame(height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 4))

        HStack(spacing: 20) {
          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
              Circle().fill(Color.orange).frame(width: 8, height: 8)
              Text("Worker")
                .font(.footnote)
                .fontWeight(.medium)
            }
            Text(String(format: "$%.2f (%.0f%%)", workerCost, workerPct * 100))
              .font(.callout.monospacedDigit())
              .foregroundStyle(.secondary)
            Text("\(formatTokens(workerTokens)) tokens")
              .font(.footnote.monospacedDigit())
              .foregroundStyle(.tertiary)
            Text("\(formatTokens(workerInput)) in / \(formatTokens(workerOutput)) out")
              .font(.system(size: 10).monospacedDigit())
              .foregroundStyle(.tertiary)
          }

          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
              Circle().fill(Color.blue).frame(width: 8, height: 8)
              Text("Main Session")
                .font(.footnote)
                .fontWeight(.medium)
            }
            Text(String(format: "$%.2f (%.0f%%)", mainCost, mainPct * 100))
              .font(.callout.monospacedDigit())
              .foregroundStyle(.secondary)
            Text("\(formatTokens(mainTokens)) tokens")
              .font(.footnote.monospacedDigit())
              .foregroundStyle(.tertiary)
            Text("\(formatTokens(mainInput)) in / \(formatTokens(mainOutput)) out")
              .font(.system(size: 10).monospacedDigit())
              .foregroundStyle(.tertiary)
          }
        }
      } else {
        Text("No usage data yet")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .padding(.vertical, 8)
      }
    }
    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    .padding(16)
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
    VStack(alignment: .leading, spacing: 14) {
      Text("By Model")
        .font(.headline)
        .fontWeight(.bold)

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
    .padding(16)
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

// MARK: - Token Formatter

private func formatTokens(_ count: Int) -> String {
  if count >= 1_000_000 {
    return String(format: "%.1fM", Double(count) / 1_000_000)
  } else if count >= 1_000 {
    return String(format: "%.0fK", Double(count) / 1_000)
  }
  return "\(count)"
}
