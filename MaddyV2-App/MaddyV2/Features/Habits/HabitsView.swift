//
//  HabitsView.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import SwiftUI

// =====================================================
// MARK: - HabitsView
// [TAG: V2_HABITS_VIEW]
// =====================================================

struct HabitsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var serialService: SerialService

    @State private var showingEditor = false
    @State private var editingHabitID: UUID?

    // =====================================================
    // MARK: - Habit Completion Animation
    // [TAG: HABIT_COMPLETION_ANIMATION]
    // =====================================================
    @State private var animatingCompletionIDs: Set<UUID> = []

    private var vm: HabitsViewModel { appState.habitsViewModel }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                weekBar
                habitsList
                heatmap
            }
            .padding(.bottom, 10)
        }
        .onAppear {
            serialService.sendView(screen: "habits")
            syncHabitsSummaryToESP()
            if let first = vm.habits.first {
                syncHabitDetailToESP(first)
            }
        }
        .sheet(isPresented: $showingEditor) {
            HabitEditorSheet(
                isPresented: $showingEditor,
                isEditingExisting: editingHabitID != nil,
                onDraftChanged: {
                    syncDraftHabitToESP()
                },
                onSave: {
                    syncHabitsSummaryToESP()
                    if let saved = vm.habits.first(where: { $0.id == vm.draft.id }) {
                        syncHabitDetailToESP(saved)
                    } else {
                        syncDraftHabitToESP()
                    }
                },
                onDelete: { habitID in
                    if let index = vm.habits.firstIndex(where: { $0.id == habitID }) {
                        vm.delete(at: IndexSet(integer: index))
                    }
                    syncHabitsSummaryToESP()
                    if let first = vm.habits.first {
                        syncHabitDetailToESP(first)
                    } else {
                        serialService.sendHabitDetail(id: "-", title: "—", symbol: "leaf.fill", colorHex: "#24C483", streak: 0, doneToday: false)
                    }
                }
            )
            .environmentObject(appState)
        }
    }

    private var weekBar: some View {
        GlassCard(title: "Week", accent: appState.accentColor) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("Weekly score: \(vm.weeklyCompletionCount())")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Spacer()

                    Button {
                        editingHabitID = nil
                        vm.resetDraft()
                        showingEditor = true
                        syncDraftHabitToESP()
                    } label: {
                        Label("New Habit", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(appState.accentColor)
                }

                let today = Calendar.current.component(.weekday, from: Date())
                let weekdayLabels = HabitItem.weekdayLabels(mondayFirst: appState.settings.habitWeekStartsMonday)
                HStack(spacing: 8) {
                    ForEach(weekdayLabels, id: \.value) { day in
                        Text(day.label)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .frame(width: 30, height: 30)
                            .background(
                                Circle().fill(today == day.value ? appState.accentColor.opacity(0.4) : Color.white.opacity(0.06))
                            )
                    }
                }
            }
        }
    }

    private var habitsList: some View {
        VStack(spacing: 10) {
            ForEach(sortedHabits) { habit in
                habitRow(habit)
            }
        }
    }

    private var heatmap: some View {
        let columns = yearHeatmapColumns()
        let maxValue = max(1.0, columns.flatMap { $0.compactMap { $0?.value } }.max() ?? 1.0)
        let tint = Color(hex: vm.habits.first?.accentHex ?? "") ?? appState.accentColor

        return GlassCard(title: "Year Heatmap", accent: appState.accentColor) {
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { geo in
                    let weekCount = max(1, columns.count)
                    let availableGridWidth = max(260.0, geo.size.width - 34.0)
                    let cellSize = max(7.0, min(11.0, (availableGridWidth - (CGFloat(weekCount - 1) * 2.0)) / CGFloat(weekCount)))
                    let gridWidth = (CGFloat(weekCount) * cellSize) + (CGFloat(weekCount - 1) * 2.0)
                    let rowHeight = (7.0 * cellSize) + (6.0 * 2.0)

                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("M").font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Text("W").font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Text("F").font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Text("S").font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                        }
                        .frame(height: rowHeight)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 2) {
                                ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                                    VStack(spacing: 2) {
                                        ForEach(0..<7, id: \.self) { weekday in
                                            if let maybeCell = week[safe: weekday], let cell = maybeCell {
                                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                                    .fill(heatmapColor(value: cell.value, maxValue: maxValue, tint: tint))
                                                    .frame(width: cellSize, height: cellSize)
                                            } else {
                                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                                    .fill(Color.clear)
                                                    .frame(width: cellSize, height: cellSize)
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(
                                minWidth: max(availableGridWidth, gridWidth),
                                alignment: .leading
                            )
                        }
                    }
                }
                .frame(height: 104)

                HStack(spacing: 6) {
                    Text("Less")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)

                    ForEach(0..<5, id: \.self) { level in
                        let value = Double(level) / 4.0 * maxValue
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(heatmapColor(value: value, maxValue: maxValue, tint: tint))
                            .frame(width: 12, height: 12)
                    }

                    Text("More")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func habitRow(_ habit: HabitItem) -> some View {
        let color = Color(hex: habit.accentHex) ?? appState.accentColor
        let isScheduledToday = vm.isScheduledToday(habit)
        let nextScheduledDate = vm.nextScheduledDate(for: habit)

        return GlassCard(accent: color) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Image(systemName: habit.symbol)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(color)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(color.opacity(0.16)))

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.green)
                        .scaleEffect(animatingCompletionIDs.contains(habit.id) ? 1.08 : 0.2)
                        .opacity(animatingCompletionIDs.contains(habit.id) ? 1 : 0)
                        .animation(.spring(duration: 0.22, bounce: 0.34), value: animatingCompletionIDs.contains(habit.id))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(habit.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))

                    HStack(spacing: 8) {
                        Text("\(vm.valueToday(for: habit))/\(habit.targetPerDay) \(habit.kind.unitLabel)")
                        Text("Streak: \(vm.currentStreak(for: habit))")
                        Text("Weekly: \(Int(vm.weeklyScore(for: habit) * 100))%")
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                    Text(habitScheduleText(for: habit, isScheduledToday: isScheduledToday, nextScheduledDate: nextScheduledDate))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(isScheduledToday ? "Today" : "Later")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill((isScheduledToday ? color : .white).opacity(0.18))
                    )
                    .foregroundStyle(.secondary)

                Button(habit.kind == .timeBased ? "+5" : "+1") {
                    let wasDone = vm.completedToday(for: habit)
                    vm.increment(habit, amount: habit.kind == .timeBased ? 5 : 1)
                    if let updated = vm.habits.first(where: { $0.id == habit.id }) {
                        syncHabitsSummaryToESP()
                        syncHabitDetailToESP(updated)

                        let nowDone = vm.completedToday(for: updated)
                        if nowDone && !wasDone {
                            triggerCompletionAnimation(for: updated.id)
                            serialService.sendHabitDone(updated.title.isEmpty ? updated.id.uuidString : updated.title)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(color)
                .help(isScheduledToday ? "Mark habit as completed for today" : "Complete habit even though it is not scheduled today")

                Button("Preview ESP") {
                    serialService.sendHabitPreview(name: habit.title)
                    syncHabitDetailToESP(habit)
                }
                .buttonStyle(.bordered)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                editingHabitID = habit.id
                vm.draft = habit
                showingEditor = true
                syncDraftHabitToESP()
            }
        }
    }

    private func triggerCompletionAnimation(for habitID: UUID) {
        animatingCompletionIDs.insert(habitID)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            withAnimation(.easeOut(duration: 0.15)) {
                _ = animatingCompletionIDs.remove(habitID)
            }
        }
    }

    private func syncHabitsSummaryToESP() {
        let scheduledToday = vm.habits.filter { vm.isScheduledToday($0) }
        let doneToday = scheduledToday.filter { vm.completedToday(for: $0) }.count
        let totalToday = scheduledToday.count
        let streak = vm.habits.map { vm.currentStreak(for: $0) }.max() ?? 0
        serialService.sendHabitsSummary(
            doneToday: doneToday,
            totalToday: totalToday,
            streak: streak
        )
    }

    private func syncHabitDetailToESP(_ habit: HabitItem) {
        serialService.sendHabitDetail(
            id: habit.id.uuidString,
            title: habit.title,
            symbol: habit.symbol,
            colorHex: habit.accentHex,
            streak: vm.currentStreak(for: habit),
            doneToday: vm.completedToday(for: habit)
        )
    }

    private func syncDraftHabitToESP() {
        serialService.sendHabitDetail(
            id: vm.draft.id.uuidString,
            title: vm.draft.title,
            symbol: vm.draft.symbol,
            colorHex: vm.draft.accentHex,
            streak: vm.currentStreak(for: vm.draft),
            doneToday: vm.completedToday(for: vm.draft)
        )
    }

    // =====================================================
    // MARK: - Year Heatmap Helpers
    // [TAG: V2_HABIT_YEAR_HEATMAP]
    // =====================================================

    private func yearHeatmapColumns() -> [[YearHeatmapCell?]] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday

        let currentYear = calendar.component(.year, from: Date())
        guard
            let yearStart = calendar.date(from: DateComponents(year: currentYear, month: 1, day: 1)),
            let yearEnd = calendar.date(from: DateComponents(year: currentYear, month: 12, day: 31)),
            let firstWeekStart = calendar.dateInterval(of: .weekOfYear, for: yearStart)?.start,
            let lastWeekStart = calendar.dateInterval(of: .weekOfYear, for: yearEnd)?.start,
            let finalCursor = calendar.date(byAdding: .day, value: 6, to: lastWeekStart)
        else {
            return []
        }

        var valuesByDay: [String: Double] = [:]
        var dayCursor = yearStart
        while dayCursor <= yearEnd {
            valuesByDay[dayCursor.yyyymmdd] = completionScore(for: dayCursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: dayCursor) else { break }
            dayCursor = next
        }

        var columns: [[YearHeatmapCell?]] = []
        var weekCursor = firstWeekStart
        while weekCursor <= finalCursor {
            var week: [YearHeatmapCell?] = []
            for dayOffset in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: dayOffset, to: weekCursor) else {
                    week.append(nil)
                    continue
                }
                if date < yearStart || date > yearEnd {
                    week.append(nil)
                } else {
                    let value = valuesByDay[date.yyyymmdd] ?? 0
                    week.append(YearHeatmapCell(date: date, value: value))
                }
            }
            columns.append(week)
            guard let nextWeek = calendar.date(byAdding: .day, value: 7, to: weekCursor) else { break }
            weekCursor = nextWeek
        }

        return columns
    }

    private func completionScore(for day: Date) -> Double {
        let key = day.yyyymmdd
        let scheduledHabits = vm.habits.filter { $0.isScheduled(on: day) }
        guard scheduledHabits.isEmpty == false else { return 0 }

        var score = 0.0
        for habit in scheduledHabits {
            let done = habit.history[key, default: 0]
            let target = max(1, habit.targetPerDay)
            score += min(1.0, Double(done) / Double(target))
        }
        return score / Double(scheduledHabits.count)
    }

    private func heatmapColor(value: Double, maxValue: Double, tint: Color) -> Color {
        guard value > 0, maxValue > 0 else {
            return Color.white.opacity(0.06)
        }
        let normalized = min(1.0, value / maxValue)
        return tint.opacity(0.18 + (normalized * 0.82))
    }

    private var sortedHabits: [HabitItem] {
        vm.habits.sorted { lhs, rhs in
            let lhsScheduled = vm.isScheduledToday(lhs)
            let rhsScheduled = vm.isScheduledToday(rhs)
            if lhsScheduled != rhsScheduled {
                return lhsScheduled && rhsScheduled == false
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func habitScheduleText(for habit: HabitItem, isScheduledToday: Bool, nextScheduledDate: Date?) -> String {
        if vm.completedToday(for: habit) {
            return "Completed today"
        }
        if isScheduledToday {
            return "Planned today"
        }
        if let nextScheduledDate {
            return "Not planned today • Next \(nextScheduledDate.formatted(date: .abbreviated, time: .omitted))"
        }
        return "Not planned today"
    }
}

private struct YearHeatmapCell: Identifiable {
    let date: Date
    let value: Double
    var id: String { date.yyyymmdd }
}

// =====================================================
// MARK: - Habit Editor Sheet
// [TAG: HABIT_EDITOR_SHEET]
// =====================================================

private struct HabitEditorSheet: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool

    let isEditingExisting: Bool
    let onDraftChanged: () -> Void
    let onSave: () -> Void
    let onDelete: (UUID) -> Void

    @State private var targetValueText: String = ""
    @State private var isHoveringSave = false
    @State private var showsDeleteConfirm = false

    private var vm: HabitsViewModel { appState.habitsViewModel }

    private static let symbolCatalog: [String] = [
        "checkmark.circle.fill", "checkmark.seal.fill", "star.fill", "heart.fill", "bolt.fill",
        "leaf.fill", "flame.fill", "figure.walk", "figure.run", "bicycle",
        "figure.yoga", "brain.head.profile", "book.fill", "book.closed.fill", "graduationcap.fill",
        "pencil", "paintbrush.fill", "music.note", "guitars.fill", "headphones",
        "sun.max.fill", "moon.stars.fill", "bed.double.fill", "alarm.fill", "clock.fill",
        "fork.knife", "cup.and.saucer.fill", "drop.fill", "hare.fill", "tortoise.fill",
        "figure.hiking", "dumbbell.fill", "lungs.fill", "cross.case.fill", "pill.fill",
        "sparkles", "camera.fill", "phone.fill", "laptopcomputer", "tray.full.fill"
    ]

    private static let palette: [String] = [
        "#24C483", "#4DA3FF", "#FF7A2F", "#FF5C7A", "#A98BFF", "#FFD166", "#5EEAD4", "#F97316"
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().opacity(0.35)

            ScrollView {
                VStack(spacing: 16) {
                    basicInfoSection
                    schedulingSection
                    goalSection
                    tagsSection

                    if isEditingExisting {
                        dangerZoneSection
                    }
                }
                .padding(20)
            }

            Divider().opacity(0.35)

            footer
        }
        .background(
            // =====================================================
            // MARK: - Apple-like Habit Sheet Styling
            // [TAG: HABIT_SHEET_STYLE]
            // =====================================================
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .onAppear {
            targetValueText = "\(max(1, vm.draft.targetPerDay))"
            onDraftChanged()
        }
        .onChange(of: vm.draft) { _, _ in
            if targetValueText != "\(vm.draft.targetPerDay)" {
                targetValueText = "\(vm.draft.targetPerDay)"
            }
            onDraftChanged()
        }
        .onChange(of: targetValueText) { _, value in
            let filtered = value.filter(\.isNumber)
            if filtered != value {
                targetValueText = filtered
                return
            }
            if let numeric = Int(filtered), numeric > 0 {
                vm.draft.targetPerDay = numeric
            }
        }
        .confirmationDialog("Delete habit?", isPresented: $showsDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                onDelete(vm.draft.id)
                isPresented = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .frame(minWidth: 640, minHeight: 620)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: isEditingExisting ? "square.and.pencil" : "plus.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(appState.accentColor)
                .frame(width: 24, height: 24)
                .background(Circle().fill(appState.accentColor.opacity(0.16)))

            VStack(alignment: .leading, spacing: 2) {
                Text(isEditingExisting ? "Edit Habit" : "New Habit")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("Configure behavior, schedule, and goal")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var basicInfoSection: some View {
        GroupBox {
            VStack(spacing: 12) {
                fieldRow(icon: "textformat", label: "Habit") {
                    TextField("Habit name", text: Binding(
                        get: { vm.draft.title },
                        set: { vm.draft.title = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 0.8)
                            }
                    )
                    .frame(maxWidth: 360, alignment: .leading)
                }

                fieldRow(icon: "sparkles", label: "Symbol") {
                    Menu {
                        ForEach(Self.symbolCatalog, id: \.self) { symbol in
                            Button {
                                vm.draft.symbol = symbol
                            } label: {
                                Label(symbol, systemImage: symbol)
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: vm.draft.symbol)
                            Text(vm.draft.symbol)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: 360, alignment: .leading)
                }

                fieldRow(icon: "paintpalette", label: "Color") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(Self.palette, id: \.self) { hex in
                                let color = Color(hex: hex) ?? appState.accentColor
                                let selected = vm.draft.accentHex.uppercased() == hex.uppercased()
                                Button {
                                    vm.draft.accentHex = hex
                                } label: {
                                    Circle()
                                        .fill(color)
                                        .frame(width: 18, height: 18)
                                        .overlay {
                                            Circle().stroke(Color.white.opacity(selected ? 0.95 : 0.2), lineWidth: selected ? 2 : 1)
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        ColorPicker("Custom", selection: Binding(
                            get: { Color(hex: vm.draft.accentHex) ?? appState.accentColor },
                            set: { vm.draft.accentHex = $0.toHex }
                        ))
                        .labelsHidden()
                        .frame(maxWidth: 90, alignment: .leading)
                    }
                    .frame(maxWidth: 360, alignment: .leading)
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Basic Information")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .groupBoxStyle(.automatic)
    }

    private var schedulingSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Active weekdays")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(HabitItem.weekdayLabels(mondayFirst: appState.settings.habitWeekStartsMonday), id: \.value) { day in
                        let selected = HabitItem.normalizedWeekdays(vm.draft.scheduledWeekdays).contains(day.value)
                        Button(day.label) {
                            if selected {
                                vm.draft.scheduledWeekdays.removeAll { $0 == day.value }
                            } else {
                                vm.draft.scheduledWeekdays.append(day.value)
                            }
                            vm.draft.scheduledWeekdays = HabitItem.normalizedWeekdays(vm.draft.scheduledWeekdays)
                        }
                        .buttonStyle(.bordered)
                        .tint(selected ? appState.accentColor : .gray)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        } label: {
            Text("Scheduling")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .groupBoxStyle(.automatic)
    }

    private var goalSection: some View {
        GroupBox {
            VStack(spacing: 12) {
                fieldRow(icon: "scope", label: "Goal type") {
                    Picker("", selection: Binding(
                        get: { vm.draft.kind },
                        set: { vm.draft.kind = $0 }
                    )) {
                        Text("Time-based").tag(HabitKind.timeBased)
                        Text("Quantity-based").tag(HabitKind.quantityBased)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                }

                fieldRow(icon: "number", label: "Target") {
                    HStack(spacing: 8) {
                        TextField("Target", text: $targetValueText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 88)

                        Stepper("", value: Binding(
                            get: { max(1, vm.draft.targetPerDay) },
                            set: {
                                vm.draft.targetPerDay = max(1, $0)
                                targetValueText = "\(vm.draft.targetPerDay)"
                            }
                        ), in: 1...999)
                        .labelsHidden()

                        Text(vm.draft.kind == .timeBased ? "minutes / hours" : "pages / reps / units")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 360, alignment: .leading)
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Goal Configuration")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .groupBoxStyle(.automatic)
    }

    private var tagsSection: some View {
        GroupBox {
            fieldRow(icon: "tag", label: "Tags") {
                TextField("Optional tags (comma separated)", text: Binding(
                    get: { vm.draft.tags.joined(separator: ", ") },
                    set: { value in
                        vm.draft.tags = value
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { $0.isEmpty == false }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360, alignment: .leading)
            }
            .padding(.top, 6)
        } label: {
            Text("Tags")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .groupBoxStyle(.automatic)
    }

    private var dangerZoneSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Delete this habit and its tracked values.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer(minLength: 0)
                    Button(role: .destructive) {
                        showsDeleteConfirm = true
                    } label: {
                        Label("Delete Habit", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        } label: {
            Text("Danger Zone")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.red)
        }
        .groupBoxStyle(.automatic)
    }

    private var footer: some View {
        HStack {
            Button("Cancel") {
                isPresented = false
            }
            .buttonStyle(.bordered)

            Spacer(minLength: 0)

            Button {
                vm.upsertDraft()
                onSave()
                isPresented = false
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                    Text("Save")
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(appState.accentColor.opacity(isHoveringSave ? 0.92 : 0.78))
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(vm.draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(vm.draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.14)) {
                    isHoveringSave = hovering
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.14))
    }

    private func fieldRow<Content: View>(icon: String, label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Label(label, systemImage: icon)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)

            content()
            Spacer(minLength: 0)
        }
    }
}
