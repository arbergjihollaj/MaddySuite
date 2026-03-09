//
//  SharedUI.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import SwiftUI

// =====================================================
// MARK: - Global Surface
// [TAG: V2_SHARED_SURFACE]
// =====================================================

struct MaddyBackground: View {
    var accent: Color

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.05, green: 0.07, blue: 0.11),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(accent.opacity(0.16))
                .frame(width: 520, height: 520)
                .blur(radius: 60)
                .offset(x: -220, y: -210)

            RoundedRectangle(cornerRadius: 220)
                .fill(Color.white.opacity(0.06))
                .frame(width: 680, height: 260)
                .rotationEffect(.degrees(-12))
                .blur(radius: 90)
                .offset(x: 220, y: -170)
        }
        .ignoresSafeArea()
    }
}

struct GlassCard<Content: View>: View {
    @EnvironmentObject private var appState: AppState

    let title: String?
    let accent: Color
    @ViewBuilder var content: Content

    init(title: String? = nil, accent: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.02 + appState.glassIntensity * 0.22))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(accent.opacity(0.25 + appState.glassIntensity * 0.5), lineWidth: 0.8)
                }
        }
    }
}

struct StatChip: View {
    let label: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }
}

// =====================================================
// MARK: - Bottom Navigation
// [TAG: V2_BOTTOM_NAV]
// =====================================================

struct BottomNavigationBar: View {
    @EnvironmentObject var appState: AppState
    @Namespace private var indicatorNamespace

    var body: some View {
        HStack(spacing: 10) {
            ForEach(appState.topOrder) { route in
                Button {
                    appState.navigate(to: route)
                } label: {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: route.icon)
                                .font(.system(size: 13, weight: .semibold))
                            Text(route.title)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(appState.route == route ? .white : .white.opacity(0.62))
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                        ZStack {
                            Capsule()
                                .fill(.clear)
                                .frame(height: 3)
                            if appState.route == route {
                                Capsule()
                                    .fill(appState.accentColor)
                                    .frame(height: 3)
                                    .matchedGeometryEffect(id: "routeIndicator", in: indicatorNamespace)
                            }
                        }
                        .padding(.horizontal, 10)
                    }
                    .frame(minWidth: 92)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            if appState.showMenuBarHint {
                Label("New debug logs", systemImage: "terminal")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.yellow.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.32, bounce: 0.25), value: appState.route)
        .animation(.easeInOut(duration: 0.22), value: appState.showMenuBarHint)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                }
        }
    }
}

// =====================================================
// MARK: - Circular Timer
// [TAG: V2_CIRCULAR_TIMER]
// =====================================================

struct CircularTimerRing: View {
    let progress: Double
    let accent: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 14, lineCap: .round))

            Circle()
                .trim(from: 0, to: progress.clamped(to: 0...1))
                .stroke(
                    AngularGradient(colors: [accent, accent.opacity(0.3), accent], center: .center),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.35), value: progress)
        }
    }
}
