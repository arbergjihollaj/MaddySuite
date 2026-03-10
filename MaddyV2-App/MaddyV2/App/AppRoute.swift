//
//  AppRoute.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import Foundation

// =====================================================
// MARK: - AppRoute
// [TAG: V2_APP_ROUTE]
// =====================================================

enum AppRoute: String, Codable, CaseIterable, Identifiable {
    case home
    case calendar
    case focus
    case tasks
    case habits
    case gamify
    case ai
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .calendar: return "Calendar"
        case .focus: return "Focus"
        case .tasks: return "Tasks"
        case .habits: return "Habits"
        case .gamify: return "Gamify"
        case .ai: return "Coach"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .calendar: return "calendar"
        case .focus: return "timer"
        case .tasks: return "checklist"
        case .habits: return "chart.bar.xaxis"
        case .gamify: return "hexagon.fill"
        case .ai: return "sparkles"
        case .settings: return "gearshape.fill"
        }
    }
}
