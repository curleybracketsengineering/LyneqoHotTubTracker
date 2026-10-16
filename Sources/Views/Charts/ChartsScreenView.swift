//
//  ChartsScreenView.swift
//  HotTub
//

import Charts
import Combine
import SwiftData
import SwiftUI

private struct ChartPoint: Identifiable {
    let id: PersistentIdentifier
    let day: Date
    let value: Double
}

private struct UserBarPoint: Identifiable {
    let id: String
    let day: Date
    let count: Int
}

private enum ChartRange: String, CaseIterable {
    case last7Days = "Week"
    case month = "Month"
    case threeMonths = "3 months"
}

struct ChartsScreenView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appPalette) private var palette
    @Environment(\.usePadLayout) private var usePadLayout

    @Query(sort: \HotTubDailyLog.loggedAt, order: .forward) private var allDaily: [HotTubDailyLog]
    @Query(sort: \UsageLogEntry.loggedAt, order: .forward) private var allUsage: [UsageLogEntry]
    @Query private var settingsRows: [AppSettings]

    @State private var chartRange: ChartRange = .month
    @State private var viewMonth: Date = Date()
    /// Monday starting the visible calendar week (7-day window ends that Sunday or today).
    @State private var sevenDayWeekStart: Date = ChartsWeekCalendar.mondayContaining(Date())
    /// 0 is the 3-month window ending today. Each step moves the window back another 3 months.
    @State private var threeMonthWindowIndex: Int = 0
    @State private var presentedHelp: HelpSheetRequest?

    private var isBromine: Bool {
        settingsRows.first?.isBromine ?? false
    }

    private var isMetric: Bool {
        settingsRows.first?.measurementSystem != "imperial"
    }

    private var phTarget: ClosedRange<Double> {
        settingsRows.first?.phTarget ?? WaterChemistryRanges.startingPH
    }

    private var sanitizerTarget: ClosedRange<Double> {
        settingsRows.first?.sanitizerTarget
            ?? (isBromine ? WaterChemistryRanges.startingBromine : WaterChemistryRanges.startingChlorine)
    }

    private var sanitizerLabel: String {
        isBromine ? "Bromine" : "Chlorine"
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f.string(from: viewMonth)
    }

    private var todayStart: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var last7DaysStart: Date {
        Calendar.current.startOfDay(for: sevenDayWeekStart)
    }

    /// Last day with data in the visible week (today for the current week, Sunday for past weeks).
    private var last7DaysDataEnd: Date {
        ChartsWeekCalendar.weekDataEnd(forWeekStarting: sevenDayWeekStart, cappedTo: todayStart)
    }

    /// Full Mon–Sun span shown on the week chart x-axis.
    private var last7DaysChartEnd: Date {
        ChartsWeekCalendar.weekSunday(forWeekStarting: sevenDayWeekStart)
    }

    /// Exclusive end for week chart scale so Sunday's label/grid line aren't clipped.
    private var last7DaysChartScaleEnd: Date {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: 1, to: last7DaysChartEnd) ?? last7DaysChartEnd
    }

    private var isViewingCurrentWeek: Bool {
        Calendar.current.isDate(sevenDayWeekStart, inSameDayAs: currentWeekMonday)
    }

    private var currentWeekMonday: Date {
        ChartsWeekCalendar.mondayContaining(todayStart)
    }

    private var selectedWeekStart: Date {
        ChartsWeekCalendar.mondayContaining(sevenDayWeekStart)
    }

    private var canAdvanceSevenDayWindow: Bool {
        sevenDayWeekStart < currentWeekMonday
    }

    private var availableChartRanges: [ChartRange] {
        usePadLayout ? ChartRange.allCases : [.last7Days, .month]
    }

    private var currentThreeMonthAnchor: Date {
        ChartsThreeMonthWindow.anchorMonth(containing: todayStart)
    }

    private var earliestThreeMonthIndex: Int {
        ChartsThreeMonthWindow.earliestIndex(
            earliest: earliestChartLogDate,
            anchorMonth: currentThreeMonthAnchor
        )
    }

    private var threeMonthWindowIndices: [Int] {
        Array((earliestThreeMonthIndex...0).reversed())
    }

    private var isViewingCurrentThreeMonths: Bool {
        threeMonthWindowIndex == 0
    }

    private var canRetreatThreeMonthWindow: Bool {
        threeMonthWindowIndex > earliestThreeMonthIndex
    }

    private var canAdvanceThreeMonthWindow: Bool {
        threeMonthWindowIndex < 0
    }

    private var threeMonthBounds: (start: Date, end: Date) {
        threeMonthBounds(for: threeMonthWindowIndex)
    }

    private var threeMonthsStart: Date {
        threeMonthBounds.start
    }

    private var threeMonthsDataEnd: Date {
        threeMonthBounds.end
    }

    /// Last day on the 3-month chart x-axis (today for the current window).
    private var threeMonthsChartEnd: Date {
        threeMonthsDataEnd
    }

    /// Exclusive end for 3-month chart scale so the last day's point/label aren't clipped.
    private var threeMonthsChartScaleEnd: Date {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: 1, to: threeMonthsChartEnd) ?? threeMonthsChartEnd
    }

    private var threeMonthsLabel: String {
        formattedThreeMonthRange(start: threeMonthsStart, end: threeMonthsDataEnd)
    }

    private var emptyStatePeriodTitle: String {
        switch chartRange {
        case .last7Days:
            return "No data in this period"
        case .month:
            return "No data for \(monthLabel)"
        case .threeMonths:
            return isViewingCurrentThreeMonths ? "No data in the last 3 months" : "No data in this period"
        }
    }

    private var noDataPeriodPhrase: String {
        switch chartRange {
        case .last7Days:
            return last7DaysLabel
        case .month:
            return "this month"
        case .threeMonths:
            return isViewingCurrentThreeMonths ? "the last 3 months" : "this period"
        }
    }

    private var viewMonthStart: Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: viewMonth))
            ?? cal.startOfDay(for: viewMonth)
    }

    private var isViewingCurrentMonth: Bool {
        Calendar.current.isDate(viewMonthStart, equalTo: todayStart, toGranularity: .month)
    }

    private var monthLastDay: Date {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: viewMonth) else { return todayStart }
        let last = cal.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
        return cal.startOfDay(for: last)
    }

    /// Last calendar day on the month chart x-axis (today when viewing the current month).
    private var monthChartEnd: Date {
        isViewingCurrentMonth ? todayStart : monthLastDay
    }

    /// Exclusive end for month chart scale so the last day's point/label aren't clipped.
    private var monthChartScaleEnd: Date {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: 1, to: monthChartEnd) ?? monthChartEnd
    }

    private var monthPickerOptions: [Date] {
        let cal = Calendar.current
        guard let earliest = cal.date(byAdding: .month, value: -35, to: todayStart),
              var cursor = cal.date(from: cal.dateComponents([.year, .month], from: earliest))
        else { return [viewMonthStart] }

        let latest = cal.date(from: cal.dateComponents([.year, .month], from: todayStart)) ?? todayStart
        var months: [Date] = []
        while cursor <= latest {
            months.append(cursor)
            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return months
    }

    private var weekPickerOptions: [Date] {
        let cal = Calendar.current
        let currentMonday = currentWeekMonday
        let usageMondays = allUsage.map { ChartsWeekCalendar.mondayContaining($0.loggedAt) }
        let dailyMondays = allDaily.map { ChartsWeekCalendar.mondayContaining($0.loggedAt) }
        let dataEarliest = (usageMondays + dailyMondays).min()
        let defaultEarliest = cal.date(byAdding: .weekOfYear, value: -52, to: currentMonday) ?? currentMonday
        let earliestMonday = dataEarliest.map { min($0, currentMonday) } ?? defaultEarliest

        var mondays: [Date] = []
        var monday = currentMonday
        while monday >= earliestMonday {
            mondays.append(monday)
            guard let prev = cal.date(byAdding: .day, value: -7, to: monday) else { break }
            monday = prev
        }
        return mondays
    }

    private var last7DaysLabel: String {
        if isViewingCurrentWeek { return "this week" }
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return "\(f.string(from: last7DaysStart)) – \(f.string(from: last7DaysDataEnd))"
    }

    private func isInChartRange(_ date: Date) -> Bool {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        switch chartRange {
        case .last7Days:
            return day >= last7DaysStart && day <= last7DaysDataEnd
        case .month:
            guard cal.isDate(day, equalTo: viewMonth, toGranularity: .month) else { return false }
            return !isViewingCurrentMonth || day <= todayStart
        case .threeMonths:
            return day >= threeMonthsStart && day <= threeMonthsDataEnd
        }
    }

    private var chartXDomain: ClosedRange<Date> {
        switch chartRange {
        case .last7Days:
            return last7DaysStart ... last7DaysChartScaleEnd
        case .month:
            return viewMonthStart ... monthChartScaleEnd
        case .threeMonths:
            return threeMonthsStart ... threeMonthsChartScaleEnd
        }
    }

    /// Inclusive last day for the ideal-range band (scale end adds a day so points aren't clipped).
    private var chartXBandEnd: Date {
        switch chartRange {
        case .last7Days:
            return last7DaysChartEnd
        case .month:
            return monthChartEnd
        case .threeMonths:
            return threeMonthsChartEnd
        }
    }

    /// One mark per day in the 7-day window (explicit dates avoid extra grid lines from `.stride`).
    private var sevenDayMarkDates: [Date] {
        let cal = Calendar.current
        var dates: [Date] = []
        var day = last7DaysStart
        while day <= last7DaysChartEnd {
            dates.append(day)
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return dates
    }

    /// Month start, Mondays, and today (current month) so edge days aren't clipped from the plot.
    private var monthMarkDates: [Date] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: viewMonth) else { return [] }
        var dates = Set<Date>()
        let monthStart = cal.startOfDay(for: interval.start)
        dates.insert(monthStart)

        var day = monthStart
        while day <= monthChartEnd {
            if cal.component(.weekday, from: day) == 2 {
                dates.insert(day)
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        if isViewingCurrentMonth {
            dates.insert(todayStart)
        }

        return dates.sorted()
    }

    /// Mid-month anchors in the rolling 3-month window; partial current month uses its start.
    private var threeMonthMarkDates: [Date] {
        let cal = Calendar.current
        var dates: [Date] = []
        var monthStart = threeMonthsStart
        while monthStart <= threeMonthsChartEnd {
            let midMonth = cal.date(byAdding: .day, value: 14, to: monthStart) ?? monthStart
            if midMonth <= threeMonthsChartEnd {
                dates.append(midMonth)
            } else {
                dates.append(monthStart)
            }
            guard let next = cal.date(byAdding: .month, value: 1, to: monthStart) else { break }
            monthStart = next
        }
        return dates
    }

    private var xAxisMarkDates: [Date] {
        switch chartRange {
        case .month:
            return monthMarkDates
        case .last7Days:
            return sevenDayMarkDates
        case .threeMonths:
            return threeMonthMarkDates
        }
    }

    private var filteredDailyLogs: [HotTubDailyLog] {
        allDaily.filter { isInChartRange($0.loggedAt) }
            .sorted { $0.loggedAt < $1.loggedAt }
    }

    private var filteredUsageLogs: [UsageLogEntry] {
        allUsage.filter { isInChartRange($0.loggedAt) }
    }

    private var phMarks: [ChartPoint] {
        chemistryMarks(from: filteredDailyLogs) { $0.ph }
    }

    private var sanitizerMarks: [ChartPoint] {
        chemistryMarks(from: filteredDailyLogs) { $0.primarySanitizerPpm }
    }

    /// One chart point per calendar day (latest log wins when multiple entries share a day).
    private func chemistryMarks(
        from logs: [HotTubDailyLog],
        value: (HotTubDailyLog) -> Double?
    ) -> [ChartPoint] {
        let cal = Calendar.current
        var latestByDay: [Date: HotTubDailyLog] = [:]
        for log in logs {
            let day = cal.startOfDay(for: log.loggedAt)
            if let existing = latestByDay[day] {
                if log.loggedAt >= existing.loggedAt {
                    latestByDay[day] = log
                }
            } else {
                latestByDay[day] = log
            }
        }
        return latestByDay.values
            .sorted { $0.loggedAt < $1.loggedAt }
            .compactMap { log in
                guard let reading = value(log) else { return nil }
                let day = cal.startOfDay(for: log.loggedAt)
                return ChartPoint(id: log.persistentModelID, day: day, value: reading)
            }
    }

    private var sanitizerYDomain: ClosedRange<Double> {
        let ideal = sanitizerTarget
        return chemistryYDomain(
            marks: sanitizerMarks,
            idealRange: ideal,
            defaultLower: 0,
            defaultUpper: 6,
            padding: 0.5,
            roundTo: 1
        )
    }

    private var phYDomain: ClosedRange<Double> {
        chemistryYDomain(
            marks: phMarks,
            idealRange: phTarget,
            defaultLower: 6.8,
            defaultUpper: 8.2,
            padding: 0.2,
            roundTo: 0.1
        )
    }

    private func chemistryYDomain(
        marks: [ChartPoint],
        idealRange: ClosedRange<Double>,
        defaultLower: Double,
        defaultUpper: Double,
        padding: Double,
        roundTo: Double
    ) -> ClosedRange<Double> {
        guard !marks.isEmpty else {
            return defaultLower ... defaultUpper
        }

        let dataMin = marks.map(\.value).min() ?? idealRange.lowerBound
        let dataMax = marks.map(\.value).max() ?? idealRange.upperBound
        let rawLower = min(dataMin, idealRange.lowerBound)
        let rawUpper = max(dataMax, idealRange.upperBound)
        let spanPadding = max(padding, (rawUpper - rawLower) * 0.08)

        let paddedLower = roundDown(rawLower - spanPadding, to: roundTo)
        let paddedUpper = chemistryYUpperBound(rawUpper + spanPadding, roundTo: roundTo)
        return paddedLower ... max(paddedUpper, paddedLower + roundTo)
    }

    private func chemistryYUpperBound(_ value: Double, roundTo: Double) -> Double {
        if roundTo >= 1 {
            if value <= 10 {
                return roundUp(value, to: roundTo)
            }
            return ceil(value / 5) * 5
        }
        return roundUp(value, to: roundTo)
    }

    private func roundDown(_ value: Double, to step: Double) -> Double {
        guard step > 0 else { return value }
        return floor(value / step) * step
    }

    private func roundUp(_ value: Double, to step: Double) -> Double {
        guard step > 0 else { return value }
        return ceil(value / step) * step
    }

    private var usageBarPoints: [UserBarPoint] {
        let cal = Calendar.current
        var countByDay: [Date: Int] = [:]
        for log in filteredUsageLogs {
            let day = cal.startOfDay(for: log.loggedAt)
            countByDay[day, default: 0] += log.numUsers
        }
        return countByDay.keys.sorted().map { day in
            UserBarPoint(
                id: usageDayID(day),
                day: day,
                count: countByDay[day, default: 0]
            )
        }
    }

    private func usageDayID(_ day: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    private var hasData: Bool {
        !filteredDailyLogs.isEmpty || !filteredUsageLogs.isEmpty
    }

    private var hasVisibleChemicalSeries: Bool {
        !phMarks.isEmpty || !sanitizerMarks.isEmpty
    }

    private var summaryPeriodPhrase: String {
        switch chartRange {
        case .month:
            return "this month"
        case .last7Days:
            return "this week"
        case .threeMonths:
            return isViewingCurrentThreeMonths ? "in the last 3 months" : "in this period"
        }
    }

    private var chemistryChartHeight: CGFloat {
        usePadLayout ? PadContentLayout.chemistryChartHeightPad : PadContentLayout.chemistryChartHeightPhone
    }

    private var usersChartHeight: CGFloat {
        usePadLayout ? PadContentLayout.usersChartHeightPad : PadContentLayout.usersChartHeightPhone
    }

    var body: some View {
        ScrollView {
            chartsScrollContent
                .appAdaptiveScrollPadding(usePadLayout: usePadLayout)
                .padReadableContent(maxWidth: usePadLayout ? PadContentLayout.dashboardMaxWidth : PadContentLayout.readableMaxWidth)
        }
        .appGroupedScreenBackground(palette)
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            HotTubModelContainer.seedIfNeeded(in: modelContext)
            clampChartRangeIfNeeded()
        }
        .onChange(of: usePadLayout) { _, _ in
            clampChartRangeIfNeeded()
        }
        .helpSheet(presentedHelp: $presentedHelp, isBromine: isBromine, isMetric: isMetric)
    }

    @ViewBuilder
    private var chartsScrollContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            periodControls

            if !hasData {
                AppEmptyState(
                    symbol: "calendar",
                    title: emptyStatePeriodTitle,
                    message: "Add logs to see charts"
                )
            } else {
                chemistryChartsSection
                if !filteredUsageLogs.isEmpty {
                    usageChartsSection
                }
            }
        }
    }

    @ViewBuilder
    private var chemistryChartsSection: some View {
        if usePadLayout {
            VStack(alignment: .leading, spacing: AppSpacing.control) {
                HStack(alignment: .top, spacing: AppSpacing.control) {
                    sanitizerCompactChart
                        .frame(maxWidth: .infinity)
                    phCompactChart
                        .frame(maxWidth: .infinity)
                }
                if hasVisibleChemicalSeries {
                    chemistryStatusLegend
                }
            }
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.control) {
                sanitizerCompactChart
                phCompactChart
                if hasVisibleChemicalSeries {
                    chemistryStatusLegend
                }
            }
        }
    }

    private func clampChartRangeIfNeeded() {
        if !availableChartRanges.contains(chartRange) {
            chartRange = .month
        }
    }

    private var periodControls: some View {
        VStack(spacing: AppSpacing.control) {
            HStack(spacing: 8) {
                ForEach(availableChartRanges, id: \.self) { range in
                    rangePill(range)
                }
            }

            switch chartRange {
            case .month:
                monthNav
            case .last7Days:
                sevenDayNav
            case .threeMonths:
                threeMonthsPeriodControl
            }
        }
    }

    @ViewBuilder
    private var threeMonthsPeriodControl: some View {
        if threeMonthWindowIndices.count > 1 {
            threeMonthsNav
        } else {
            Text(threeMonthsLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.color(.textPrimary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
    }

    private var threeMonthsNav: some View {
        HStack(spacing: 8) {
            Button {
                shiftThreeMonthWindow(by: -1)
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canRetreatThreeMonthWindow ? palette.color(.accentBlue) : palette.color(.separator))
            }
            .disabled(!canRetreatThreeMonthWindow)
            .accessibilityLabel("Earlier 3 months")

            threeMonthWindowPicker
                .frame(maxWidth: .infinity)

            Button {
                shiftThreeMonthWindow(by: 1)
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canAdvanceThreeMonthWindow ? palette.color(.accentBlue) : palette.color(.separator))
            }
            .disabled(!canAdvanceThreeMonthWindow)
            .accessibilityLabel("Later 3 months")
        }
        .padding(.vertical, 4)
    }

    private var threeMonthWindowPicker: some View {
        Menu {
            ForEach(threeMonthWindowIndices, id: \.self) { index in
                Button {
                    threeMonthWindowIndex = index
                } label: {
                    if index == threeMonthWindowIndex {
                        Label(threeMonthWindowLabel(for: index), systemImage: "checkmark")
                    } else {
                        Text(threeMonthWindowLabel(for: index))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(threeMonthsLabel)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(palette.color(.accentBlue))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("3 month period, \(threeMonthsLabel)")
    }

    private func rangePill(_ range: ChartRange) -> some View {
        let selected = chartRange == range
        return Button {
            chartRange = range
            if range == .last7Days {
                sevenDayWeekStart = currentWeekMonday
            } else if range == .threeMonths {
                threeMonthWindowIndex = 0
            }
        } label: {
            Text(range.rawValue)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selected ? palette.color(.accentBlue).opacity(0.12) : palette.color(.surfaceCard))
                .foregroundStyle(selected ? palette.color(.accentBlue) : palette.color(.textPrimary))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            selected ? palette.color(.accentBlue) : palette.color(.separator),
                            lineWidth: selected ? 2 : 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var monthNav: some View {
        let canGoBack = viewMonthStart > (monthPickerOptions.first ?? viewMonthStart)
        let canGoForward = viewMonthStart < (monthPickerOptions.last ?? viewMonthStart)

        return HStack(spacing: 8) {
            Button {
                if let prev = Calendar.current.date(byAdding: .month, value: -1, to: viewMonthStart) {
                    viewMonth = prev
                }
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canGoBack ? palette.color(.accentBlue) : palette.color(.separator))
            }
            .disabled(!canGoBack)

            monthPeriodPicker
                .frame(maxWidth: .infinity)

            Button {
                if let next = Calendar.current.date(byAdding: .month, value: 1, to: viewMonthStart) {
                    viewMonth = next
                }
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canGoForward ? palette.color(.accentBlue) : palette.color(.separator))
            }
            .disabled(!canGoForward)
        }
        .padding(.vertical, 4)
    }

    private var monthPeriodPicker: some View {
        Picker(
            "Month",
            selection: Binding(
                get: { viewMonthStart },
                set: { viewMonth = $0 }
            )
        ) {
            ForEach(monthPickerOptions, id: \.self) { monthStart in
                Text(monthPickerLabel(for: monthStart)).tag(monthStart)
            }
        }
        .pickerStyle(.menu)
        .tint(palette.color(.accentBlue))
    }

    private var sevenDayNav: some View {
        HStack(spacing: 8) {
            Button {
                shiftSevenDayWindow(by: -7)
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
                    .foregroundStyle(palette.color(.accentBlue))
            }

            weekPeriodPicker
                .frame(maxWidth: .infinity)

            Button {
                shiftSevenDayWindow(by: 7)
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canAdvanceSevenDayWindow ? palette.color(.accentBlue) : palette.color(.separator))
            }
            .disabled(!canAdvanceSevenDayWindow)
        }
        .padding(.vertical, 4)
    }

    private var weekPeriodPicker: some View {
        Menu {
            ForEach(weekPickerOptions, id: \.self) { monday in
                Button {
                    sevenDayWeekStart = monday
                } label: {
                    if Calendar.current.isDate(monday, inSameDayAs: selectedWeekStart) {
                        Label(weekPickerLabel(for: monday), systemImage: "checkmark")
                    } else {
                        Text(weekPickerLabel(for: monday))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(weekPickerLabel(for: selectedWeekStart))
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(palette.color(.accentBlue))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
    }

    private func monthPickerLabel(for monthStart: Date) -> String {
        let formatter = DateFormatter()
        let cal = Calendar.current
        if cal.component(.year, from: monthStart) == cal.component(.year, from: todayStart) {
            formatter.dateFormat = "MMMM"
        } else {
            formatter.dateFormat = "MMMM yyyy"
        }
        return formatter.string(from: monthStart)
    }

    private func weekPickerLabel(for weekStart: Date) -> String {
        if Calendar.current.isDate(weekStart, inSameDayAs: currentWeekMonday) {
            return "This week"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return "Week of \(formatter.string(from: weekStart))"
    }

    private var earliestChartLogDate: Date? {
        let daily = allDaily.map(\.loggedAt).min()
        let usage = allUsage.map(\.loggedAt).min()
        switch (daily, usage) {
        case let (dailyDate?, usageDate?):
            return min(dailyDate, usageDate)
        case let (dailyDate?, nil):
            return dailyDate
        case let (nil, usageDate?):
            return usageDate
        case (nil, nil):
            return nil
        }
    }

    private func threeMonthBounds(for index: Int) -> (start: Date, end: Date) {
        let lastMonth = ChartsThreeMonthWindow.lastMonthStart(
            index: index,
            anchorMonth: currentThreeMonthAnchor
        )
        let start = ChartsThreeMonthWindow.start(lastMonthStart: lastMonth)
        let end = ChartsThreeMonthWindow.dataEnd(
            lastMonthStart: lastMonth,
            index: index,
            today: todayStart
        )
        return (start, end)
    }

    private func threeMonthWindowLabel(for index: Int) -> String {
        let bounds = threeMonthBounds(for: index)
        return formattedThreeMonthRange(start: bounds.start, end: bounds.end)
    }

    private func formattedThreeMonthRange(start: Date, end: Date) -> String {
        let calendar = Calendar.current
        let startFormatter = DateFormatter()
        let endFormatter = DateFormatter()
        endFormatter.dateFormat = "d MMM yyyy"
        if calendar.component(.year, from: start) == calendar.component(.year, from: end) {
            startFormatter.dateFormat = "d MMM"
        } else {
            startFormatter.dateFormat = "d MMM yyyy"
        }
        return "\(startFormatter.string(from: start)) – \(endFormatter.string(from: end))"
    }

    private func shiftThreeMonthWindow(by steps: Int) {
        let next = threeMonthWindowIndex + steps
        threeMonthWindowIndex = min(0, max(earliestThreeMonthIndex, next))
    }

    private func shiftSevenDayWindow(by days: Int) {
        let cal = Calendar.current
        guard let shifted = cal.date(byAdding: .day, value: days, to: selectedWeekStart) else { return }
        let normalized = ChartsWeekCalendar.mondayContaining(shifted)
        if days > 0 {
            sevenDayWeekStart = min(normalized, currentWeekMonday)
        } else if let earliest = weekPickerOptions.last {
            sevenDayWeekStart = max(normalized, earliest)
        } else {
            sevenDayWeekStart = normalized
        }
    }

    private var sanitizerCompactChart: some View {
        let ideal = sanitizerTarget
        let subtitle = "Your target \(WaterChemistryRanges.targetLabel(ideal, unit: "ppm"))"
        return compactChemistryChart(
            title: sanitizerLabel,
            subtitle: subtitle,
            tips: sanitizerGuideBullets,
            helpRequest: .sanitizer(.overview),
            marks: sanitizerMarks,
            idealRange: ideal,
            yDomain: sanitizerYDomain,
            yAxisFormat: { String(format: "%.0f", $0) },
            status: sanitizerReadingStatus(for:),
            emptyMessage: "No \(sanitizerLabel.lowercased()) readings in \(noDataPeriodPhrase)."
        )
    }

    private func sanitizerReadingStatus(for value: Double) -> WaterChemistryReadingStatus {
        WaterChemistryRanges.readingStatus(value: value, target: sanitizerTarget)
    }

    private var phCompactChart: some View {
        compactChemistryChart(
            title: "pH",
            subtitle: "Your target \(WaterChemistryRanges.targetLabel(phTarget))",
            tips: phGuideBullets,
            helpRequest: .ph(.overview),
            marks: phMarks,
            idealRange: phTarget,
            yDomain: phYDomain,
            yAxisFormat: { String(format: "%.1f", $0) },
            status: { WaterChemistryRanges.readingStatus(value: $0, target: phTarget) },
            emptyMessage: "No pH readings in \(noDataPeriodPhrase)."
        )
    }

    private var chemistryStatusLegend: some View {
        HStack(spacing: 16) {
            statusLegendItem(color: palette.color(.accentGreen), label: "Within range")
            statusLegendItem(color: palette.color(.accentOrange), label: "Outside range")
        }
        .font(.caption)
        .foregroundStyle(palette.color(.textSecondary))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusLegendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
        }
    }

    private func compactChemistryChart(
        title: String,
        subtitle: String,
        tips: [String],
        helpRequest: HelpSheetRequest,
        marks: [ChartPoint],
        idealRange: ClosedRange<Double>,
        yDomain: ClosedRange<Double>,
        yAxisFormat: @escaping (Double) -> String,
        status: @escaping (Double) -> WaterChemistryReadingStatus,
        emptyMessage: String
    ) -> some View {
        chartCard(title: title, tips: tips, helpRequest: helpRequest) {
            if marks.isEmpty {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(palette.color(.textSecondary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 120)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(palette.color(.textSecondary))

                    Chart {
                        RectangleMark(
                            xStart: .value("Start", chartXDomain.lowerBound, unit: .day),
                            xEnd: .value("End", chartXBandEnd, unit: .day),
                            yStart: .value("Target low", idealRange.lowerBound),
                            yEnd: .value("Target high", idealRange.upperBound)
                        )
                        .foregroundStyle(palette.color(.statusSuccessFill))

                        if marks.count >= 2 {
                            ForEach(marks) { mark in
                                LineMark(
                                    x: .value("Day", mark.day, unit: .day),
                                    y: .value(title, mark.value)
                                )
                                .foregroundStyle(palette.color(.separator).opacity(0.6))
                                .interpolationMethod(.catmullRom)
                            }
                        }

                        ForEach(marks) { mark in
                            PointMark(
                                x: .value("Day", mark.day, unit: .day),
                                y: .value(title, mark.value)
                            )
                            .foregroundStyle(
                                WaterChemistryRanges.statusColor(status(mark.value), palette: palette)
                            )
                            .symbolSize(44)
                        }
                    }
                    .chartYScale(domain: yDomain)
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                                .foregroundStyle(palette.color(.separator).opacity(0.4))
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text(yAxisFormat(v))
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        chartXAxisMarks(showLabels: true, showGrid: true)
                    }
                    .chartXScale(domain: chartXDomain)
                    .chartPlotStyle { plotArea in
                        plotArea.clipShape(Rectangle())
                    }
                    .frame(height: chemistryChartHeight)
                }
            }
        }
    }

    @AxisContentBuilder
    private func chartXAxisMarks(showLabels: Bool, showGrid: Bool) -> some AxisContent {
        AxisMarks(values: xAxisMarkDates) { _ in
            if showGrid {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(palette.color(.separator).opacity(0.5))
            }
            if showLabels {
                if chartRange == .threeMonths {
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                } else {
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
        }
    }

    private var suspiciousUsageLogs: [UsageLogEntry] {
        UsageLogDiagnostics.entriesMatchingSanitizerPPM(
            usage: filteredUsageLogs,
            daily: allDaily
        )
    }

    private var usageSessionCount: Int {
        filteredUsageLogs.count
    }

    @ViewBuilder
    private var usageChartsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.control) {
            if !suspiciousUsageLogs.isEmpty {
                usageMismatchBanner
            }

            usersChart
        }
    }

    private var usageMismatchBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(palette.color(.accentOrange))
            VStack(alignment: .leading, spacing: 4) {
                Text("These may not be real usage sessions")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.color(.textPrimary))
                Text(usageMismatchMessage)
                    .font(.caption)
                    .foregroundStyle(palette.color(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.cardRadius, style: .continuous)
                .fill(palette.color(.accentOrange).opacity(0.12))
        )
    }

    private var usageMismatchMessage: String {
        if suspiciousUsageLogs.count == filteredUsageLogs.count {
            return "The people counts match your chlorine readings on the same days — likely imported or logged by mistake. Check History → Usage, or delete them there."
        }
        return "\(suspiciousUsageLogs.count) session\(suspiciousUsageLogs.count == 1 ? "" : "s") match chlorine readings on the same day. Review them in History → Usage."
    }

    private var usageChartSubtitle: String {
        let sessions = usageSessionCount
        let sessionPhrase = "\(sessions) session\(sessions == 1 ? "" : "s") logged \(summaryPeriodPhrase)"
        if sessions == 1, let only = filteredUsageLogs.first {
            return "\(sessionPhrase) · \(only.numUsers) \(only.numUsers == 1 ? "person" : "people")"
        }
        return sessionPhrase
    }

    private var usersChart: some View {
        let barPoints = usageBarPoints
        return chartCard(title: "Hot tub use per day", subtitle: usageChartSubtitle, tips: usageGuideBullets) {
            if barPoints.isEmpty {
                Text("No usage logs from \(noDataPeriodPhrase)")
                    .font(.caption)
                    .foregroundStyle(palette.color(.textSecondary))
                    .frame(height: 200)
            } else {
                Chart {
                    ForEach(barPoints) { p in
                        BarMark(
                            x: .value("Day", p.day, unit: .day),
                            y: .value("Users", p.count)
                        )
                        .foregroundStyle(palette.color(.accentOrange).opacity(0.85))
                    }
                }
                .chartXAxis {
                    chartXAxisMarks(showLabels: true, showGrid: true)
                }
                .chartXScale(domain: chartXDomain)
                .frame(height: usersChartHeight)
            }
        }
    }

    private var sanitizerGuideBullets: [String] {
        let target = WaterChemistryRanges.targetLabel(sanitizerTarget, unit: "ppm")
        return [
            "Your target: \(target)",
            "The band on the chart is the \(sanitizerLabel.lowercased()) target you saved.",
            "Points outside that band are below or above your target.",
        ]
    }

    private var phGuideBullets: [String] {
        [
            "Your target: \(WaterChemistryRanges.targetLabel(phTarget))",
            "The band on the chart is the pH target you saved.",
            "Points outside that band are below or above your target.",
        ]
    }

    private var usageGuideBullets: [String] {
        [
            "Track how many people use your hot tub daily.",
            "Higher usage may require more frequent chemical adjustments.",
            "Test water quality after heavy use sessions.",
        ]
    }

    private func chartCard<Content: View>(
        title: String,
        subtitle: String? = nil,
        tips: [String] = [],
        helpRequest: HelpSheetRequest? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.control) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(palette.color(.textPrimary))
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(palette.color(.textSecondary))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !tips.isEmpty {
                    ChartTipsButton(
                        title: title,
                        bullets: tips,
                        helpRequest: helpRequest,
                        presentedHelp: $presentedHelp
                    )
                }
            }
            content()
        }
        .appCard(palette: palette, radius: AppSpacing.largeCardRadius)
    }
}

private struct ChartTipsButton: View {
    let title: String
    let bullets: [String]
    var helpRequest: HelpSheetRequest?
    @Binding var presentedHelp: HelpSheetRequest?

    @State private var isPresented = false
    @Environment(\.appPalette) private var palette

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "lightbulb")
                Text("Tip")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.color(.accentBlue))
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(Capsule().fill(palette.color(.tagBlueFill)))
            .frame(minWidth: 44, minHeight: 44, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) tips")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            tipPopover
                .presentationCompactAdaptation(.popover)
        }
    }

    private var tipPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(palette.color(.accentBlue))
                Text("Tips")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.color(.textPrimary))
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(palette.color(.accentBlue))
                        Text(bullet)
                            .font(.caption)
                            .foregroundStyle(palette.color(.textSecondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let helpRequest {
                Button {
                    let request = helpRequest
                    isPresented = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(250))
                        presentedHelp = request
                    }
                } label: {
                    Text("Open guide")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.color(.accentBlue))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 280, alignment: .leading)
    }
}

// MARK: - Calendar week helpers

private enum ChartsWeekCalendar {
    static func mondayContaining(_ date: Date) -> Date {
        let cal = Calendar.current
        var day = cal.startOfDay(for: date)
        while cal.component(.weekday, from: day) != 2 {
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return day
    }

    static func weekSunday(forWeekStarting monday: Date) -> Date {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: 6, to: cal.startOfDay(for: monday)) ?? monday
    }

    static func weekDataEnd(forWeekStarting monday: Date, cappedTo today: Date) -> Date {
        min(weekSunday(forWeekStarting: monday), Calendar.current.startOfDay(for: today))
    }
}

// MARK: - Three-month window

private enum ChartsThreeMonthWindow {
    static func anchorMonth(containing date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(from: calendar.dateComponents([.year, .month], from: start)) ?? start
    }

    static func lastMonthStart(index: Int, anchorMonth: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: index * 3, to: anchorMonth) ?? anchorMonth
    }

    static func start(lastMonthStart: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: -2, to: lastMonthStart) ?? lastMonthStart
    }

    /// Inclusive last day. The current window ends today; earlier windows end on the last day of their final month.
    static func dataEnd(lastMonthStart: Date, index: Int, today: Date, calendar: Calendar = .current) -> Date {
        if index >= 0 {
            return calendar.startOfDay(for: today)
        }
        guard let interval = calendar.dateInterval(of: .month, for: lastMonthStart) else {
            return lastMonthStart
        }
        let last = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
        return calendar.startOfDay(for: last)
    }

    /// Window index that contains the earliest log. 0 when every reading is already in the current window.
    static func earliestIndex(earliest: Date?, anchorMonth: Date, calendar: Calendar = .current) -> Int {
        guard let earliest else { return 0 }
        let earliestMonth = Self.anchorMonth(containing: earliest, calendar: calendar)
        let monthDelta = calendar.dateComponents([.month], from: earliestMonth, to: anchorMonth).month ?? 0
        if monthDelta <= 2 { return 0 }
        return -Int(ceil(Double(monthDelta - 2) / 3.0))
    }
}
