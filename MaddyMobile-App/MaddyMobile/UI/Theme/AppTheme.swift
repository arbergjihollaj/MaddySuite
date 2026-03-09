import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// =====================================================
// MARK: - AppTheme
// [TAG: MOBILE_THEME]
// =====================================================

enum AppTheme {
    static let background = Color(red: 0.06, green: 0.07, blue: 0.09)
    static let surface = Color.white.opacity(0.06)
    static let surfaceElevated = Color.white.opacity(0.1)
    static let border = Color.white.opacity(0.14)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.7)
}

extension Color {
    init?(hex: String) {
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            return nil
        }

        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0

        self.init(red: r, green: g, blue: b)
    }

    var hexString: String {
#if canImport(UIKit)
        let uiColor = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
#else
        return "#FFFFFF"
#endif
    }
}
