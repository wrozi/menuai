//
//  Theme.swift
//  menuai
//
//  Design tokens, matched to Cal AI's shipped screens rather than to a
//  recollection of them.
//
//  What the reference actually shows: a neutral near-white ground, pure white
//  cards with a large radius and almost no shadow, SF Pro at heavy weights
//  (not the rounded variant), rings on a flat light-grey track, one black
//  CTA, and a small fixed palette used only for meaning — coral, tan, blue,
//  green. Colour never decorates.
//

import SwiftUI

enum Theme {
    // MARK: - Colour

    /// Page ground. Neutral, a hair off white so cards still read as lifted.
    static let bg = adaptive(light: 0xF6F6F8, dark: 0x1C1B20)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x26252B)
    /// Icon wells, inputs and the quiet capsules.
    static let surfaceSunken = adaptive(light: 0xF2F2F4, dark: 0x302F36)

    static let ink = adaptive(light: 0x000000, dark: 0xFFFFFF)
    static let inkSecondary = adaptive(light: 0x6E6E73, dark: 0xA5A5AA)
    static let inkTertiary = adaptive(light: 0xA0A0A5, dark: 0x8A8A90)

    /// The one CTA colour. Black on light, white on dark — always the
    /// highest-contrast element on screen.
    static let accent = adaptive(light: 0x000000, dark: 0xFFFFFF)
    static let onAccent = adaptive(light: 0xFFFFFF, dark: 0x000000)

    static let hairline = adaptive(light: 0xECECEE, dark: 0x38373E)
    /// The faint lighter edge every card carries in dark, where the shadow
    /// does nothing. White on white in light, so it never shows there.
    static let cardEdge = adaptive(light: 0xFFFFFF, dark: 0x38373E)
    /// The unfilled part of every ring and bar.
    static let track = adaptive(light: 0xEDEDF0, dark: 0x38373E)

    // Semantic. These are Cal AI's macro colours, reused for score bands so a
    // number means the same thing wherever it appears.
    static let great = adaptive(light: 0x4CD964, dark: 0x5EE07A)
    static let good = adaptive(light: 0x4A90E2, dark: 0x5B9CF0)
    static let okay = adaptive(light: 0xE0A060, dark: 0xE8AC70)
    static let poor = adaptive(light: 0xA0A0A5, dark: 0x6F6F75)
    static let danger = adaptive(light: 0xE5645A, dark: 0xF07068)
    static let star = adaptive(light: 0xF5A623, dark: 0xF7B043)
    /// Companion avatars. The one place colour tells people apart rather
    /// than carrying meaning; four of six are the semantic tokens above.
    static let avatars: [Color] = [good, danger, great, adaptive(light: 0x8E7BC8, dark: 0x9C8AD6), star, adaptive(light: 0x3DAFB8, dark: 0x4FBFC8)]

    static func scoreColor(_ score: Int, blocked: Bool = false) -> Color {
        if blocked { return danger }
        switch score {
        case 85...: return great
        case 70 ..< 85: return good
        case 50 ..< 70: return okay
        default: return poor
        }
    }

    // MARK: - Geometry

    enum Radius {
        static let chip: CGFloat = 12
        static let row: CGFloat = 16
        static let tile: CGFloat = 18
        /// The white inner card of a two-level group, and the option rows
        /// and privacy card that share its corner.
        static let inner: CGFloat = 20
        static let card: CGFloat = 24
        /// The lavender outer card of a two-level group.
        static let section: CGFloat = 28
        static let sheet: CGFloat = 32
    }

    enum Space {
        static let xs: CGFloat = 6
        static let s: CGFloat = 10
        static let sm: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 22
        static let xl: CGFloat = 32
    }

    // MARK: - Type
    //
    // SF Pro, standard design. The reference sets headings and numerals in
    // the default face at bold weights; the rounded variant is not used
    // anywhere in the shipped app.
    //
    // Each text token rides on the system text style whose default size is
    // the size the reference was matched at, so it scales with the user's
    // text-size setting. The tokens keep their role names; the style behind
    // each is just the one with the right base size. `number` stays fixed —
    // ring numerals and stat figures are sized to their frames.

    static func number(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }

    /// 17pt at the default size.
    static let headline = Font.system(.headline, weight: .semibold)
    /// 16pt at the default size.
    static let body = Font.system(.callout, weight: .regular)
    /// 15pt at the default size.
    static let callout = Font.system(.subheadline, weight: .regular)
    /// 13pt at the default size.
    static let caption = Font.system(.footnote, weight: .medium)
    /// 11pt at the default size.
    static let micro = Font.system(.caption2, weight: .semibold)

    // MARK: - Motion

    static let snap = Animation.spring(response: 0.34, dampingFraction: 0.78)
    static let gentle = Animation.spring(response: 0.55, dampingFraction: 0.85)

    // MARK: - Helpers

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Card

extension View {
    /// The standard raised surface. The reference cards are almost flat — a
    /// single faint shadow that reads as a hairline of separation, not as
    /// elevation.
    ///
    /// The shadow belongs to the background shape, not to the composite, so
    /// content that animates inside the card does not re-blur it every frame.
    func card(padding: CGFloat = Theme.Space.m, radius: CGFloat = Theme.Radius.card) -> some View {
        self
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.surface)
                    .cardShadow()
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.cardEdge, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }

    /// The card's shadow, for anything else that sits on the ground as a
    /// white shape — Home's round You button. Apply it to the background
    /// shape, never to the composite.
    func cardShadow() -> some View {
        shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 2)
    }

    /// The detail screen's surface: white, a 1pt light-grey outline, and no
    /// shadow at all. The reference separates these tiles with the line alone.
    func tile(padding: CGFloat = Theme.Space.m) -> some View {
        self
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .fill(Theme.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            }
    }

    /// Nudges a view in from below as it appears, staggered by index.
    func riseIn(_ index: Int, isActive: Bool) -> some View {
        modifier(RiseIn(index: index, isActive: isActive))
    }
}

private struct RiseIn: ViewModifier {
    let index: Int
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 1 : 0)
            .offset(y: isActive ? 0 : 14)
            .animation(Theme.gentle.delay(min(Double(index) * 0.045, 0.5)), value: isActive)
    }
}

// MARK: - Scaled type

/// A fixed-size font that still follows the text-size setting. The default
/// size is exact; larger settings scale it like the text style it rides on.
private struct ScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
    }
}

extension View {
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> some View {
        modifier(ScaledFont(size: size, weight: weight, relativeTo: style))
    }
}

// MARK: - Haptics

enum Haptic {
    private static let impact = UIImpactFeedbackGenerator(style: .light)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    static func tap() { impact.impactOccurred(); impact.prepare() }
    static func select() { selection.selectionChanged(); selection.prepare() }
    static func success() { notification.notificationOccurred(.success); notification.prepare() }
    static func warning() { notification.notificationOccurred(.warning); notification.prepare() }
}
