//
//  MusicView.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import SwiftUI

// =====================================================
// MARK: - MusicView
// [TAG: V2_MUSIC_VIEW]
// =====================================================

struct MusicView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var musicService: MusicService
    @EnvironmentObject var serialService: SerialService

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                playerCard
            }
            .padding(.bottom, 10)
        }
        .onAppear {
            serialService.sendView(screen: "music")
        }
    }

    private var playerCard: some View {
        GlassCard(title: "Apple Music (polling every \(Int(appState.settings.musicPollingSeconds))s)", accent: appState.accentColor) {
            VStack(spacing: 14) {
                coverArt
                    .frame(maxWidth: .infinity, alignment: .center)

                VStack(spacing: 4) {
                    Text(musicService.snapshot.title.isEmpty ? "No track" : musicService.snapshot.title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520, alignment: .center)

                    Text(musicService.snapshot.artist)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 520, alignment: .center)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .center, spacing: 6) {
                    Text("State: \(musicService.snapshot.state.rawValue.capitalized)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)

                    ProgressView(value: musicService.snapshot.progress)
                        .tint(appState.accentColor)
                        .frame(maxWidth: 520)

                    Text("\(timeString(musicService.snapshot.positionSeconds)) / \(timeString(musicService.snapshot.durationSeconds))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                HStack(spacing: 18) {
                    transportButton(symbol: "backward.fill", isPrimary: false) {
                        musicService.previousTrack()
                    }
                    transportButton(symbol: musicService.snapshot.state == .playing ? "pause.fill" : "play.fill", isPrimary: true) {
                        musicService.togglePlayPause()
                    }
                    transportButton(symbol: "forward.fill", isPrimary: false) {
                        musicService.nextTrack()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: 10) {
                    Text("Volume")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)

                    Slider(value: Binding(
                        get: { musicService.snapshot.volume },
                        set: { musicService.setVolume($0) }
                    ), in: 0...1)
                    .tint(appState.accentColor)

                    Text("\(Int(musicService.snapshot.volume * 100))%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()

                    Button {
                        serialService.sendView(screen: "music")
                    } label: {
                        Image(systemName: "display")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: 520)

                if let permission = musicService.permissionMessage, permission.isEmpty == false {
                    Text(permission)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if let error = musicService.lastError, error.isEmpty == false {
                    Text(error)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var coverArt: some View {
        ZStack {
            if let image = musicService.coverArt {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                appState.accentColor.opacity(0.45),
                                Color.white.opacity(0.06),
                                Color.black.opacity(0.22)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "music.note")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(.white.opacity(0.9))
                            Text("No Artwork")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                }
            }
        }
        .frame(width: 220, height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func transportButton(symbol: String, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: isPrimary ? 22 : 18, weight: .semibold))
                .frame(width: isPrimary ? 64 : 54, height: isPrimary ? 64 : 54)
                .foregroundStyle(.white)
                .background(
                    Circle()
                        .fill(isPrimary ? appState.accentColor : Color.white.opacity(0.12))
                )
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(isPrimary ? 0.05 : 0.22), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(isPrimary ? 0.3 : 0.2), radius: isPrimary ? 10 : 6, y: 4)
    }

    private func timeString(_ seconds: Double) -> String {
        let clamped = max(0, Int(seconds))
        let mins = clamped / 60
        let secs = clamped % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
