import SwiftUI

private typealias UTheme = Theme

/// Detailed AI usage stats for worker runs.
struct WorkerUsageDetailSheet: View {
  let history: WorkerHistory
  let period: WorkerStatusCard.UsagePeriod

  @Environment(\.dismiss) private var dismiss

  private var filteredRuns: [WorkerHistoryRun] {
    history.runs
      .filter { $0.endedAt != nil }
      .filter { run in
        guard let ended = run.endedAt else { return false }
        return period.includes(ended)
      }
      .sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }
  }

  private var totalTokens: Int {
    filteredRuns.reduce(0) { $0 + ($1.totalTokens ?? 0) }
  }

  private var totalSpend: Double {
    filteredRuns.reduce(0.0) { $0 + ($1.totalCostUSD ?? 0) }
  }

  private var avgTokens: Int {
    guard !filteredRuns.isEmpty else { return 0 }
    return Int(Double(totalTokens) / Double(filteredRuns.count))
  }

  private var avgSpend: Double {
    guard !filteredRuns.isEmpty else { return 0 }
    return totalSpend / Double(filteredRuns.count)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("AI Usage — \(period.rawValue)")
            .font(.title3)
            .fontWeight(.bold)
          Text("\(filteredRuns.count) run\(filteredRuns.count == 1 ? "" : "s")")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button("Close") { dismiss() }
          .keyboardShortcut(.cancelAction)
      }

      HStack(spacing: 14) {
        UsageStatCard(label: "Total Tokens", value: formatTokenCount(totalTokens), icon: "cpu", color: .purple)
        UsageStatCard(label: "Total Spend", value: totalSpend > 0 ? "$\(String(format: "%.2f", totalSpend))" : "—", icon: "dollarsign.circle.fill", color: .mint)
        UsageStatCard(label: "Avg Tokens/Run", value: formatTokenCount(avgTokens), icon: "gauge", color: .orange)
        UsageStatCard(label: "Avg Spend/Run", value: totalSpend > 0 ? "$\(String(format: "%.2f", avgSpend))" : "—", icon: "chart.bar", color: .blue)
      }

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(filteredRuns) { run in
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text(run.endedAt?.formatted(date: .abbreviated, time: .shortened) ?? "(unknown)")
                  .font(.system(size: 12, weight: .semibold))
                Spacer()
                if let cost = run.totalCostUSD, cost > 0 {
                  Text("$\(cost, specifier: "%.2f")")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                }
              }
              HStack(spacing: 10) {
                if let inTok = run.inputTokens, let outTok = run.outputTokens, (inTok + outTok) > 0 {
                  Text("In/Out: \(formatTokenCount(inTok))/\(formatTokenCount(outTok))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                } else if let tok = run.totalTokens, tok > 0 {
                  Text("Tokens: \(formatTokenCount(tok))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                if let completed = run.tasksCompleted {
                  Text("Tasks: \(completed)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
                }
                if let started = run.startedAt, let ended = run.endedAt {
                  let minutes = max(1, Int(ended.timeIntervalSince(started) / 60))
                  Text("Duration: \(minutes)m")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
                }
              }
            }
            .padding(10)
            .background(UTheme.subtle)
            .clipShape(RoundedRectangle(cornerRadius: 10))
          }
        }
      }
    }
    .padding(16)
  }
}

private struct UsageStatCard: View {
  let label: String
  let value: String
  let icon: String
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .font(.system(size: 11))
          .foregroundStyle(color)
        Text(label)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
      }
      Text(value)
        .font(.system(size: 16, weight: .bold).monospacedDigit())
        .foregroundStyle(.primary)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(UTheme.cardBg)
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(UTheme.border, lineWidth: 0.5)
    )
  }
}

// Simple formatter helper (kept consistent with OverviewView)
private func formatTokenCount(_ tokens: Int) -> String {
  if tokens >= 1_000_000 { return String(format: "%.1fM", Double(tokens) / 1_000_000.0) }
  if tokens >= 1_000 { return String(format: "%.1fk", Double(tokens) / 1_000.0) }
  return "\(tokens)"
}
