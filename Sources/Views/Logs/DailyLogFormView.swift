//
//  DailyLogFormView.swift
//  HotTub
//

import SwiftData
import SwiftUI

struct DailyLogFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.usePadLayout) private var usePadLayout
    @Environment(\.isLandscape) private var isLandscape

    let existing: HotTubDailyLog?

    @State private var loggedAt: Date = .now
    @State private var waterTemp: Int = 37
    @State private var ph: String = ""
    @State private var sanitizerFree: String = ""
    @State private var sanitizerCombined: String = ""
    @State private var addedSanitizer: String = ""
    @State private var addedPhUp: String = ""
    @State private var addedPhDown: String = ""
    @State private var notes: String = ""

    @State private var alertTitle = "Fix before saving"
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var presentedHelp: HelpSheetRequest?
    @Query private var settingsRows: [AppSettings]

    private var isCelsius: Bool {
        settingsRows.first?.temperatureUnit != "fahrenheit"
    }

    private var isBromine: Bool {
        settingsRows.first?.isBromine ?? false
    }

    private var isMetric: Bool {
        settingsRows.first?.measurementSystem != "imperial"
    }

    private var sanitizerName: String {
        isBromine ? "Bromine" : "Chlorine"
    }

    private var freeSanitizerPlaceholder: String {
        let range = settingsRows.first?.sanitizerTarget
            ?? (isBromine ? WaterChemistryRanges.startingBromine : WaterChemistryRanges.startingChlorine)
        return WaterChemistryRanges.placeholder(range)
    }

    private var phPlaceholder: String {
        WaterChemistryRanges.placeholder(settingsRows.first?.phTarget ?? WaterChemistryRanges.startingPH)
    }

    private var combinedPlaceholder: String {
        WaterChemistryRanges.placeholder(
            settingsRows.first?.combinedChlorineTarget ?? WaterChemistryRanges.startingCombinedChlorine
        )
    }

    private var weightUnit: String {
        isMetric ? "g" : "oz"
    }

    init(existing: HotTubDailyLog? = nil) {
        self.existing = existing
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                AppFormScreenSection(title: "When", presentedHelp: $presentedHelp) {
                    AppLogDateTimePicker(selection: $loggedAt)
                }

                AppFormScreenSection(
                    title: "Temperature",
                    helpRequest: HelpSheetRequest(topic: .temperature),
                    presentedHelp: $presentedHelp
                ) {
                    HStack(spacing: 12) {
                        Image(systemName: "thermometer.medium")
                            .font(.body.weight(.medium))
                            .foregroundStyle(palette.color(.accentBlue))
                            .frame(width: 24, alignment: .center)
                        Stepper(
                            "Water \(isCelsius ? "°C" : "°F"): \(waterTemp)",
                            value: $waterTemp,
                            in: isCelsius ? 10 ... 45 : 50 ... 110,
                            step: 1
                        )
                        .font(.body.weight(.medium))
                        .foregroundStyle(palette.color(.textPrimary))
                    }
                    .frame(minHeight: AppSpacing.minTap)
                }

                chemicalsLayout

                AppFormScreenSection(title: "Notes", presentedHelp: $presentedHelp) {
                    AppFormNotesField(text: $notes)
                }
            }
            .appAdaptiveScrollPadding(usePadLayout: usePadLayout)
            .padReadableContent(maxWidth: PadContentLayout.settingsMaxWidth)
        }
        .scrollDismissesKeyboard(.interactively)
        .appGroupedScreenBackground(palette)
        .navigationTitle(existing == nil ? "Water test" : "Edit water test")
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
        .helpSheet(presentedHelp: $presentedHelp, isBromine: isBromine, isMetric: isMetric)
        .onAppear {
            HotTubModelContainer.seedIfNeeded(in: modelContext)
            if let e = existing {
                loggedAt = e.loggedAt
                if let t = e.waterTemperature { waterTemp = t }
                ph = e.ph.map { String(format: "%g", $0) } ?? ""
                sanitizerFree = e.sanitizerFree.map { String(format: "%g", $0) } ?? ""
                sanitizerCombined = e.sanitizerCombined.map { String(format: "%g", $0) } ?? ""
                addedSanitizer = e.addedSanitizer > 0 ? String(format: "%g", e.addedSanitizer) : ""
                addedPhUp = e.addedPhUp > 0 ? String(format: "%g", e.addedPhUp) : ""
                addedPhDown = e.addedPhDown > 0 ? String(format: "%g", e.addedPhDown) : ""
                notes = e.notes ?? ""
            } else {
                waterTemp = isCelsius ? 37 : 98
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var usesSideBySideChemicals: Bool {
        usePadLayout && isLandscape
    }

    @ViewBuilder
    private var chemicalsLayout: some View {
        if usesSideBySideChemicals {
            HStack(alignment: .top, spacing: AppSpacing.control) {
                chemicalReadingsSection
                    .frame(maxWidth: .infinity, alignment: .leading)
                chemicalsAddedSection
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                chemicalReadingsSection
                chemicalsAddedSection
            }
        }
    }

    private var chemicalReadingsSection: some View {
        AppFormScreenSection(title: "Chemical readings", presentedHelp: $presentedHelp) {
            AppLabeledFormField(
                title: "pH",
                helpRequest: .ph(.overview),
                presentedHelp: $presentedHelp,
                systemImage: "flask",
                placeholder: phPlaceholder,
                text: $ph,
                blurValidator: { FormValidation.blurRangeError(for: $0, min: 0, max: 14) }
            )
            AppLabeledFormField(
                title: isBromine ? "Bromine (ppm)" : "Free chlorine (ppm)",
                helpRequest: .sanitizer(.free),
                presentedHelp: $presentedHelp,
                systemImage: "drop.fill",
                placeholder: freeSanitizerPlaceholder,
                text: $sanitizerFree,
                blurValidator: { FormValidation.blurRangeError(for: $0, min: 0, max: 20) }
            )
            if !isBromine {
                AppLabeledFormField(
                    title: "Combined chlorine (ppm)",
                    helpRequest: .sanitizer(.combined),
                    presentedHelp: $presentedHelp,
                    systemImage: "drop.triangle",
                    placeholder: combinedPlaceholder,
                    text: $sanitizerCombined,
                    blurValidator: { FormValidation.blurRangeError(for: $0, min: 0, max: 20) }
                )
            }
        }
    }

    private var chemicalsAddedSection: some View {
        AppFormScreenSection(
            title: "Chemicals added",
            helpRequest: HelpSheetRequest(topic: .chemicalsAdded),
            presentedHelp: $presentedHelp
        ) {
            AppSimpleMetricField(
                title: "\(sanitizerName) added (\(weightUnit))",
                systemImage: "bolt.fill",
                placeholder: "0.0 \(weightUnit)",
                text: $addedSanitizer,
                blurValidator: FormValidation.blurNonNegativeError
            )
            AppLabeledFormField(
                title: "pH Down added (\(weightUnit))",
                helpRequest: .ph(.down),
                presentedHelp: $presentedHelp,
                systemImage: "arrow.down.right",
                placeholder: "0.0 \(weightUnit)",
                text: $addedPhDown,
                blurValidator: FormValidation.blurNonNegativeError
            )
            AppLabeledFormField(
                title: "pH Up added (\(weightUnit))",
                helpRequest: .ph(.up),
                presentedHelp: $presentedHelp,
                systemImage: "arrow.up.right",
                placeholder: "0.0 \(weightUnit)",
                text: $addedPhUp,
                blurValidator: FormValidation.blurNonNegativeError
            )
        }
    }

    private func refreshReminders() {
        guard !PreviewEnvironment.isActive else { return }
        HotTubDataRefresh.notifyLocalStoreChanged()
        Task { await ReminderNotificationService.shared.rescheduleFromSharedContainer() }
    }

    private func finish() {
        let errs = FormValidation.validateDailyLog(
            loggedAt: loggedAt,
            ph: ph,
            sanitizerFree: sanitizerFree,
            sanitizerCombined: sanitizerCombined,
            addedSanitizer: addedSanitizer,
            addedPhUp: addedPhUp,
            addedPhDown: addedPhDown,
            notes: notes,
            isBromine: isBromine
        )
        if !errs.isEmpty {
            alertTitle = "Fix before saving"
            alertMessage = errs.joined(separator: "\n")
            showAlert = true
            return
        }

        guard commitSave() else { return }
        refreshReminders()
        dismiss()
    }

    @discardableResult
    private func commitSave() -> Bool {
        let phVal = FormFieldParsing.validatedOptionalDouble(from: ph, min: 0, max: 14)
        let freeVal = FormFieldParsing.validatedOptionalDouble(from: sanitizerFree, min: 0, max: 20)
        let combVal = FormFieldParsing.validatedOptionalDouble(from: sanitizerCombined, min: 0, max: 20)

        do {
            if let existing {
                apply(to: existing, phVal: phVal, freeVal: freeVal, combVal: combVal)
            } else {
                let log = HotTubDailyLog(
                    loggedAt: loggedAt,
                    waterTemperature: waterTemp,
                    ph: phVal,
                    sanitizerFree: freeVal,
                    sanitizerCombined: combVal,
                    addedPhUp: FormFieldParsing.nonNegativeDouble(from: addedPhUp),
                    addedPhDown: FormFieldParsing.nonNegativeDouble(from: addedPhDown),
                    addedSanitizer: FormFieldParsing.nonNegativeDouble(from: addedSanitizer),
                    notes: notes.isEmpty ? nil : notes
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

    private func apply(to record: HotTubDailyLog, phVal: Double?, freeVal: Double?, combVal: Double?) {
        record.loggedAt = loggedAt
        record.waterTemperature = waterTemp
        if ph.trimmingCharacters(in: .whitespaces).isEmpty || phVal != nil {
            record.ph = phVal
        }
        if sanitizerFree.trimmingCharacters(in: .whitespaces).isEmpty || freeVal != nil {
            record.sanitizerFree = freeVal
        }
        if sanitizerCombined.trimmingCharacters(in: .whitespaces).isEmpty || combVal != nil {
            record.sanitizerCombined = combVal
        }
        record.addedPhUp = FormFieldParsing.nonNegativeDouble(from: addedPhUp)
        record.addedPhDown = FormFieldParsing.nonNegativeDouble(from: addedPhDown)
        record.addedSanitizer = FormFieldParsing.nonNegativeDouble(from: addedSanitizer)
        record.notes = notes.isEmpty ? nil : notes
    }

    private func deleteLog() {
        guard let record = existing else { return }
        modelContext.delete(record)
        try? modelContext.save()
        refreshReminders()
        dismiss()
    }
}
