//
//  WeeklyLogFormView.swift
//  HotTub
//

import SwiftData
import SwiftUI

private let chlorineShockOptions: [(String, String)] = [
    ("Cal-Hypo", "cal-hypo"),
    ("Dichlor", "dichlor"),
    ("Lithium hypochlorite", "lithium-hypo"),
    ("Non-chlorine (MPS)", "mps"),
]

private let bromineShockOptions: [(String, String)] = [
    ("Non-chlorine (MPS)", "mps"),
    ("Bromine granules", "bromine-granules"),
]

struct WeeklyLogFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.usePadLayout) private var usePadLayout

    let existing: WeeklyCheckLog?

    @State private var loggedAt: Date = .now
    @State private var combined = ""
    @State private var total = ""
    @State private var alkalinity = ""
    @State private var copper = ""
    @State private var shock = ""
    @State private var shockType = ""
    @State private var alkUp = ""
    @State private var waterClarity = ""
    @State private var foamPresent = false
    @State private var notes = ""

    @State private var alertTitle = "Fix before saving"
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var presentedHelp: HelpSheetRequest?
    @Query private var settingsRows: [AppSettings]

    init(existing: WeeklyCheckLog? = nil) {
        self.existing = existing
    }

    private var shockOptions: [(String, String)] {
        isBromine ? bromineShockOptions : chlorineShockOptions
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

    private var totalSanitizerPlaceholder: String {
        let range = settingsRows.first?.sanitizerTarget
            ?? (isBromine ? WaterChemistryRanges.startingBromine : WaterChemistryRanges.startingChlorine)
        return WaterChemistryRanges.placeholder(range)
    }

    private var combinedPlaceholder: String {
        if isBromine { return "0.0-0.5" }
        return WaterChemistryRanges.placeholder(
            settingsRows.first?.combinedChlorineTarget ?? WaterChemistryRanges.startingCombinedChlorine
        )
    }

    private var weightUnit: String {
        isMetric ? "g" : "oz"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                AppFormScreenSection(title: "When", presentedHelp: $presentedHelp) {
                    AppLogDateTimePicker(selection: $loggedAt)
                }

                AppFormScreenSection(title: "Water chemistry", presentedHelp: $presentedHelp) {
                    AppLabeledFormField(
                        title: "Combined \(sanitizerName.lowercased()) (ppm)",
                        helpRequest: .sanitizer(.combined),
                        presentedHelp: $presentedHelp,
                        systemImage: "drop.triangle",
                        placeholder: combinedPlaceholder,
                        text: $combined,
                        blurValidator: { FormValidation.blurRangeError(for: $0, min: 0, max: 50) }
                    )
                    AppLabeledFormField(
                        title: "Total \(sanitizerName.lowercased()) (ppm)",
                        helpRequest: .sanitizer(.total),
                        presentedHelp: $presentedHelp,
                        systemImage: "drop.fill",
                        placeholder: totalSanitizerPlaceholder,
                        text: $total,
                        blurValidator: { FormValidation.blurRangeError(for: $0, min: 0, max: 50) }
                    )
                    AppLabeledFormField(
                        title: "Total alkalinity (ppm)",
                        helpRequest: HelpSheetRequest(topic: .alkalinity),
                        presentedHelp: $presentedHelp,
                        systemImage: "aqi.medium",
                        placeholder: "80-120",
                        text: $alkalinity,
                        blurValidator: { FormValidation.blurRangeError(for: $0, min: 0, max: 300) }
                    )
                    AppLabeledFormField(
                        title: "Copper (ppm)",
                        helpRequest: HelpSheetRequest(topic: .copper),
                        presentedHelp: $presentedHelp,
                        systemImage: "circle.hexagongrid",
                        placeholder: "0.0-0.3",
                        text: $copper,
                        blurValidator: { FormValidation.blurRangeError(for: $0, min: 0, max: 5) }
                    )
                }

                AppFormScreenSection(title: "Appearance", presentedHelp: $presentedHelp) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Water clarity")
                            .font(.subheadline)
                            .foregroundStyle(palette.color(.textSecondary))
                        AppFormCardTextField(
                            placeholder: "Clear, cloudy, etc.",
                            text: $waterClarity
                        )
                    }
                    Toggle("Foam present", isOn: $foamPresent)
                        .font(.body)
                        .tint(palette.color(.accentBlue))
                        .padding(.top, 4)
                }

                AppFormScreenSection(
                    title: "Shock & adjustments",
                    helpRequest: HelpSheetRequest(topic: .shock),
                    presentedHelp: $presentedHelp
                ) {
                    AppSimpleMetricField(
                        title: "Shock added (\(weightUnit))",
                        systemImage: "bolt.fill",
                        placeholder: "0.0 \(weightUnit)",
                        text: $shock,
                        blurValidator: FormValidation.blurNonNegativeError
                    )
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Shock type")
                            .font(.subheadline)
                            .foregroundStyle(palette.color(.textSecondary))
                        Picker("Shock type", selection: $shockType) {
                            Text("—").tag("")
                            ForEach(shockOptions, id: \.1) { label, value in
                                Text(label).tag(value)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .font(.body.weight(.medium))
                        .foregroundStyle(palette.color(.textPrimary))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 50)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(palette.color(.backgroundSecondary))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(palette.color(.separator).opacity(0.5), lineWidth: 1)
                        }
                    }
                    AppLabeledFormField(
                        title: "Alkalinity Up added (\(weightUnit))",
                        helpRequest: HelpSheetRequest(topic: .alkalinity),
                        presentedHelp: $presentedHelp,
                        systemImage: "arrow.up.circle",
                        placeholder: "0.0 \(weightUnit)",
                        text: $alkUp,
                        blurValidator: FormValidation.blurNonNegativeError
                    )
                }

                AppFormScreenSection(title: "Notes", presentedHelp: $presentedHelp) {
                    AppFormNotesField(text: $notes)
                }
            }
            .appAdaptiveScrollPadding(usePadLayout: usePadLayout)
            .padReadableContent(maxWidth: PadContentLayout.settingsMaxWidth)
        }
        .scrollDismissesKeyboard(.interactively)
        .appGroupedScreenBackground(palette)
        .navigationTitle(existing == nil ? "Full water check" : "Edit full water check")
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
                combined = e.combinedChlorine.map { String(format: "%g", $0) } ?? ""
                total = e.sanitizerTotal.map { String(format: "%g", $0) } ?? ""
                alkalinity = e.totalAlkalinity.map { String(format: "%g", $0) } ?? ""
                copper = e.copper.map { String(format: "%g", $0) } ?? ""
                shock = (e.shockAdded ?? 0) > 0 ? String(format: "%g", e.shockAdded!) : ""
                shockType = e.shockType
                alkUp = (e.alkalinityUpAdded ?? 0) > 0 ? String(format: "%g", e.alkalinityUpAdded!) : ""
                waterClarity = e.waterClarity
                foamPresent = e.foamPresent
                notes = e.notes ?? ""
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func refreshReminders() {
        guard !PreviewEnvironment.isActive else { return }
        HotTubDataRefresh.notifyLocalStoreChanged()
        Task { await ReminderNotificationService.shared.rescheduleFromSharedContainer() }
    }

    private func finish() {
        let errs = FormValidation.validateWeekly(
            loggedAt: loggedAt,
            combined: combined,
            total: total,
            alkalinity: alkalinity,
            copper: copper,
            shock: shock,
            alkUp: alkUp,
            notes: notes,
            waterClarity: waterClarity,
            foamPresent: foamPresent,
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
        let shockVal = FormFieldParsing.nonNegativeDouble(from: shock)
        let combinedVal = FormFieldParsing.validatedOptionalDouble(from: combined, min: 0, max: 50)
        let totalVal = FormFieldParsing.validatedOptionalDouble(from: total, min: 0, max: 50)
        let alkalinityVal = FormFieldParsing.validatedOptionalDouble(from: alkalinity, min: 0, max: 300)
        let copperVal = FormFieldParsing.validatedOptionalDouble(from: copper, min: 0, max: 5)

        do {
            if let existing {
                apply(
                    to: existing,
                    shockVal: shockVal,
                    combinedVal: combinedVal,
                    totalVal: totalVal,
                    alkalinityVal: alkalinityVal,
                    copperVal: copperVal
                )
            } else {
                let log = WeeklyCheckLog(
                    loggedAt: loggedAt,
                    combinedChlorine: combinedVal,
                    sanitizerTotal: totalVal,
                    totalAlkalinity: alkalinityVal,
                    copper: copperVal,
                    shockAdded: shockVal,
                    shockType: shockType,
                    alkalinityUpAdded: FormFieldParsing.nonNegativeDouble(from: alkUp),
                    notes: notes.isEmpty ? nil : notes,
                    waterClarity: waterClarity.trimmingCharacters(in: .whitespaces),
                    foamPresent: foamPresent
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

    private func apply(
        to record: WeeklyCheckLog,
        shockVal: Double,
        combinedVal: Double?,
        totalVal: Double?,
        alkalinityVal: Double?,
        copperVal: Double?
    ) {
        record.loggedAt = loggedAt
        if combined.trimmingCharacters(in: .whitespaces).isEmpty || combinedVal != nil {
            record.combinedChlorine = combinedVal
        }
        if total.trimmingCharacters(in: .whitespaces).isEmpty || totalVal != nil {
            record.sanitizerTotal = totalVal
        }
        if alkalinity.trimmingCharacters(in: .whitespaces).isEmpty || alkalinityVal != nil {
            record.totalAlkalinity = alkalinityVal
        }
        if copper.trimmingCharacters(in: .whitespaces).isEmpty || copperVal != nil {
            record.copper = copperVal
        }
        record.shockAdded = shockVal
        record.shockType = shockType
        record.alkalinityUpAdded = FormFieldParsing.nonNegativeDouble(from: alkUp)
        record.waterClarity = waterClarity.trimmingCharacters(in: .whitespaces)
        record.foamPresent = foamPresent
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
