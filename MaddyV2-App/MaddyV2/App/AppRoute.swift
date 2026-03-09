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
    case focus
    case tasks
    case habits
    case gamify
    case ai
    case music
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .focus: return "Focus"
        case .tasks: return "Tasks"
        case .habits: return "Habits"
        case .gamify: return "Gamify"
        case .ai: return "Coach"
        case .music: return "Music"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .focus: return "timer"
        case .tasks: return "checklist"
        case .habits: return "chart.bar.xaxis"
        case .gamify: return "hexagon.fill"
        case .ai: return "sparkles"
        case .music: return "music.note"
        case .settings: return "gearshape.fill"
        }
    }
}
