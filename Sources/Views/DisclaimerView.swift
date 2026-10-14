//
//  DisclaimerView.swift
//  HotTub
//

import SwiftUI

struct DisclaimerView: View {
    var onAccept: () -> Void

    @Environment(\.appPalette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            DisclaimerScrollContent()
            acceptFooter
        }
        .background(palette.color(.backgroundPrimary).ignoresSafeArea())
    }

    private var acceptFooter: some View {
        VStack(spacing: 10) {
            Divider()
            Button(action: onAccept) {
                Text("I Accept & Understand")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.color(.onAccent))
            .background(palette.color(.accentRed))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text("By accepting, you acknowledge you have read and understood this disclaimer")
                .font(.caption)
                .foregroundStyle(palette.color(.textSecondary))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(palette.color(.backgroundPrimary))
    }
}

struct DisclaimerSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appPalette) private var palette

    var body: some View {
        NavigationStack {
            DisclaimerScrollContent()
                .background(palette.color(.backgroundPrimary))
                .navigationTitle("Disclaimer")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

struct DisclaimerScrollContent: View {
    @Environment(\.appPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                    .padding(.vertical, 20)
                sections
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark")
                .font(.title2.bold())
                .foregroundStyle(palette.color(.onAccent))
                .frame(width: 52, height: 52)
                .background(palette.color(.accentRed))
                .clipShape(Circle())

            Text("Important Disclaimer")
                .font(.title.bold())
                .foregroundStyle(palette.color(.textPrimary))
                .multilineTextAlignment(.center)

            Text("Version \(DisclaimerAcceptance.currentVersion) • Please read carefully before using this app")
                .font(.subheadline)
                .foregroundStyle(palette.color(.textSecondary))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 24) {
            DisclaimerSection(title: "Overview") {
                Text(
                    "This app is for data-logging purposes only. It does not provide medical, safety, or chemical advice. The user is solely responsible for verifying chemical levels and ensuring the safety of their water."
                )
                Text(
                    "This app does not provide professional advice and does not replace manufacturer instructions or professional services."
                )
            }

            DisclaimerSection(title: "Water Chemistry") {
                Text(
                    "This app is a logging and tracking tool for recording your hot tub maintenance. Any water chemistry values, ranges, or guidance shown are for reference only. The app does not calculate or recommend chemical dosages. Always follow your hot tub or spa manufacturer's guidance and the instructions on chemical products. Users are responsible for testing their own water and making their own decisions about chemical treatment."
                )
            }

            DisclaimerSection(title: "Safety") {
                Text(
                    "Pool and spa chemicals can be hazardous if handled incorrectly. Always read and follow product labels, safety warnings, and safety data sheets. This app is intended for use by adults only (18+)."
                )
            }

            DisclaimerSection(title: "Your Data") {
                Text(
                    "This app does not require an account with Curley Brackets Engineering, and we do not collect, receive, or access what you enter. Readings, treatments, usage, reminders, and target ranges are stored on this device and, when iCloud is available, synced through your personal iCloud account so they can appear on your other Apple devices. That sync is handled by Apple."
                )
            }

            DisclaimerSection(title: "Local Laws") {
                Text(
                    "Laws, standards, and recommended practices may vary by country or region. Users are responsible for ensuring compliance with local regulations and manufacturer guidance."
                )
            }

            DisclaimerSection(title: "No Warranty") {
                Text(
                    "This app is provided \"as is\" and \"as available\", without warranties of any kind, either express or implied, including but not limited to warranties of merchantability, fitness for a particular purpose, or non-infringement."
                )
            }

            DisclaimerSection(title: "Limitation of Liability") {
                Text(
                    "To the fullest extent permitted by applicable law, Curley Brackets Engineering Ltd accepts no liability for any loss, damage, or injury (including but not limited to direct, indirect, incidental, consequential, special, or punitive damages) arising from use of or inability to use this app."
                )
                Text("Nothing in this disclaimer excludes or limits our liability for:")
                DisclaimerBulletList(items: [
                    "Death or personal injury caused by our negligence",
                    "Fraud or fraudulent misrepresentation",
                    "Any other liability that cannot be excluded or limited under UK law",
                ])
                Text("Use of this app is entirely at the user's own risk.")
            }

            DisclaimerSection(title: "User Responsibilities") {
                Text("By using this app, you agree to:")
                DisclaimerBulletList(items: [
                    "Test your water before adding any chemicals",
                    "Follow all applicable safety regulations and manufacturer instructions",
                    "Indemnify and hold harmless Curley Brackets Engineering Ltd from any claims arising from your use of this app",
                ])
            }

            DisclaimerSection(title: "Governing Law") {
                Text(
                    "This disclaimer is governed by the laws of England and Wales. Any disputes shall be subject to the exclusive jurisdiction of the courts of England and Wales."
                )
            }

            DisclaimerSection(title: "Modifications") {
                Text(
                    "We reserve the right to modify or discontinue this app at any time without notice."
                )
            }

            DisclaimerSection(title: "Severability") {
                Text(
                    "If any provision of this disclaimer is found to be invalid or unenforceable, the remaining provisions shall continue in full force and effect."
                )
            }
        }
    }
}

struct DisclaimerSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    @Environment(\.appPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(palette.color(.textPrimary))

            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .font(.subheadline)
            .foregroundStyle(palette.color(.textPrimary))
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct DisclaimerBulletList: View {
    let items: [String]

    @Environment(\.appPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(palette.color(.textSecondary))
                    Text(item)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

#Preview {
    DisclaimerView(onAccept: {})
        .appPalette(.light)
}
