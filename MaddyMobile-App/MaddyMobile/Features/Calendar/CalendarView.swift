import SwiftUI

/// File: Features/Calendar/CalendarView.swift

// =====================================================
// MARK: - CalendarView
// [TAG: MOBILE_CALENDAR_VIEW]
// =====================================================

struct CalendarView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var calendarStore: CalendarStore

    private let weekdaySymbols = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                headerControls

                Text(calendarStore.periodTitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)

                if calendarStore.selectedMode == .month {
                    monthGrid
                    selectedDayAgenda
                } else {
                    agendaList
                }
            }
            .padding(16)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Calendar")
        .task {
            calendarStore.setLiveUpdatesEnabled(true)
            await calendarStore.refreshIfNeeded(maxAge: 90, forceCalendarPermissionPrompt: false)
        }
        .refreshable {
            await calendarStore.refreshAll(forceCalendarPermissionPrompt: false)
        }
        .onDisappear {
            calendarStore.setLiveUpdatesEnabled(false)
        }
    }

    private var headerControls: some View {
        HStack(spacing: 10) {
            navButton(systemName: "chevron.left") {
                calendarStore.goToPreviousPeriod()
            }

            Spacer(minLength: 8)

            Picker("View", selection: Binding(
                get: { calendarStore.selectedMode },
                set: { calendarStore.setMode($0) }
            )) {
                ForEach(CalendarViewMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 210)

            Spacer(minLength: 8)

            navButton(systemName: "chevron.right") {
                calendarStore.goToNextPeriod()
            }
        }
    }

    private func navButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(AppTheme.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var monthGrid: some View {
        GlassCard(accent: settings.accentColor) {
            VStack(spacing: 10) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                    ForEach(weekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                    }

                    ForEach(calendarStore.monthCells()) { cell in
                        Button {
                            calendarStore.selectDate(cell.date)
                        } label: {
                            monthCellContent(cell)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func monthCellContent(_ cell: CalendarMonthCell) -> some View {
        let isSelected = Calendar.current.isDate(cell.date, inSameDayAs: calendarStore.anchorDate)

        return VStack(spacing: 5) {
            Text(cell.date.formatted(.dateTime.day()))
                .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                .foregroundStyle(cell.isInCurrentMonth ? AppTheme.textPrimary : AppTheme.textSecondary)

            if cell.entryCount > 0 {
                HStack(spacing: 3) {
                    Circle()
                        .fill(cell.hasTask ? settings.accentColor : Color.blue.opacity(0.85))
                        .frame(width: 5, height: 5)
                    Text("\(min(cell.entryCount, 9))")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            } else {
                Color.clear
                    .frame(height: 5)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? settings.accentColor.opacity(0.22) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? settings.accentColor.opacity(0.6) : Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private var selectedDayAgenda: some View {
        GlassCard(title: "Selected Day", accent: settings.accentColor) {
            let entries = calendarStore.entriesForSelectedDay()

            if entries.isEmpty {
                Text("No events or tasks")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(entries) { entry in
                        entryRow(entry)
                    }
                }
            }
        }
    }

    private var agendaList: some View {
        let groups = calendarStore.daySummariesForVisiblePeriod()

        return Group {
            if groups.isEmpty {
                GlassCard(accent: settings.accentColor) {
                    Text("No events or tasks in this period")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(groups) { summary in
                        GlassCard(accent: settings.accentColor) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(summary.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppTheme.textSecondary)

                                ForEach(summary.entries) { entry in
                                    entryRow(entry)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func entryRow(_ entry: CalendarEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color(for: entry.source))
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(timeText(for: entry))
                    Text(entry.sourceName)
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func color(for source: CalendarEntrySource) -> Color {
        switch source {
        case .task:
            return settings.accentColor
        case .google:
            return Color.blue.opacity(0.95)
        case .ical:
            return Color.purple.opacity(0.9)
        }
    }

    private func timeText(for entry: CalendarEntry) -> String {
        if entry.isAllDay {
            return "All day"
        }

        let start = entry.startDate.formatted(date: .omitted, time: .shortened)
        let end = entry.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }
}
