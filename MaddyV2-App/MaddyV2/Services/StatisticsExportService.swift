import Foundation

// =====================================================
// MARK: - Statistics Snapshot
// [TAG: STATS_EXPORT_SNAPSHOT]
// =====================================================

struct StatisticsSnapshot: Sendable {
    struct FocusEntry: Sendable {
        var id: String
        var startedAt: Date
        var durationSeconds: Int
    }

    struct HabitEntry: Sendable {
        var habitID: String
        var habitName: String
        var dateKey: String
        var value: Int
        var target: Int
    }

    struct TaskEntry: Sendable {
        var id: String
        var title: String
        var status: String
        var dueDate: Date?
        var doneDate: Date?
    }

    var focusEntries: [FocusEntry]
    var habitEntries: [HabitEntry]
    var taskEntries: [TaskEntry]
    var totalXP: Int
    var level: Int
    var capturedAt: Date
}

// =====================================================
// MARK: - Statistics Export Service
// [TAG: STATS_EXPORT_SERVICE]
// =====================================================

actor StatisticsExportService {
    struct ExportResult {
        var statsFileURL: URL
        var weeklyFileURL: URL
    }

    enum ExportError: LocalizedError {
        case unableToCreateDirectory
        case zipFailed(code: Int32)
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .unableToCreateDirectory:
                return "Could not create export directory."
            case .zipFailed:
                return "Could not generate Excel archive."
            case .writeFailed:
                return "Could not write export data."
            }
        }
    }

    private struct FocusSessionRow: Codable {
        var id: String
        var date: String
        var start: String
        var end: String
        var minutes: Int
    }

    private struct HabitRow: Codable {
        var habitID: String
        var date: String
        var habit: String
        var done: Int
    }

    private struct TaskRow: Codable {
        var rowID: String
        var taskID: String
        var task: String
        var status: String
        var due: String
        var done: String
        var updatedAt: String
    }

    private struct XPRow: Codable {
        var timestamp: String
        var date: String
        var xp: Int
        var level: Int
    }

    private struct StatisticsLedger: Codable {
        var focusRows: [FocusSessionRow] = []
        var habitRows: [HabitRow] = []
        var taskRows: [TaskRow] = []
        var xpRows: [XPRow] = []

        var seenFocusIDs: Set<String> = []
        var habitLastValueByKey: [String: Int] = [:]
        var taskLastSignatureByID: [String: String] = [:]

        var lastXP: Int = 0
        var lastLevel: Int = 1
        var hasXPBaseline: Bool = false
    }

    private enum CellValue {
        case text(String)
        case number(Double)
    }

    private struct ChartSeries {
        var name: String
        var categoriesFormula: String
        var valuesFormula: String
    }

    private struct ChartSpec {
        enum Kind {
            case line
            case bar
        }

        var title: String
        var kind: Kind
        var series: [ChartSeries]
    }

    private struct SheetSpec {
        var name: String
        var rows: [[CellValue]]
        var hiddenColumnRange: ClosedRange<Int>?
        var chart: ChartSpec?
    }

    private let folderName = "Maddy"
    private let statsFileName = "Maddy_Stats.xlsx"
    private let weeklyFileName = "Maddy_Weekly_Report.xlsx"
    private let ledgerFileName = "stats_ledger.json"

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private let dateFormatter: DateFormatter
    private let timeFormatter: DateFormatter
    private let dateTimeFormatter: DateFormatter

    private var ledger: StatisticsLedger

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        decoder = JSONDecoder()

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MM-dd"
        self.dateFormatter = dateFormatter

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = .current
        timeFormatter.dateFormat = "HH:mm"
        self.timeFormatter = timeFormatter

        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateTimeFormatter.timeZone = .current
        dateTimeFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        self.dateTimeFormatter = dateTimeFormatter

        self.ledger = StatisticsLedger()

        if let loaded = try? loadLedger() {
            self.ledger = loaded
        }
    }

    func ingest(snapshot: StatisticsSnapshot) async {
        do {
            try ensureExportDirectory()
            var didChange = false

            didChange = ingestFocus(snapshot.focusEntries) || didChange
            didChange = ingestHabits(snapshot.habitEntries) || didChange
            didChange = ingestTasks(snapshot.taskEntries, capturedAt: snapshot.capturedAt) || didChange
            didChange = ingestXP(snapshot: snapshot) || didChange

            if didChange {
                try saveLedger()
            }
        } catch {
            // Keep export ingestion best-effort and non-blocking.
        }
    }

    func exportWorkbooks() async throws -> ExportResult {
        let directory = try ensureExportDirectory()
        let statsURL = directory.appendingPathComponent(statsFileName)
        let weeklyURL = directory.appendingPathComponent(weeklyFileName)

        try writeMainWorkbook(to: statsURL)
        try writeWeeklyWorkbook(to: weeklyURL)

        return ExportResult(statsFileURL: statsURL, weeklyFileURL: weeklyURL)
    }

    func statsWorkbookURL() throws -> URL {
        let directory = try ensureExportDirectory()
        return directory.appendingPathComponent(statsFileName)
    }

    func exportDirectoryURL() throws -> URL {
        try ensureExportDirectory()
    }

    // =====================================================
    // MARK: - Ingestion
    // [TAG: STATS_EXPORT_INGEST]
    // =====================================================

    private func ingestFocus(_ entries: [StatisticsSnapshot.FocusEntry]) -> Bool {
        guard entries.isEmpty == false else { return false }

        var changed = false
        for entry in entries {
            guard ledger.seenFocusIDs.contains(entry.id) == false else { continue }

            let started = entry.startedAt
            let endDate = started.addingTimeInterval(TimeInterval(max(0, entry.durationSeconds)))
            let minutes = max(0, entry.durationSeconds / 60)

            ledger.focusRows.append(
                FocusSessionRow(
                    id: entry.id,
                    date: dateFormatter.string(from: started),
                    start: timeFormatter.string(from: started),
                    end: timeFormatter.string(from: endDate),
                    minutes: minutes
                )
            )
            ledger.seenFocusIDs.insert(entry.id)
            changed = true
        }

        if changed {
            ledger.focusRows.sort {
                ($0.date, $0.start) < ($1.date, $1.start)
            }
        }

        return changed
    }

    private func ingestHabits(_ entries: [StatisticsSnapshot.HabitEntry]) -> Bool {
        guard entries.isEmpty == false else { return false }

        var changed = false
        for entry in entries {
            let target = max(1, entry.target)
            let normalizedValue = max(0, entry.value)
            let key = "\(entry.habitID)|\(entry.dateKey)"

            let lastValue = ledger.habitLastValueByKey[key]
            guard lastValue != normalizedValue else { continue }

            ledger.habitLastValueByKey[key] = normalizedValue

            let done = normalizedValue >= target ? 1 : 0
            ledger.habitRows.append(
                HabitRow(
                    habitID: entry.habitID,
                    date: entry.dateKey,
                    habit: entry.habitName.isEmpty ? "Habit" : entry.habitName,
                    done: done
                )
            )
            changed = true
        }

        if changed {
            ledger.habitRows.sort {
                if $0.date == $1.date {
                    return $0.habit < $1.habit
                }
                return $0.date < $1.date
            }
        }

        return changed
    }

    private func ingestTasks(_ entries: [StatisticsSnapshot.TaskEntry], capturedAt: Date) -> Bool {
        guard entries.isEmpty == false else { return false }

        var changed = false
        let timestamp = dateTimeFormatter.string(from: capturedAt)

        for entry in entries {
            let due = entry.dueDate.map { dateTimeFormatter.string(from: $0) } ?? ""
            let done = entry.doneDate.map { dateTimeFormatter.string(from: $0) } ?? ""
            let signature = "\(entry.title)|\(entry.status)|\(due)|\(done)"

            if ledger.taskLastSignatureByID[entry.id] == signature {
                continue
            }

            ledger.taskLastSignatureByID[entry.id] = signature
            ledger.taskRows.append(
                TaskRow(
                    rowID: UUID().uuidString,
                    taskID: entry.id,
                    task: entry.title,
                    status: entry.status,
                    due: due,
                    done: done,
                    updatedAt: timestamp
                )
            )
            changed = true
        }

        if changed {
            ledger.taskRows.sort {
                if $0.updatedAt == $1.updatedAt {
                    return $0.rowID < $1.rowID
                }
                return $0.updatedAt < $1.updatedAt
            }
        }

        return changed
    }

    private func ingestXP(snapshot: StatisticsSnapshot) -> Bool {
        let xp = max(0, snapshot.totalXP)
        let level = max(1, snapshot.level)

        if ledger.hasXPBaseline,
           ledger.lastXP == xp,
           ledger.lastLevel == level {
            return false
        }

        ledger.xpRows.append(
            XPRow(
                timestamp: dateTimeFormatter.string(from: snapshot.capturedAt),
                date: dateTimeFormatter.string(from: snapshot.capturedAt),
                xp: xp,
                level: level
            )
        )
        ledger.lastXP = xp
        ledger.lastLevel = level
        ledger.hasXPBaseline = true

        ledger.xpRows.sort { $0.timestamp < $1.timestamp }
        return true
    }

    // =====================================================
    // MARK: - Workbook Writing
    // [TAG: STATS_EXPORT_WORKBOOKS]
    // =====================================================

    private func writeMainWorkbook(to url: URL) throws {
        let focusRows: [[CellValue]] = [
            [.text("Date"), .text("Start"), .text("End"), .text("Minutes")]
        ] + ledger.focusRows.map {
            [.text($0.date), .text($0.start), .text($0.end), .number(Double($0.minutes))]
        }

        let habitsRows: [[CellValue]] = [
            [.text("Date"), .text("Habit"), .text("Done")]
        ] + ledger.habitRows.map {
            [.text($0.date), .text($0.habit), .number(Double($0.done))]
        }

        let tasksRows: [[CellValue]] = [
            [.text("Task"), .text("Status"), .text("Due"), .text("Done"), .text("Completed"), .text("Week")]
        ] + ledger.taskRows.map {
            let completed = ($0.done.isEmpty == false && $0.status.lowercased() == "done") ? 1.0 : 0.0
            let week = weekKey(fromDateString: $0.done)
            return [.text($0.task), .text($0.status), .text($0.due), .text($0.done), .number(completed), .text(week)]
        }

        let xpRows: [[CellValue]] = [
            [.text("Date"), .text("XP"), .text("Level")]
        ] + ledger.xpRows.map {
            [.text($0.date), .number(Double($0.xp)), .number(Double($0.level))]
        }

        let sheets = [
            SheetSpec(
                name: "FocusSessions",
                rows: focusRows,
                hiddenColumnRange: nil,
                chart: ChartSpec(
                    title: "Focus Minutes per Day",
                    kind: .line,
                    series: [
                        ChartSeries(
                            name: "Focus Minutes",
                            categoriesFormula: "'FocusSessions'!$A:$A",
                            valuesFormula: "'FocusSessions'!$D:$D"
                        )
                    ]
                )
            ),
            SheetSpec(
                name: "Habits",
                rows: habitsRows,
                hiddenColumnRange: nil,
                chart: ChartSpec(
                    title: "Habit Completion Rate",
                    kind: .bar,
                    series: [
                        ChartSeries(
                            name: "Done",
                            categoriesFormula: "'Habits'!$A:$A",
                            valuesFormula: "'Habits'!$C:$C"
                        )
                    ]
                )
            ),
            SheetSpec(
                name: "Tasks",
                rows: tasksRows,
                hiddenColumnRange: 5...6,
                chart: ChartSpec(
                    title: "Tasks Completed per Week",
                    kind: .bar,
                    series: [
                        ChartSeries(
                            name: "Completed",
                            categoriesFormula: "'Tasks'!$F:$F",
                            valuesFormula: "'Tasks'!$E:$E"
                        )
                    ]
                )
            ),
            SheetSpec(
                name: "XP",
                rows: xpRows,
                hiddenColumnRange: nil,
                chart: ChartSpec(
                    title: "XP Growth",
                    kind: .line,
                    series: [
                        ChartSeries(
                            name: "XP",
                            categoriesFormula: "'XP'!$A:$A",
                            valuesFormula: "'XP'!$B:$B"
                        )
                    ]
                )
            )
        ]

        try writeWorkbook(sheets: sheets, destinationURL: url)
    }

    private func writeWeeklyWorkbook(to url: URL) throws {
        let summaryRows = buildWeeklySummaryRows()

        let rows: [[CellValue]] = [
            [.text("Week"), .text("Focus Minutes"), .text("Tasks Completed"), .text("Habits Completed"), .text("XP Gained")]
        ] + summaryRows.map {
            [
                .text($0.week),
                .number(Double($0.focusMinutes)),
                .number(Double($0.tasksCompleted)),
                .number(Double($0.habitsCompleted)),
                .number(Double($0.xpGained))
            ]
        }

        let sheets = [
            SheetSpec(
                name: "WeeklySummary",
                rows: rows,
                hiddenColumnRange: nil,
                chart: ChartSpec(
                    title: "Weekly Productivity Overview",
                    kind: .bar,
                    series: [
                        ChartSeries(name: "Focus Minutes", categoriesFormula: "'WeeklySummary'!$A:$A", valuesFormula: "'WeeklySummary'!$B:$B"),
                        ChartSeries(name: "Tasks Completed", categoriesFormula: "'WeeklySummary'!$A:$A", valuesFormula: "'WeeklySummary'!$C:$C"),
                        ChartSeries(name: "Habits Completed", categoriesFormula: "'WeeklySummary'!$A:$A", valuesFormula: "'WeeklySummary'!$D:$D"),
                        ChartSeries(name: "XP Gained", categoriesFormula: "'WeeklySummary'!$A:$A", valuesFormula: "'WeeklySummary'!$E:$E")
                    ]
                )
            )
        ]

        try writeWorkbook(sheets: sheets, destinationURL: url)
    }

    // =====================================================
    // MARK: - Weekly Summary
    // [TAG: STATS_EXPORT_WEEKLY]
    // =====================================================

    private struct WeeklySummaryRow {
        var week: String
        var focusMinutes: Int
        var tasksCompleted: Int
        var habitsCompleted: Int
        var xpGained: Int
    }

    private struct WeeklyAccumulator {
        var focusMinutes: Int = 0
        var tasksCompleted: Int = 0
        var habitsCompleted: Int = 0
        var xpGained: Int = 0
    }

    private func buildWeeklySummaryRows() -> [WeeklySummaryRow] {
        var accumulator: [String: WeeklyAccumulator] = [:]

        for row in ledger.focusRows {
            guard let date = dateFormatter.date(from: row.date) else { continue }
            let week = weekKey(for: date)
            accumulator[week, default: WeeklyAccumulator()].focusMinutes += max(0, row.minutes)
        }

        var completedTaskKeys = Set<String>()
        for row in ledger.taskRows {
            guard row.done.isEmpty == false else { continue }
            guard row.status.lowercased() == "done" else { continue }
            let key = "\(row.taskID)|\(row.done)"
            guard completedTaskKeys.insert(key).inserted else { continue }

            guard let date = parseDateTime(row.done) else { continue }
            let week = weekKey(for: date)
            accumulator[week, default: WeeklyAccumulator()].tasksCompleted += 1
        }

        for row in ledger.habitRows where row.done > 0 {
            guard let date = dateFormatter.date(from: row.date) else { continue }
            let week = weekKey(for: date)
            accumulator[week, default: WeeklyAccumulator()].habitsCompleted += 1
        }

        var previousXP: Int?
        let sortedXP = ledger.xpRows.sorted { $0.timestamp < $1.timestamp }
        for row in sortedXP {
            guard let date = parseDateTime(row.timestamp) else { continue }
            let week = weekKey(for: date)
            if let previousXP {
                accumulator[week, default: WeeklyAccumulator()].xpGained += max(0, row.xp - previousXP)
            }
            previousXP = row.xp
        }

        return accumulator
            .map { key, value in
                WeeklySummaryRow(
                    week: key,
                    focusMinutes: value.focusMinutes,
                    tasksCompleted: value.tasksCompleted,
                    habitsCompleted: value.habitsCompleted,
                    xpGained: value.xpGained
                )
            }
            .sorted { lhs, rhs in
                sortWeekKey(lhs.week) < sortWeekKey(rhs.week)
            }
    }

    // =====================================================
    // MARK: - XLSX Package Builder
    // [TAG: STATS_EXPORT_XLSX_BUILDER]
    // =====================================================

    private func writeWorkbook(sheets: [SheetSpec], destinationURL: URL) throws {
        guard sheets.isEmpty == false else { throw ExportError.writeFailed }

        let stagingURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("maddy-xlsx-\(UUID().uuidString)", isDirectory: true)

        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: stagingURL)
        }

        try createBaseDirectories(in: stagingURL)

        let chartCount = sheets.filter { $0.chart != nil }.count

        try writeText(contentTypesXML(sheetCount: sheets.count, chartCount: chartCount), to: stagingURL.appendingPathComponent("[Content_Types].xml"))
        try writeText(rootRelsXML(), to: stagingURL.appendingPathComponent("_rels/.rels"))
        try writeText(workbookXML(sheets: sheets), to: stagingURL.appendingPathComponent("xl/workbook.xml"))
        try writeText(workbookRelsXML(sheetCount: sheets.count), to: stagingURL.appendingPathComponent("xl/_rels/workbook.xml.rels"))
        try writeText(stylesXML(), to: stagingURL.appendingPathComponent("xl/styles.xml"))

        try writeText(appPropsXML(sheetNames: sheets.map(\.name)), to: stagingURL.appendingPathComponent("docProps/app.xml"))
        try writeText(corePropsXML(), to: stagingURL.appendingPathComponent("docProps/core.xml"))

        var chartIndex = 1
        for (index, sheet) in sheets.enumerated() {
            let sheetNumber = index + 1

            try writeText(
                worksheetXML(sheet: sheet),
                to: stagingURL.appendingPathComponent("xl/worksheets/sheet\(sheetNumber).xml")
            )

            if let chart = sheet.chart {
                try writeText(
                    worksheetRelsXML(drawingIndex: chartIndex),
                    to: stagingURL.appendingPathComponent("xl/worksheets/_rels/sheet\(sheetNumber).xml.rels")
                )

                try writeText(
                    drawingXML(drawingIndex: chartIndex),
                    to: stagingURL.appendingPathComponent("xl/drawings/drawing\(chartIndex).xml")
                )

                try writeText(
                    drawingRelsXML(chartIndex: chartIndex),
                    to: stagingURL.appendingPathComponent("xl/drawings/_rels/drawing\(chartIndex).xml.rels")
                )

                try writeText(
                    chartXML(chart: chart, chartIndex: chartIndex),
                    to: stagingURL.appendingPathComponent("xl/charts/chart\(chartIndex).xml")
                )

                chartIndex += 1
            }
        }

        try zipDirectory(stagingURL: stagingURL, destinationURL: destinationURL)
    }

    private func createBaseDirectories(in root: URL) throws {
        let directories = [
            "_rels",
            "docProps",
            "xl",
            "xl/_rels",
            "xl/worksheets",
            "xl/worksheets/_rels",
            "xl/drawings",
            "xl/drawings/_rels",
            "xl/charts"
        ]

        for relative in directories {
            try fileManager.createDirectory(
                at: root.appendingPathComponent(relative, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    private func worksheetXML(sheet: SheetSpec) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        xml += "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
        xml += "<sheetViews><sheetView workbookViewId=\"0\"/></sheetViews>"
        xml += "<sheetFormatPr defaultRowHeight=\"15\"/>"

        if let hidden = sheet.hiddenColumnRange {
            xml += "<cols>"
            xml += "<col min=\"\(hidden.lowerBound)\" max=\"\(hidden.upperBound)\" width=\"0\" hidden=\"1\" customWidth=\"1\"/>"
            xml += "</cols>"
        }

        xml += "<sheetData>"

        for (rowIndex, row) in sheet.rows.enumerated() {
            let excelRow = rowIndex + 1
            xml += "<row r=\"\(excelRow)\">"

            for (columnIndex, cell) in row.enumerated() {
                let excelColumn = columnName(columnIndex + 1)
                let cellRef = "\(excelColumn)\(excelRow)"

                switch cell {
                case .text(let value):
                    xml += "<c r=\"\(cellRef)\" t=\"inlineStr\"><is><t>\(escapeXML(value))</t></is></c>"
                case .number(let value):
                    xml += "<c r=\"\(cellRef)\"><v>\(numberString(value))</v></c>"
                }
            }

            xml += "</row>"
        }

        xml += "</sheetData>"

        if sheet.chart != nil {
            xml += "<drawing r:id=\"rId1\"/>"
        }

        xml += "</worksheet>"
        return xml
    }

    private func chartXML(chart: ChartSpec, chartIndex: Int) -> String {
        let catAxID = 1000 + chartIndex * 2
        let valAxID = 1001 + chartIndex * 2

        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        xml += "<c:chartSpace xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
        xml += "<c:chart>"
        xml += "<c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>\(escapeXML(chart.title))</a:t></a:r></a:p></c:rich></c:tx></c:title>"
        xml += "<c:autoTitleDeleted val=\"0\"/>"
        xml += "<c:plotArea><c:layout/>"

        switch chart.kind {
        case .line:
            xml += "<c:lineChart><c:grouping val=\"standard\"/>"
            for (index, series) in chart.series.enumerated() {
                xml += chartSeriesXML(series: series, seriesIndex: index)
            }
            xml += "<c:axId val=\"\(catAxID)\"/><c:axId val=\"\(valAxID)\"/>"
            xml += "</c:lineChart>"
        case .bar:
            xml += "<c:barChart><c:barDir val=\"col\"/><c:grouping val=\"clustered\"/>"
            for (index, series) in chart.series.enumerated() {
                xml += chartSeriesXML(series: series, seriesIndex: index)
            }
            xml += "<c:axId val=\"\(catAxID)\"/><c:axId val=\"\(valAxID)\"/>"
            xml += "</c:barChart>"
        }

        xml += "<c:catAx><c:axId val=\"\(catAxID)\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling><c:axPos val=\"b\"/><c:tickLblPos val=\"nextTo\"/><c:crossAx val=\"\(valAxID)\"/><c:crosses val=\"autoZero\"/></c:catAx>"
        xml += "<c:valAx><c:axId val=\"\(valAxID)\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling><c:axPos val=\"l\"/><c:majorGridlines/><c:tickLblPos val=\"nextTo\"/><c:crossAx val=\"\(catAxID)\"/><c:crosses val=\"autoZero\"/></c:valAx>"

        xml += "</c:plotArea>"
        xml += "<c:legend><c:legendPos val=\"r\"/></c:legend>"
        xml += "<c:plotVisOnly val=\"1\"/>"
        xml += "</c:chart>"
        xml += "</c:chartSpace>"

        return xml
    }

    private func chartSeriesXML(series: ChartSeries, seriesIndex: Int) -> String {
        var xml = "<c:ser>"
        xml += "<c:idx val=\"\(seriesIndex)\"/><c:order val=\"\(seriesIndex)\"/>"
        xml += "<c:tx><c:v>\(escapeXML(series.name))</c:v></c:tx>"
        xml += "<c:cat><c:strRef><c:f>\(escapeXML(series.categoriesFormula))</c:f></c:strRef></c:cat>"
        xml += "<c:val><c:numRef><c:f>\(escapeXML(series.valuesFormula))</c:f></c:numRef></c:val>"
        xml += "</c:ser>"
        return xml
    }

    private func drawingXML(drawingIndex: Int) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <xdr:twoCellAnchor>
            <xdr:from>
              <xdr:col>6</xdr:col>
              <xdr:colOff>0</xdr:colOff>
              <xdr:row>1</xdr:row>
              <xdr:rowOff>0</xdr:rowOff>
            </xdr:from>
            <xdr:to>
              <xdr:col>15</xdr:col>
              <xdr:colOff>0</xdr:colOff>
              <xdr:row>20</xdr:row>
              <xdr:rowOff>0</xdr:rowOff>
            </xdr:to>
            <xdr:graphicFrame macro="">
              <xdr:nvGraphicFramePr>
                <xdr:cNvPr id="2" name="Chart \(drawingIndex)"/>
                <xdr:cNvGraphicFramePr/>
              </xdr:nvGraphicFramePr>
              <xdr:xfrm>
                <a:off x="0" y="0"/>
                <a:ext cx="0" cy="0"/>
              </xdr:xfrm>
              <a:graphic>
                <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart">
                  <c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:id="rId1"/>
                </a:graphicData>
              </a:graphic>
            </xdr:graphicFrame>
            <xdr:clientData/>
          </xdr:twoCellAnchor>
        </xdr:wsDr>
        """
    }

    private func workbookXML(sheets: [SheetSpec]) -> String {
        var sheetsXML = ""
        for (index, sheet) in sheets.enumerated() {
            sheetsXML += "<sheet name=\"\(escapeXML(sheet.name))\" sheetId=\"\(index + 1)\" r:id=\"rId\(index + 1)\"/>"
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <bookViews>
            <workbookView xWindow="0" yWindow="0" windowWidth="20000" windowHeight="12000"/>
          </bookViews>
          <sheets>
            \(sheetsXML)
          </sheets>
        </workbook>
        """
    }

    private func workbookRelsXML(sheetCount: Int) -> String {
        var rels = ""
        for index in 0..<sheetCount {
            rels += "<Relationship Id=\"rId\(index + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(index + 1).xml\"/>"
        }
        rels += "<Relationship Id=\"rId\(sheetCount + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          \(rels)
        </Relationships>
        """
    }

    private func worksheetRelsXML(drawingIndex: Int) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing\(drawingIndex).xml"/>
        </Relationships>
        """
    }

    private func drawingRelsXML(chartIndex: Int) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="../charts/chart\(chartIndex).xml"/>
        </Relationships>
        """
    }

    private func contentTypesXML(sheetCount: Int, chartCount: Int) -> String {
        var overrides = ""
        overrides += "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"
        overrides += "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
        overrides += "<Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/>"
        overrides += "<Override PartName=\"/docProps/app.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.extended-properties+xml\"/>"

        for index in 1...sheetCount {
            overrides += "<Override PartName=\"/xl/worksheets/sheet\(index).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
            overrides += "<Override PartName=\"/xl/drawings/drawing\(index).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.drawing+xml\"/>"
        }

        for index in 1...chartCount {
            overrides += "<Override PartName=\"/xl/charts/chart\(index).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.drawingml.chart+xml\"/>"
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          \(overrides)
        </Types>
        """
    }

    private func rootRelsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
          <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
        </Relationships>
        """
    }

    private func stylesXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <fonts count="1">
            <font><sz val="11"/><name val="Calibri"/></font>
          </fonts>
          <fills count="2">
            <fill><patternFill patternType="none"/></fill>
            <fill><patternFill patternType="gray125"/></fill>
          </fills>
          <borders count="1">
            <border><left/><right/><top/><bottom/><diagonal/></border>
          </borders>
          <cellStyleXfs count="1">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
          </cellStyleXfs>
          <cellXfs count="1">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
          </cellXfs>
          <cellStyles count="1">
            <cellStyle name="Normal" xfId="0" builtinId="0"/>
          </cellStyles>
        </styleSheet>
        """
    }

    private func appPropsXML(sheetNames: [String]) -> String {
        let count = sheetNames.count
        let vectorItems = sheetNames
            .map { "<vt:lpstr>\(escapeXML($0))</vt:lpstr>" }
            .joined()

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
          <Application>Maddy</Application>
          <DocSecurity>0</DocSecurity>
          <ScaleCrop>false</ScaleCrop>
          <HeadingPairs>
            <vt:vector size="2" baseType="variant">
              <vt:variant><vt:lpstr>Worksheets</vt:lpstr></vt:variant>
              <vt:variant><vt:i4>\(count)</vt:i4></vt:variant>
            </vt:vector>
          </HeadingPairs>
          <TitlesOfParts>
            <vt:vector size="\(count)" baseType="lpstr">\(vectorItems)</vt:vector>
          </TitlesOfParts>
          <Company>Maddy</Company>
        </Properties>
        """
    }

    private func corePropsXML() -> String {
        let now = ISO8601DateFormatter().string(from: Date())
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <dc:creator>Maddy</dc:creator>
          <cp:lastModifiedBy>Maddy</cp:lastModifiedBy>
          <dcterms:created xsi:type="dcterms:W3CDTF">\(now)</dcterms:created>
          <dcterms:modified xsi:type="dcterms:W3CDTF">\(now)</dcterms:modified>
        </cp:coreProperties>
        """
    }

    // =====================================================
    // MARK: - Persistence & File IO
    // [TAG: STATS_EXPORT_IO]
    // =====================================================

    private func ensureExportDirectory() throws -> URL {
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ExportError.unableToCreateDirectory
        }

        let directory = documents.appendingPathComponent(folderName, isDirectory: true)
        if fileManager.fileExists(atPath: directory.path) == false {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw ExportError.unableToCreateDirectory
            }
        }

        return directory
    }

    private func ledgerURL() throws -> URL {
        let directory = try ensureExportDirectory()
        return directory.appendingPathComponent(ledgerFileName)
    }

    private func loadLedger() throws -> StatisticsLedger {
        let url = try ledgerURL()
        guard let data = try? Data(contentsOf: url) else {
            return StatisticsLedger()
        }

        return try decoder.decode(StatisticsLedger.self, from: data)
    }

    private func saveLedger() throws {
        let url = try ledgerURL()
        guard let data = try? encoder.encode(ledger) else {
            throw ExportError.writeFailed
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ExportError.writeFailed
        }
    }

    private func writeText(_ text: String, to url: URL) throws {
        guard let data = text.data(using: .utf8) else {
            throw ExportError.writeFailed
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ExportError.writeFailed
        }
    }

    private func zipDirectory(stagingURL: URL, destinationURL: URL) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = stagingURL
        process.arguments = ["-qr", destinationURL.path, "."]

        do {
            try process.run()
        } catch {
            throw ExportError.zipFailed(code: -1)
        }

        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw ExportError.zipFailed(code: process.terminationStatus)
        }
    }

    // =====================================================
    // MARK: - Helpers
    // [TAG: STATS_EXPORT_HELPERS]
    // =====================================================

    private func weekKey(fromDateString value: String) -> String {
        guard let date = parseDateTime(value) else { return "" }
        return weekKey(for: date)
    }

    private func weekKey(for date: Date) -> String {
        let calendar = Calendar(identifier: .iso8601)
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        return String(format: "%04d-W%02d", year, week)
    }

    private func sortWeekKey(_ value: String) -> (Int, Int) {
        let parts = value.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let week = Int(parts[1].replacingOccurrences(of: "W", with: "")) else {
            return (0, 0)
        }
        return (year, week)
    }

    private func parseDateTime(_ value: String) -> Date? {
        if let date = dateTimeFormatter.date(from: value) {
            return date
        }

        if value.count >= 10 {
            let prefix = String(value.prefix(10))
            if let date = dateFormatter.date(from: prefix) {
                return date
            }
        }

        return nil
    }

    private func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func columnName(_ number: Int) -> String {
        guard number > 0 else { return "A" }
        var value = number
        var column = ""

        while value > 0 {
            let remainder = (value - 1) % 26
            if let scalar = UnicodeScalar(65 + remainder) {
                column = String(Character(scalar)) + column
            }
            value = (value - 1) / 26
        }

        return column
    }

    private func numberString(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }
}
