//
//  ActivityLogKind.swift
//  HotTub
//

import SwiftUI

/// Shared icons and accent tokens for log entry types (Activity hub, History, Dashboard).
enum ActivityLogKind: String, CaseIterable, Identifiable {
    case daily
    case weekly
    case maintenance
    case usage

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .daily: "drop.fill"
        case .weekly: "calendar.badge.checkmark"
        case .maintenance: "wrench.fill"
        case .usage: "timer"
        }
    }

    var fillToken: PaletteToken {
        switch self {
        case .daily: .tagBlueFill
        case .weekly: .tagGreenFill
        case .maintenance: .tagOrangeFill
        case .usage: .tagPinkFill
        }
    }

    var iconToken: PaletteToken {
        switch self {
        case .daily: .accentBlue
        case .weekly: .accentGreen
        case .maintenance: .accentOrange
        case .usage: .accentPink
        }
    }

    var padActionTitle: String {
        switch self {
        case .daily: "Record water test"
        case .weekly: "Full water check"
        case .maintenance: "Service"
        case .usage: "Log hot-tub usage"
        }
    }

    var padActionSubtitle: String {
        switch self {
        case .daily: "Log today's readings"
        case .weekly: "Record all water readings"
        case .maintenance: "Log cleaning or repairs"
        case .usage: "Record people and duration"
        }
    }

    var tileSystemImage: String {
        switch self {
        case .daily: "drop.fill"
        case .weekly: "flask.fill"
        case .maintenance: "wrench.fill"
        case .usage: "person.2.fill"
        }
    }

    @ViewBuilder
    var formDestination: some View {
        switch self {
        case .daily:
            DailyLogFormView()
        case .weekly:
            WeeklyLogFormView()
        case .maintenance:
            MaintenanceLogFormView()
        case .usage:
            UsageLogFormView()
        }
    }
}

extension HistoryRow {
    var kind: ActivityLogKind {
        switch self {
        case .daily: .daily
        case .weekly: .weekly
        case .maintenance: .maintenance
        case .usage: .usage
        }
    }
}
