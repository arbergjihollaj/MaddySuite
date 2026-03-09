//
//  RadarHexChart.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import SwiftUI

// =====================================================
// MARK: - Radar Hex Chart
// [TAG: V2_RADAR_HEX_CHART]
// =====================================================

struct RadarHexChart: View {
    struct AxisValue: Identifiable, Equatable {
        let id: String
        let label: String
        let value: Double
        let color: Color
    }

    let axes: [AxisValue]
    var rings: Int = 5

    @State private var animatedValues: [Double] = []

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let side = min(size.width, size.height)
            let radius = side * 0.33
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            ZStack {
                Canvas { context, canvasSize in
                    guard axes.isEmpty == false else { return }

                    let baseColor = Color.white.opacity(0.10)

                    for ring in 1...max(1, rings) {
                        let ringScale = Double(ring) / Double(max(1, rings))
                        let ringPath = polygonPath(
                            values: Array(repeating: ringScale, count: axes.count),
                            center: center,
                            radius: radius
                        )
                        context.stroke(ringPath, with: .color(baseColor), lineWidth: 1)
                    }

                    for index in axes.indices {
                        var axisPath = Path()
                        axisPath.move(to: center)
                        axisPath.addLine(to: point(for: index, scale: 1.0, center: center, radius: radius, count: axes.count))
                        context.stroke(axisPath, with: .color(Color.white.opacity(0.14)), lineWidth: 1)
                    }

                    let safeValues = sanitizedValues(count: axes.count)
                    let areaPath = polygonPath(values: safeValues, center: center, radius: radius)
                    let gradient = Gradient(colors: axes.map(\.color) + [axes.first?.color ?? .white])

                    context.fill(
                        areaPath,
                        with: .linearGradient(
                            gradient,
                            startPoint: CGPoint(x: canvasSize.width * 0.2, y: canvasSize.height * 0.15),
                            endPoint: CGPoint(x: canvasSize.width * 0.8, y: canvasSize.height * 0.85)
                        )
                    )

                    context.stroke(areaPath, with: .color(Color.white.opacity(0.6)), lineWidth: 1.4)

                    for index in axes.indices {
                        let value = safeValues[index]
                        let dotPoint = point(for: index, scale: value, center: center, radius: radius, count: axes.count)
                        let dotRect = CGRect(x: dotPoint.x - 3.5, y: dotPoint.y - 3.5, width: 7, height: 7)
                        context.fill(Path(ellipseIn: dotRect), with: .color(axes[index].color))
                    }
                }

                ForEach(Array(axes.enumerated()), id: \.element.id) { index, axis in
                    let labelPoint = point(for: index, scale: 1.14, center: center, radius: radius, count: axes.count)

                    VStack(spacing: 2) {
                        Text(axis.label)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.86))
                        Text("L\(Int(max(1, min(20, round((axis.value * 20.0))))))")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .position(x: labelPoint.x, y: labelPoint.y)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                animateValues(to: axes.map(\.value))
            }
            .onChange(of: axes.map(\.value)) { _, newValues in
                animateValues(to: newValues)
            }
        }
    }

    private func animateValues(to values: [Double]) {
        if animatedValues.count != values.count {
            animatedValues = Array(repeating: 0, count: values.count)
        }

        withAnimation(.easeInOut(duration: 0.22)) {
            animatedValues = values.map { min(1.0, max(0.0, $0)) }
        }
    }

    private func sanitizedValues(count: Int) -> [Double] {
        guard count > 0 else { return [] }

        if animatedValues.count == count {
            return animatedValues.map { min(1.0, max(0.0, $0)) }
        }

        return axes.prefix(count).map { min(1.0, max(0.0, $0.value)) }
    }

    private func polygonPath(values: [Double], center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        guard values.isEmpty == false else { return path }

        for index in values.indices {
            let point = point(for: index, scale: values[index], center: center, radius: radius, count: values.count)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        path.closeSubpath()
        return path
    }

    private func point(for index: Int, scale: Double, center: CGPoint, radius: CGFloat, count: Int) -> CGPoint {
        let safeCount = max(1, count)
        let angleStep = (Double.pi * 2.0) / Double(safeCount)
        let angle = -Double.pi / 2.0 + (Double(index) * angleStep)

        let x = center.x + CGFloat(cos(angle) * Double(radius) * scale)
        let y = center.y + CGFloat(sin(angle) * Double(radius) * scale)
        return CGPoint(x: x, y: y)
    }
}
