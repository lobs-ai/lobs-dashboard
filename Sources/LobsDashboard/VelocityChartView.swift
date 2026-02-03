import SwiftUI
import Charts

// MARK: - Velocity Chart

/// Shows tasks completed per day over the last N days as an area chart.
/// Placed on the Overview screen to visualize productivity trends.
struct VelocityChartView: View {
  let tasks: [DashboardTask]

  @State private var selectedPeriod: Period = .twoWeeks

  enum Period: String, CaseIterable {
    case week = "7d"
    case twoWeeks = "14d"
    case month = "30d"

    var days: Int {
      switch self {
      case .week: return 7
      case .twoWeeks: return 14
      case .month: return 30
      }
    }
  }

  private struct DayData: Identifiable {
    let id: Date
    let date: Date
    let count: Int

    var dayLabel: String {
      let formatter = DateFormatter()
      formatter.dateFormat = "E"
      return formatter.string(from: date)
    }
  }

  private var dailyCounts: [DayData] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let days = selectedPeriod.days

    // Build a map of completion counts by day
    var countsByDay: [Date: Int] = [:]

    // Initialize all days to 0
    for offset in (0..<days).reversed() {
      if let date = calendar.date(byAdding: .day, value: -offset, to: today) {
        countsByDay[date] = 0
      }
    }

    // Count completed tasks by their updatedAt date
    let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
    for task in tasks where task.status == .completed {
      let taskDay = calendar.startOfDay(for: task.updatedAt)
      if taskDay >= startDate && taskDay <= today {
        countsByDay[taskDay, default: 0] += 1
      }
    }

    return countsByDay
      .map { DayData(id: $0.key, date: $0.key, count: $0.value) }
      .sorted { $0.date < $1.date }
  }

  private var totalCompleted: Int {
    dailyCounts.reduce(0) { $0 + $1.count }
  }

  private var avgPerDay: Double {
    guard !dailyCounts.isEmpty else { return 0 }
    return Double(totalCompleted) / Double(dailyCounts.count)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Header
      HStack(spacing: 8) {
        Image(systemName: "chart.line.uptrend.xyaxis")
          .font(.footnote)
          .foregroundStyle(.blue)
        Text("Velocity")
          .font(.footnote)
          .fontWeight(.medium)
          .foregroundStyle(.secondary)

        Spacer()

        // Summary stats
        HStack(spacing: 12) {
          HStack(spacing: 4) {
            Text("\(totalCompleted)")
              .font(.system(size: 11, weight: .semibold).monospacedDigit())
              .foregroundStyle(.primary)
            Text("done")
              .font(.system(size: 11))
              .foregroundStyle(.tertiary)
          }
          HStack(spacing: 4) {
            Text(String(format: "%.1f", avgPerDay))
              .font(.system(size: 11, weight: .semibold).monospacedDigit())
              .foregroundStyle(.primary)
            Text("/day")
              .font(.system(size: 11))
              .foregroundStyle(.tertiary)
          }
        }

        // Period picker
        HStack(spacing: 4) {
          ForEach(Period.allCases, id: \.self) { period in
            Button {
              withAnimation(.easeInOut(duration: 0.15)) { selectedPeriod = period }
            } label: {
              Text(period.rawValue)
                .font(.system(size: 10, weight: selectedPeriod == period ? .semibold : .regular))
                .foregroundStyle(selectedPeriod == period ? .primary : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(selectedPeriod == period ? Color.primary.opacity(0.1) : Color.clear)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
          }
        }
      }

      // Chart
      if totalCompleted > 0 {
        Chart(dailyCounts) { day in
          AreaMark(
            x: .value("Date", day.date, unit: .day),
            y: .value("Completed", day.count)
          )
          .foregroundStyle(
            LinearGradient(
              colors: [.blue.opacity(0.3), .blue.opacity(0.05)],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .interpolationMethod(.catmullRom)

          LineMark(
            x: .value("Date", day.date, unit: .day),
            y: .value("Completed", day.count)
          )
          .foregroundStyle(.blue)
          .lineStyle(StrokeStyle(lineWidth: 2))
          .interpolationMethod(.catmullRom)

          PointMark(
            x: .value("Date", day.date, unit: .day),
            y: .value("Completed", day.count)
          )
          .foregroundStyle(.blue)
          .symbolSize(day.count > 0 ? 20 : 0)
        }
        .chartXAxis {
          AxisMarks(values: .stride(by: .day, count: selectedPeriod == .month ? 5 : selectedPeriod == .twoWeeks ? 2 : 1)) { value in
            AxisGridLine()
              .foregroundStyle(Color.primary.opacity(0.05))
            AxisValueLabel {
              if let date = value.as(Date.self) {
                Text(shortDayLabel(date))
                  .font(.system(size: 9))
                  .foregroundStyle(.tertiary)
              }
            }
          }
        }
        .chartYAxis {
          AxisMarks(position: .leading) { value in
            AxisGridLine()
              .foregroundStyle(Color.primary.opacity(0.05))
            AxisValueLabel {
              if let count = value.as(Int.self) {
                Text("\(count)")
                  .font(.system(size: 9))
                  .foregroundStyle(.tertiary)
              }
            }
          }
        }
        .frame(height: 120)
      } else {
        HStack {
          Spacer()
          VStack(spacing: 6) {
            Image(systemName: "chart.line.flattrend.xyaxis")
              .font(.title3)
              .foregroundStyle(.quaternary)
            Text("No completions in this period")
              .font(.footnote)
              .foregroundStyle(.tertiary)
          }
          Spacer()
        }
        .frame(height: 80)
      }
    }
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: Theme.cardRadius)
        .fill(Theme.cardBg)
    )
    .overlay(
      RoundedRectangle(cornerRadius: Theme.cardRadius)
        .stroke(Theme.border, lineWidth: 0.5)
    )
  }

  private func shortDayLabel(_ date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "Today" }
    let formatter = DateFormatter()
    formatter.dateFormat = selectedPeriod == .month ? "M/d" : "E"
    return formatter.string(from: date)
  }
}
