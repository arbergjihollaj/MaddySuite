import SwiftUI

// =====================================================
// MARK: - RingTimerView
// [TAG: MOBILE_RING_TIMER]
// =====================================================

struct RingTimerView: View {
    let progress: Double
    let text: String
    let accent: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 14)

            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(
                    AngularGradient(colors: [accent.opacity(0.6), accent], center: .center),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.25), value: progress)

            Text(text)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .frame(width: 240, height: 240)
    }
}
