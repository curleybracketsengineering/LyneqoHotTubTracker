//
//  UsageLogFormView.swift
//  HotTub
//

import SwiftData
import SwiftUI

struct UsageLogFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.usePadLayout) private var usePadLayout

    let existing: UsageLogEntry?

    @State private var loggedAt: Date = .now
    @State private var numUsers = 1
    @State private var durationMinutes = 15
    @State private var waterTemp = 37

    @State private var alertTitle = "Fix before saving"
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var presentedHelp: HelpSheetRequest?
    @Query private var settingsRows: [AppSettings]

    private var isCelsius: Bool {
        settingsRows.first?.temperatureUnit != "fahrenheit"
    }

    init(existing: UsageLogEntry? = nil) {
        self.existing = existing
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                AppFormScreenSection(title: "When", presentedHelp: $presentedHelp) {
                    AppLogDateTimePicker(selection: $loggedAt)
                }

                AppFormScreenSection(title: "Session", presentedHelp: $presentedHelp) {
                    Stepper("People: \(numUsers)", value: $numUsers, in: 1 ... 20)
                        .font(.body.weight(.medium))
                        .foregroundStyle(palette.color(.textPrimary))
                        .frame(minHeight: AppSpacing.minTap)
                    Stepper("Duration: \(durationMinutes) min", value: $durationMinutes, in: 5 ... 480, step: 5)
                        .font(.body.weight(.medium))
                        .foregroundStyle(palette.color(.textPrimary))
                        .frame(minHeight: AppSpacing.minTap)
                    Stepper(
                        "Water \(isCelsius ? "°C" : "°F"): \(waterTemp)",
                        value: $waterTemp,
                        in: isCelsius ? 10 ... 45 : 50 ... 110,
                        step: 1
                    )
                    .font(.body.weight(.medium))
                    .foregroundStyle(palette.color(.textPrimary))
                    .frame(minHeight: AppSpacing.minTap)
                }
            }
            .appAdaptiveScrollPadding(usePadLayout: usePadLayout)
            .padReadableContent(maxWidth: PadContentLayout.settingsMaxWidth)
        }
        .scrollDismissesKeyboard(.interactively)
        .appGroupedScreenBackground(palette)
        .navigationTitle(existing == nil ? "Usage log" : "Edit usage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { finish() }
            }
            if existing != nil {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", role: .destructive) { deleteLog() }
                }
            }
        }
        .onAppear {
            HotTubModelContainer.seedIfNeeded(in: modelContext)
            let defaultWaterTemp = isCelsius ? 37 : 98
            if let e = existing {
                loggedAt = e.loggedAt
                numUsers = e.numUsers
                durationMinutes = e.durationMinutes
                waterTemp = e.waterTemperature ?? defaultWaterTemp
            } else {
                waterTemp = defaultWaterTemp
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func finish() {
        let errs = FormValidation.validateUsage(loggedAt: loggedAt)
        if !errs.isEmpty {
            alertTitle = "Fix before saving"
            alertMessage = errs.joined(separator: "\n")
            showAlert = true
            return
        }

        guard commitSave() else { return }
        notifyStoreChanged()
        dismiss()
    }

    private func notifyStoreChanged() {
        guard !PreviewEnvironment.isActive else { return }
        HotTubDataRefresh.notifyLocalStoreChanged()
    }

    @discardableResult
    private func commitSave() -> Bool {
        do {
            if let existing {
                existing.loggedAt = loggedAt
                existing.numUsers = numUsers
                existing.durationMinutes = durationMinutes
                existing.waterTemperature = waterTemp
            } else {
                let log = UsageLogEntry(
                    loggedAt: loggedAt,
                    numUsers: numUsers,
                    durationMinutes: durationMinutes,
                    waterTemperature: waterTemp
                )
                modelContext.insert(log)
            }
            try modelContext.save()
            return true
        } catch {
            alertTitle = "Couldn't save"
            alertMessage = "Please try again."
            showAlert = true
            return false
        }
    }

    private func deleteLog() {
        guard let record = existing else { return }
        modelContext.delete(record)
        try? modelContext.save()
        notifyStoreChanged()
        dismiss()
    }
}
