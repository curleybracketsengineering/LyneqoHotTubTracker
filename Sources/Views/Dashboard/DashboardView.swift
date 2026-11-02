//
//  DashboardView.swift
//  HotTub
//

import Combine
import SwiftData
import SwiftUI
import UIKit

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appPalette) private var palette
    @Environment(\.usePadLayout) private var usePadLayout
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var notificationService = ReminderNotificationService.shared
    @StateObject private var viewModel = DashboardViewModel()
    @Query(sort: \HotTubDailyLog.loggedAt, order: .reverse) private var dailyLogsSnapshot: [HotTubDailyLog]

    @State private var showNotificationSettings = false
    @State private var showNotificationsDeniedAlert = false
    @State private var navigateToDailyLog = false
    @State private var navigateToWeeklyCheck = false
    @State private var navigateToMaintenancePreset: MaintenanceLogPreset?

    var body: some View {
        ScrollView {
            Group {
                if usePadLayout {
                    padDashboardContent
                } else {
                    phoneDashboardContent
                }
            }
            .appAdaptiveScrollPadding(usePadLayout: usePadLayout)
            .padReadableContent(maxWidth: usePadLayout ? PadContentLayout.dashboardMaxWidth : PadContentLayout.readableMaxWidth)
        }
        .appGroupedScreenBackground(palette)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            viewModel.reload(context: modelContext)
            guard !PreviewEnvironment.isActive else { return }
            await notificationService.refreshAuthorizationStatus()
            await notificationService.reschedule(context: modelContext)
        }
        .onAppear { viewModel.reload(context: modelContext) }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            viewModel.reload(context: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: .hotTubLocalStoreDidChange)) { _ in
            viewModel.reload(context: modelContext)
        }
        .onChange(of: dailyLogsSnapshot.map(dailyLogRevision)) { _, _ in
            viewModel.reload(context: modelContext)
        }
        .refreshable {
            viewModel.reload(context: modelContext)
            guard !PreviewEnvironment.isActive else { return }
            await notificationService.reschedule(context: modelContext)
        }
        .sheet(isPresented: $showNotificationSettings) {
            NotificationSettingsSheet(notificationService: notificationService)
        }
        .alert("Notifications are off", isPresented: $showNotificationsDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Turn on notifications in Settings to get maintenance reminders.")
        }
        .navigationDestination(isPresented: $navigateToDailyLog) {
            DailyLogFormView()
        }
        .navigationDestination(isPresented: $navigateToWeeklyCheck) {
            WeeklyLogFormView()
        }
        .navigationDestination(item: $navigateToMaintenancePreset) { preset in
            MaintenanceLogFormView(preset: preset)
        }
        .onChange(of: notificationService.pendingDestination) { _, destination in
            guard let destination else { return }
            switch destination {
            case .dailyLog:
                navigateToDailyLog = true
            case .weeklyCheck:
                navigateToWeeklyCheck = true
            case .maintenanceFilterRinse:
                navigateToMaintenancePreset = .filterRinse
            case .maintenanceFilterChange:
                navigateToMaintenancePreset = .filterChange
            case .maintenanceWaterChange:
                navigateToMaintenancePreset = .waterChange
            }
            notificationService.pendingDestination = nil
        }
    }

    private var phoneDashboardContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            dashboardHeader
            statusCard
            actionsSection
            recentRecordsSection
            remindersSection
            homeFooter
        }
    }

    private var padDashboardContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            dashboardHeader
            padStatusBanner
            padMainActionButton
            padSecondaryActions

            HStack(alignment: .top, spacing: AppSpacing.section) {
                padRecentRecordsColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
                padRemindersColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            homeFooter
        }
    }

    // MARK: - iPad hero banner

    private var padStatusBanner: some View {
        let status = viewModel.homeStatus(log: viewModel.latestDailyLog)

        return ZStack {
            statusCardGradient(for: status)

            PadHeroWaveDecoration()
                .opacity(0.18)

            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "drop.fill")
                            .font(.title2)
                            .foregroundStyle(palette.color(.accentBlue))
                            .frame(width: 48, height: 48)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        HomeStatusCopy(status: status, palette: palette, linksDueReminder: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 16)

                padHeroDivider

                HomeReadingColumn(reading: status.sanitizer, showsGauge: true, valueFont: .title2.weight(.bold))
                    .padding(.horizontal, 16)

                padHeroDivider

                HomeReadingColumn(reading: status.ph, showsGauge: true, valueFont: .title2.weight(.bold))
                    .padding(.leading, 16)
            }
            .padding(24)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.largeCardRadius, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }

    private var padHeroDivider: some View {
        Rectangle()
            .fill(palette.color(.onAccent).opacity(0.22))
            .frame(width: 1)
            .frame(maxHeight: 140)
    }

    private var padMainActionButton: some View {
        NavigationLink {
            DailyLogFormView()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "drop.fill")
                    .font(.title3)
                Text("Record water test")
                    .font(.headline)
            }
            .foregroundStyle(palette.color(.onAccent))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(palette.color(.accentBlue))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var padSecondaryActions: some View {
        EqualSizeRow(spacing: AppSpacing.control) {
            padActionCard(kind: .usage, destination: UsageLogFormView())
            padActionCard(kind: .weekly, destination: WeeklyLogFormView())
            padActionCard(kind: .maintenance, destination: MaintenanceLogFormView())
        }
    }

    private func padActionCard<D: View>(kind: ActivityLogKind, destination: D) -> some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 12) {
                Image(systemName: kind.tileSystemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(palette.color(kind.iconToken))
                    .frame(width: 44, height: 44)
                    .background(palette.color(kind.fillToken))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.padActionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.color(.textPrimary))
                        .lineLimit(2, reservesSpace: true)
                    Text(kind.padActionSubtitle)
                        .font(.caption)
                        .foregroundStyle(palette.color(.textSecondary))
                        .lineLimit(2, reservesSpace: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.color(.textTertiary))
            }
            .appCard(palette: palette, radius: AppSpacing.largeCardRadius, fillsHeight: true)
        }
        .buttonStyle(.plain)
    }

    // MARK: - iPad columns

    private var padRecentRecordsColumn: some View {
        VStack(alignment: .leading, spacing: AppSpacing.control) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent records")
                    .font(.headline)
                    .foregroundStyle(palette.color(.textPrimary))
                Spacer()
                NavigationLink("View all records") {
                    HistoryView(isTabRoot: false)
                }
                .font(.subheadline.weight(.medium))
            }

            if viewModel.recentRecords.isEmpty {
                AppEmptyState(
                    symbol: "clock.arrow.circlepath",
                    title: "No records yet",
                    message: "Log a daily reading or weekly check to see it here."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.recentRecords.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            AppSettingsDivider()
                        }
                        padCompactActivityLink(item)
                    }
                }
                .appCard(palette: palette, padding: 0)

                NavigationLink {
                    HistoryView(isTabRoot: false)
                } label: {
                    Text("View all records")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.color(.accentBlue))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }

    private func padCompactActivityLink(_ item: DashboardActivity) -> some View {
        NavigationLink {
            activityDetail(item)
        } label: {
            ActivityRowView(
                row: item.historyRow,
                isBromine: viewModel.isBromine,
                palette: palette,
                phTarget: viewModel.phTarget,
                sanitizerTarget: viewModel.sanitizerTarget
            )
                .padding(12)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                viewModel.delete(item, context: modelContext)
                Task { await notificationService.reschedule(context: modelContext) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var padRemindersColumn: some View {
        remindersCard
    }

    private var remindersCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.control) {
            HStack(alignment: .firstTextBaseline) {
                Text("Reminders")
                    .font(.headline)
                    .foregroundStyle(palette.color(.textPrimary))
                Spacer()
                NavigationLink {
                    SetupView()
                } label: {
                    Text("Manage")
                        .font(.subheadline.weight(.medium))
                }
            }

            if viewModel.dueReminders.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.title2)
                        .foregroundStyle(palette.color(.accentGreen))
                    Text("All caught up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.color(.textPrimary))
                    Text("No maintenance tasks due in the next two weeks.")
                        .font(.caption)
                        .foregroundStyle(palette.color(.textSecondary))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard(palette: palette)
            } else {
                VStack(spacing: AppSpacing.control) {
                    ForEach(viewModel.dueReminders) { reminder in
                        reminderCard(reminder)
                    }
                }
            }
        }
    }

    private func reminderCard(_ reminder: HomeReminder) -> some View {
        let urgency = reminder.urgency()
        let colors = reminderColors(for: urgency)

        return NavigationLink {
            reminderDestination(reminder.kind)
        } label: {
            HStack(spacing: AppSpacing.control) {
                Image(systemName: reminder.kind.systemImage(urgency: urgency))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(colors.icon)
                    .frame(width: 40, height: 40)
                    .background(colors.iconBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(reminder.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.color(.textPrimary))
                    Text(reminder.padSubtitle())
                        .font(.caption)
                        .foregroundStyle(palette.color(.textSecondary))
                }

                Spacer(minLength: 8)

                Text(reminder.badgeLabel())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(colors.badgeText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(colors.badgeBackground)
                    .clipShape(Capsule())

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.color(.textTertiary))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppSpacing.cardRadius, style: .continuous)
                    .fill(colors.background)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppSpacing.cardRadius, style: .continuous)
                    .strokeBorder(colors.border.opacity(0.5), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private struct ReminderCardColors {
        let background: Color
        let border: Color
        let icon: Color
        let iconBackground: Color
        let badgeBackground: Color
        let badgeText: Color
    }

    private func reminderColors(for urgency: HomeReminder.Urgency) -> ReminderCardColors {
        switch urgency {
        case .overdue:
            return ReminderCardColors(
                background: palette.color(.statusErrorFill),
                border: palette.color(.statusErrorBorder),
                icon: palette.color(.accentRed),
                iconBackground: palette.color(.statusErrorFill),
                badgeBackground: palette.color(.accentRed).opacity(0.16),
                badgeText: palette.color(.statusErrorText)
            )
        case .dueToday:
            return ReminderCardColors(
                background: palette.color(.statusWarningFill),
                border: palette.color(.statusWarningBorder),
                icon: palette.color(.accentOrange),
                iconBackground: palette.color(.statusWarningFill),
                badgeBackground: palette.color(.accentOrange).opacity(0.16),
                badgeText: palette.color(.statusWarningText)
            )
        case .upcoming:
            return ReminderCardColors(
                background: palette.color(.accentBlue).opacity(0.08),
                border: palette.color(.accentBlue).opacity(0.25),
                icon: palette.color(.accentBlue),
                iconBackground: palette.color(.accentBlue).opacity(0.12),
                badgeBackground: palette.color(.accentBlue).opacity(0.12),
                badgeText: palette.color(.accentBlue)
            )
        }
    }

    private var homeFooter: some View {
        let status = viewModel.homeStatus(log: viewModel.latestDailyLog)
        return HStack(alignment: .top, spacing: 12) {
            Text(status.footer)
                .font(.caption)
                .foregroundStyle(palette.color(.textSecondary))
                .frame(maxWidth: .infinity, alignment: .leading)

            TargetRangesInfoLink(palette: palette)
        }
    }

    private var statusCard: some View {
        let status = viewModel.homeStatus(log: viewModel.latestDailyLog)

        return VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "drop.fill")
                .font(.title2)
                .foregroundStyle(palette.color(.onAccent))
                .padding(10)
                .background(Color.white.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HomeStatusCopy(status: status, palette: palette, linksDueReminder: true)

            HStack(alignment: .top, spacing: 0) {
                HomeReadingColumn(reading: status.sanitizer, showsGauge: false, valueFont: .title3.weight(.bold))
                Rectangle()
                    .fill(palette.color(.onAccent).opacity(0.25))
                    .frame(width: 1)
                    .padding(.vertical, 4)
                HomeReadingColumn(reading: status.ph, showsGauge: false, valueFont: .title3.weight(.bold))
                    .padding(.leading, 16)
            }
        }
        .padding(20)
        .background(statusCardGradient(for: status))
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.largeCardRadius, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
        .animation(.spring(response: 0.35), value: status)
    }

    private func statusCardGradient(for status: HomeStatusPresentation) -> LinearGradient {
        let colors: [Color]
        if !status.hasData {
            colors = [palette.color(.heroEmptyStart), palette.color(.heroEmptyEnd)]
        } else if status.readingsOutsideTarget {
            colors = [
                palette.color(.accentIndigo),
                palette.color(.accentBlue).opacity(0.88),
            ]
        } else if status.isDue {
            colors = [
                palette.color(.heroEmptyStart),
                palette.color(.heroEmptyEnd).opacity(0.88),
            ]
        } else {
            colors = [
                palette.color(.accentBlue),
                palette.color(.accentIndigo).opacity(0.92),
            ]
        }
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var actionsSection: some View {
        VStack(spacing: AppSpacing.control) {
            mainActionButton
            subActionRow
        }
    }

    private var mainActionButton: some View {
        NavigationLink {
            DailyLogFormView()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                Text("Record water test")
                    .font(.headline)
            }
            .foregroundStyle(palette.color(.onAccent))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .background(palette.color(.accentBlue))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var subActionRow: some View {
        HStack(spacing: AppSpacing.control) {
           

            NavigationLink {
                UsageLogFormView()
            } label: {
                subActionTile(
                    title: "Log hot-tub usage",
                    systemImage: ActivityLogKind.usage.systemImage,
                    fillToken: ActivityLogKind.usage.fillToken,
                    iconToken: ActivityLogKind.usage.iconToken
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                WeeklyLogFormView()
            } label: {
                subActionTile(
                    title: "Full water check",
                    systemImage: ActivityLogKind.weekly.systemImage,
                    fillToken: ActivityLogKind.weekly.fillToken,
                    iconToken: ActivityLogKind.weekly.iconToken
                )
            }
            .buttonStyle(.plain)
            
            NavigationLink {
                MaintenanceLogFormView()
            } label: {
                subActionTile(
                    title: "Service",
                    systemImage: ActivityLogKind.maintenance.systemImage,
                    fillToken: ActivityLogKind.maintenance.fillToken,
                    iconToken: ActivityLogKind.maintenance.iconToken
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func subActionTile(
        title: String,
        systemImage: String,
        fillToken: PaletteToken,
        iconToken: PaletteToken
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(palette.color(iconToken))
                .frame(width: AppSpacing.minTap, height: AppSpacing.minTap)
                .background(palette.color(fillToken))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.color(.textPrimary))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .appCard(palette: palette, radius: AppSpacing.largeCardRadius)
    }

    private var recentRecordsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.control) {
            HStack(alignment: .firstTextBaseline) {
                AppSectionHeader(title: "Recent records")
                Spacer()
                NavigationLink("View all records") {
                    HistoryView(isTabRoot: false)
                }
                .font(.subheadline.weight(.medium))
            }

            if viewModel.recentRecords.isEmpty {
                AppEmptyState(
                    symbol: "clock.arrow.circlepath",
                    title: "No records yet",
                    message: "Log a daily reading or weekly check to see it here."
                )
            } else {
                ForEach(viewModel.recentRecords) { item in
                    activityRow(item)
                }
            }
        }
    }

    @ViewBuilder
    private var remindersSection: some View {
        remindersCard
    }

    @ViewBuilder
    private func reminderDestination(_ kind: ReminderKind) -> some View {
        switch kind {
        case .dailyWaterTest:
            DailyLogFormView()
        case .weeklyWaterCheck:
            WeeklyLogFormView()
        case .filterRinse:
            MaintenanceLogFormView(preset: .filterRinse)
        case .filterChange:
            MaintenanceLogFormView(preset: .filterChange)
        case .waterChange:
            MaintenanceLogFormView(preset: .waterChange)
        }
    }

    private func activityRow(_ item: DashboardActivity) -> some View {
        NavigationLink {
            activityDetail(item)
        } label: {
            ActivityRowView(
                row: item.historyRow,
                isBromine: viewModel.isBromine,
                palette: palette,
                phTarget: viewModel.phTarget,
                sanitizerTarget: viewModel.sanitizerTarget
            )
                .appCard(palette: palette, padding: 12)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                viewModel.delete(item, context: modelContext)
                Task { await notificationService.reschedule(context: modelContext) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func activityDetail(_ item: DashboardActivity) -> some View {
        switch item {
        case .daily(let log):
            DailyLogFormView(existing: log)
        case .weekly(let log):
            WeeklyLogFormView(existing: log)
        case .maintenance(let log):
            MaintenanceLogFormView(existing: log)
        case .usage(let log):
            UsageLogFormView(existing: log)
        }
    }

    private var dashboardHeader: some View {
        HStack(alignment: .center, spacing: AppSpacing.control) {
            Text("Home")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(palette.color(.textPrimary))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: AppSpacing.control)

            notificationBellButton
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notificationBellButton: some View {
        Button {
            Task { await handleBellTap() }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.body.weight(.semibold))
                    .frame(width: AppSpacing.minTap, height: AppSpacing.minTap)

                if !viewModel.dueReminders.isEmpty {
                    Text("\(min(viewModel.dueReminders.count, 9))")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(notificationBadgeColor)
                        .clipShape(Circle())
                        .offset(x: 4, y: -4)
                }
            }
            .padding(.top, 4)
            .padding(.trailing, 4)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(palette.color(.surfaceCard))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Notifications")
    }

    /// Badge follows the most urgent reminder in the two-week window.
    private var notificationBadgeColor: Color {
        let urgencies = viewModel.dueReminders.map { $0.urgency() }
        if urgencies.contains(.overdue) {
            return palette.color(.accentRed)
        }
        if urgencies.contains(.dueToday) {
            return palette.color(.accentOrange)
        }
        return palette.color(.accentBlue)
    }

    private func handleBellTap() async {
        await notificationService.refreshAuthorizationStatus()
        switch notificationService.authorizationStatus {
        case .notDetermined:
            let granted = await notificationService.requestAuthorization()
            if !granted {
                showNotificationsDeniedAlert = true
            }
        case .denied:
            showNotificationsDeniedAlert = true
        default:
            showNotificationSettings = true
        }
    }

    private func dailyLogRevision(_ log: HotTubDailyLog) -> String {
        "\(log.persistentModelID)-\(log.loggedAt.timeIntervalSince1970)-\(log.ph ?? -1)-\(log.sanitizerFree ?? -1)"
    }
}

private struct NotificationSettingsSheet: View {
    @ObservedObject var notificationService: ReminderNotificationService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appPalette) private var palette

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Water test reminders", isOn: Binding(
                        get: { notificationService.remindersEnabled },
                        set: { notificationService.remindersEnabled = $0 }
                    ))
                } footer: {
                    Text("Get reminded when a scheduled maintenance task is due.")
                }

                if notificationService.remindersEnabled {
                    Section("Reminder time") {
                        DatePicker(
                            "Time",
                            selection: Binding(
                                get: { notificationService.preferredReminderTime },
                                set: { notificationService.preferredReminderTime = $0 }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                    }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .appPalette(palette.colorScheme)
    }
}

#Preview {
    NavigationStack {
        DashboardView()
    }
    .modelContainer(HotTubModelContainer.preview)
    .appPalette(.light)
}

/// Gives every child the same width and the same height inside a horizontal row.
private struct EqualSizeRow: Layout {
    var spacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let count = subviews.count
        guard count > 0 else { return .zero }

        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? idealWidth(subviews)
        let childProposal = ProposedViewSize(width: itemWidth(in: width, count: count), height: nil)
        let height = subviews.map { $0.sizeThatFits(childProposal).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let count = subviews.count
        guard count > 0 else { return }

        let width = itemWidth(in: bounds.width, count: count)
        let childProposal = ProposedViewSize(width: width, height: bounds.height)
        var x = bounds.minX
        for subview in subviews {
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: childProposal)
            x += width + spacing
        }
    }

    private func itemWidth(in totalWidth: CGFloat, count: Int) -> CGFloat {
        let spaces = spacing * CGFloat(max(count - 1, 0))
        return max(0, (totalWidth - spaces) / CGFloat(count))
    }

    private func idealWidth(_ subviews: Subviews) -> CGFloat {
        let widest = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        return widest * CGFloat(subviews.count) + spacing * CGFloat(max(subviews.count - 1, 0))
    }
}

// MARK: - iPad dashboard decorations

private struct PadHeroWaveDecoration: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let w = geometry.size.width
                let h = geometry.size.height
                path.move(to: CGPoint(x: 0, y: h * 0.72))
                path.addCurve(
                    to: CGPoint(x: w, y: h * 0.55),
                    control1: CGPoint(x: w * 0.25, y: h * 0.95),
                    control2: CGPoint(x: w * 0.72, y: h * 0.35)
                )
                path.addLine(to: CGPoint(x: w, y: h))
                path.addLine(to: CGPoint(x: 0, y: h))
                path.closeSubpath()
            }
            .fill(Color.white)
        }
    }
}

private struct TargetRangesInfoLink: View {
    let palette: AppPalette
    @State private var isPresented = false

    var body: some View {
        Button("About target ranges") {
            isPresented = true
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(palette.color(.accentBlue))
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented) {
            Text("These comparisons use the targets you saved in Settings. They describe your readings. They do not decide whether the water is safe.")
                .font(.footnote)
                .foregroundStyle(palette.color(.textPrimary))
                .padding(16)
                .frame(maxWidth: 280)
                .presentationCompactAdaptation(.popover)
        }
    }
}

private struct HomeStatusCopy: View {
    let status: HomeStatusPresentation
    let palette: AppPalette
    var linksDueReminder: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(status.headline)
                .font(.title2.weight(.bold))
                .foregroundStyle(palette.color(.onAccent))
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle = status.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(palette.color(.onAccent).opacity(0.8))
            }

            Text(status.comparisonCaption)
                .font(.caption)
                .foregroundStyle(palette.color(.onAccent).opacity(0.7))

            if let dueSecondary = status.dueSecondary {
                if linksDueReminder {
                    NavigationLink {
                        DailyLogFormView()
                    } label: {
                        dueLabel(dueSecondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    dueLabel(dueSecondary)
                }
            }
        }
    }

    private func dueLabel(_ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.caption.weight(.semibold))
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(palette.color(.accentBlue))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white)
        .clipShape(Capsule())
    }
}

private struct HomeReadingColumn: View {
    let reading: HomeReadingPresentation
    var showsGauge: Bool
    var valueFont: Font

    @Environment(\.appPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(reading.name)
                .font(.caption)
                .foregroundStyle(palette.color(.onAccent).opacity(0.75))

            Text(reading.valueText)
                .font(valueFont)
                .foregroundStyle(palette.color(.onAccent))

            if reading.status != .unknown {
                HStack(spacing: 4) {
                    Image(systemName: reading.status.symbolName)
                        .font(.caption)
                    Text(reading.status.shortLabel)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(palette.color(.onAccent))
            }

            Text("Your target \(WaterChemistryRanges.targetLabel(reading.target, unit: reading.unit))")
                .font(.caption2)
                .foregroundStyle(palette.color(.onAccent).opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)

            if showsGauge, reading.status != .unknown {
                ChemistryRangeGauge(
                    value: numericValue,
                    targetRange: reading.target,
                    displayRange: reading.displayRange,
                    status: reading.status.readingStatus
                )
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.accessibilityText)
    }

    private var numericValue: Double? {
        guard reading.status != .unknown else { return nil }
        let digits = reading.valueText.replacingOccurrences(of: " ppm", with: "")
        return Double(digits)
    }
}
