import SwiftUI

// =====================================================
// MARK: - RadarChartView
// [TAG: MOBILE_RADAR]
// =====================================================

struct RadarChartView: View {
    let skills: SkillValues
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = size * 0.36

            ZStack {
                ForEach(1..<5, id: \.self) { step in
                    RadarPolygon(
                        points: normalizedPoints(values: Array(repeating: Double(step) / 4.0, count: 6), center: center, radius: radius)
                    )
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                }

                ForEach(0..<6, id: \.self) { index in
                    let point = axisPoint(index: index, center: center, radius: radius)
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: point)
                    }
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }

                RadarPolygon(points: normalizedPoints(values: normalizedSkillValues(), center: center, radius: radius))
                    .fill(accent.opacity(0.28))

                RadarPolygon(points: normalizedPoints(values: normalizedSkillValues(), center: center, radius: radius))
                    .stroke(accent, lineWidth: 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func normalizedSkillValues() -> [Double] {
        SkillCategory.allCases.map { category in
            Double(skills[category]) / 100.0
        }
    }

    private func normalizedPoints(values: [Double], center: CGPoint, radius: CGFloat) -> [CGPoint] {
        var points: [CGPoint] = []
        points.reserveCapacity(values.count)

        for (idx, value) in values.enumerated() {
            let angle = angleForAxis(index: idx)
            let clamped = max(0.0, min(1.0, value))
            let scaledRadius = CGFloat(clamped) * radius
            let x = center.x + CGFloat(cos(angle)) * scaledRadius
            let y = center.y + CGFloat(sin(angle)) * scaledRadius
            points.append(CGPoint(x: x, y: y))
        }

        return points
    }

    private func axisPoint(index: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = angleForAxis(index: index)
        let x = center.x + CGFloat(cos(angle)) * radius
        let y = center.y + CGFloat(sin(angle)) * radius
        return CGPoint(x: x, y: y)
    }

    private func angleForAxis(index: Int) -> Double {
        let step = (2.0 * Double.pi) / 6.0
        return (-Double.pi / 2.0) + (Double(index) * step)
    }
}

private struct RadarPolygon: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}
