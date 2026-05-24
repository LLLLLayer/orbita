import AppKit
import SwiftUI

enum OrbitaTheme {
    static let cardRadius: CGFloat = 20
    static let compactCardRadius: CGFloat = 14
    static let controlRadius: CGFloat = 12

    static let canvas = gray(light: 0.91, dark: 0.075)
    static let sidebarBackground = gray(light: 0.93, dark: 0.095)
    static let surface = gray(light: 0.965, dark: 0.135)
    static let elevatedSurface = gray(light: 0.99, dark: 0.17)
    static let controlFill = gray(light: 0.925, dark: 0.205)
    static let controlHoverFill = gray(light: 0.895, dark: 0.255)
    static let prominentControlFill = color(
        light: NSColor(calibratedWhite: 0.08, alpha: 1),
        dark: NSColor(calibratedWhite: 0.92, alpha: 1)
    )
    static let prominentControlForeground = color(
        light: NSColor(calibratedWhite: 1, alpha: 1),
        dark: NSColor(calibratedWhite: 0.05, alpha: 1)
    )
    static let border = color(
        light: NSColor(calibratedWhite: 0, alpha: 0.08),
        dark: NSColor(calibratedWhite: 1, alpha: 0.10)
    )
    static let strongBorder = color(
        light: NSColor(calibratedWhite: 0, alpha: 0.18),
        dark: NSColor(calibratedWhite: 1, alpha: 0.22)
    )
    static let cardShadow = color(
        light: NSColor(calibratedWhite: 0, alpha: 0.055),
        dark: NSColor(calibratedWhite: 0, alpha: 0.32)
    )
    static let selectedShadow = color(
        light: NSColor(calibratedWhite: 0, alpha: 0.09),
        dark: NSColor(calibratedWhite: 0, alpha: 0.40)
    )

    private static func gray(light: CGFloat, dark: CGFloat, alpha: CGFloat = 1) -> Color {
        color(
            light: NSColor(calibratedWhite: light, alpha: alpha),
            dark: NSColor(calibratedWhite: dark, alpha: alpha)
        )
    }

    private static func color(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? dark : light
        })
    }
}

extension View {
    func orbitaCard(
        cornerRadius: CGFloat = OrbitaTheme.cardRadius,
        shadowRadius: CGFloat = 14,
        shadowY: CGFloat = 8
    ) -> some View {
        modifier(OrbitaCardModifier(cornerRadius: cornerRadius, shadowRadius: shadowRadius, shadowY: shadowY))
    }

    func orbitaControlSurface(
        selected: Bool = false,
        cornerRadius: CGFloat = OrbitaTheme.controlRadius
    ) -> some View {
        modifier(OrbitaControlSurfaceModifier(selected: selected, cornerRadius: cornerRadius))
    }
}

private struct OrbitaCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let shadowRadius: CGFloat
    let shadowY: CGFloat

    func body(content: Content) -> some View {
        content
            .background(OrbitaTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(OrbitaTheme.border)
            }
            .shadow(color: OrbitaTheme.cardShadow, radius: shadowRadius, x: 0, y: shadowY)
    }
}

private struct OrbitaControlSurfaceModifier: ViewModifier {
    let selected: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                selected ? OrbitaTheme.prominentControlFill : OrbitaTheme.controlFill,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(selected ? Color.clear : OrbitaTheme.border)
            }
    }
}
