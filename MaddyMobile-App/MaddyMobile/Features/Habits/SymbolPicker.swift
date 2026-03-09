import SwiftUI

/// File: Features/Habits/SymbolPicker.swift

// =====================================================
// MARK: - SymbolPicker
// [TAG: MOBILE_SYMBOL_PICKER]
// =====================================================

struct SymbolPicker: View {
    @Binding var selectedSymbol: String

    static let symbols: [String] = [
        "checkmark.circle.fill", "flame.fill", "book.fill", "figure.walk", "drop.fill",
        "brain.head.profile", "leaf.fill", "heart.fill", "moon.fill", "sun.max.fill",
        "dumbbell.fill", "fork.knife", "pills.fill", "waterbottle.fill", "figure.run",
        "figure.cooldown", "figure.mind.and.body", "figure.yoga", "medal.fill", "target",
        "timer", "alarm.fill", "calendar", "sparkles", "bolt.fill",
        "graduationcap.fill", "music.note", "paintbrush.fill", "camera.fill", "gamecontroller.fill",
        "doc.text.fill", "square.and.pencil", "tray.full.fill", "tray.and.arrow.down.fill", "flag.fill",
        "star.fill", "gift.fill", "tree.fill", "airplane", "cup.and.saucer.fill"
    ]

    var body: some View {
        Menu {
            ForEach(Self.symbols, id: \.self) { symbol in
                Button {
                    selectedSymbol = symbol
                } label: {
                    Label(symbol, systemImage: symbol)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selectedSymbol)
                Text(selectedSymbol)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
        }
    }
}
