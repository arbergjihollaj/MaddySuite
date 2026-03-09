import SwiftUI

// =====================================================
// MARK: - YearHeatmapView
// [TAG: MOBILE_HEATMAP]
// =====================================================

struct YearHeatmapView: View {
    let year: Int
    let values: [Date: Int]
    let tint: Color

    private let cellSize: CGFloat = 11
    private let gap: CGFloat = 3

    var body: some View {
        let weeks = makeWeeks()

        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: gap) {
                    ForEach(weeks.indices, id: \.self) { weekIndex in
                        VStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { row in
                                let date = weeks[weekIndex][safe: row] ?? nil
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(color(for: date))
                                    .frame(width: cellSize, height: cellSize)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: 6) {
                Text("Less")
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(legendColor(step: index))
                        .frame(width: 12, height: 12)
                }
                Text("More")
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private func color(for date: Date?) -> Color {
        guard let date else { return Color.clear }
        let key = Calendar.current.startOfDay(for: date)
        let value = values[key, default: 0]
        if value <= 0 { return Color.white.opacity(0.07) }
        if value == 1 { return tint.opacity(0.35) }
        if value == 2 { return tint.opacity(0.55) }
        return tint.opacity(0.8)
    }

    private func legendColor(step: Int) -> Color {
        switch step {
        case 0: return Color.white.opacity(0.07)
        case 1: return tint.opacity(0.35)
        case 2: return tint.opacity(0.55)
        default: return tint.opacity(0.8)
        }
    }

    private func makeWeeks() -> [[Date?]] {
        let calendar = Calendar.current
        guard let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let yearEnd = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else {
            return []
        }

        let weekday = calendar.component(.weekday, from: yearStart)
        let leading = (weekday + 5) % 7

        var dates: [Date?] = Array(repeating: nil, count: leading)
        var current = yearStart
        while current < yearEnd {
            dates.append(calendar.startOfDay(for: current))
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        while dates.count % 7 != 0 {
            dates.append(nil)
        }

        var weeks: [[Date?]] = []
        var index = 0
        while index < dates.count {
            let end = min(index + 7, dates.count)
            weeks.append(Array(dates[index..<end]))
            index += 7
        }

        return weeks
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
