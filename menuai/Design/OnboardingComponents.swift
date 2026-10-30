//
//  OnboardingComponents.swift
//  menuai
//
//  The onboarding vocabulary, matched to Cal AI's actual onboarding screens:
//  a back-circle-plus-bar header, a drawn phone for the welcome, a pastel
//  gradient ring for celebration moments, two-level cards (lavender outer,
//  white inner), editable summary tiles, a gradient progress bar for the
//  "setting up" screen, the without/with comparison and the trend chart.
//
//  Each illustration choreographs itself once on appear — a beat after the
//  step transition settles — and shows its final frame straight away when
//  Reduce Motion is on or `animated` is false. The two idle loops (the
//  viewfinder's breath, the ring's twinkle) stop when their view goes.
//

import SwiftUI

// MARK: - Palette additions used only here

extension Theme {
    /// The outer card of a two-level group: a lavender-grey a clear step
    /// below the ground, so the white inner cards read as sitting inside
    /// it. (One shade under `bg` was invisible on the ground.)
    static let sectionCard = adaptiveHex(light: 0xEEEEF2, dark: 0x232228)

    /// Gradient ring around celebration illustrations.
    static let ringGradient = LinearGradient(
        colors: [Color(hex: 0xF6D5DE), Color(hex: 0xE3DCF2), Color(hex: 0xD3DEF5)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// The "setting up" progress bar.
    static let progressGradient = LinearGradient(
        colors: [Color(hex: 0xE5645A), Color(hex: 0x8E7BC8), Color(hex: 0x4A90E2)],
        startPoint: .leading,
        endPoint: .trailing
    )

    private static func adaptiveHex(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            let v = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((v >> 16) & 0xFF) / 255,
                green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Motion scale

extension Theme {
    /// Every bespoke onboarding duration and delay is multiplied by this.
    /// 1 in release; the DEBUG hook `MENUAI_SELFTEST_MOTION=slow` makes it
    /// 3 so the choreography can be captured frame by frame.
    static let motionScale: Double = {
        #if DEBUG
        return SelfTest.motionScale
        #else
        return 1
        #endif
    }()

    /// `seconds` at the motion scale.
    static func paced(_ seconds: Double) -> Double { seconds * motionScale }
}

extension Animation {
    /// This animation at the motion scale.
    var paced: Animation { Theme.motionScale == 1 ? self : speed(1 / Theme.motionScale) }
}

/// Waits `seconds` at the motion scale. False once the view has gone, so a
/// choreography stops where it is instead of finishing off-screen.
private func settled(_ seconds: Double) async -> Bool {
    (try? await Task.sleep(for: .seconds(Theme.paced(seconds)))) != nil
}

/// The lead every illustration gives the step transition before its own
/// choreography starts.
private let stepSettle: Double = 0.12

// MARK: - Appear modifiers

/// Fades and rises a piece into place once `on` flips, `delay` seconds
/// after the first. With `motion` off nothing moves: `on` is already true.
private struct Reveal: ViewModifier {
    let on: Bool
    let motion: Bool
    let delay: Double
    let rise: CGFloat
    let animation: Animation

    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .offset(y: on ? 0 : rise)
            .animation(motion ? animation.paced.delay(Theme.paced(delay)) : nil, value: on)
    }
}

/// Pops a piece in from `from` scale once `on` flips.
private struct Pop: ViewModifier {
    let on: Bool
    let motion: Bool
    let delay: Double
    let from: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(on ? 1 : from)
            .opacity(on ? 1 : 0)
            .animation(motion ? Theme.snap.paced.delay(Theme.paced(delay)) : nil, value: on)
    }
}

private extension View {
    func reveal(_ on: Bool, motion: Bool, delay: Double = 0, rise: CGFloat = 6, animation: Animation = Theme.gentle) -> some View {
        modifier(Reveal(on: on, motion: motion, delay: delay, rise: rise, animation: animation))
    }

    func pop(_ on: Bool, motion: Bool, delay: Double = 0, from: CGFloat = 0) -> some View {
        modifier(Pop(on: on, motion: motion, delay: delay, from: from))
    }
}

// MARK: - Header: back circle + progress bar on one row

/// The same back circle every pushed screen wears, beside one continuous
/// black progress bar.
struct OnboardingHeader: View {
    let progress: Double
    let showsBack: Bool
    let onBack: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            BackCircleButton(action: onBack)
                .opacity(showsBack ? 1 : 0)
                .disabled(!showsBack)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule()
                        .fill(Theme.ink)
                        .frame(width: max(0, geo.size.width * min(max(progress, 0), 1)))
                }
            }
            .frame(height: 4)
            .accessibilityElement()
            .accessibilityLabel("Progress")
            .accessibilityValue("\(Int((min(max(progress, 0), 1) * 100).rounded())) percent")
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.top, Theme.Space.s)
        // The bar slides to the next step's width with the step itself.
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Theme.gentle, value: progress)
    }
}

// MARK: - Device mockup

/// The welcome illustration: a drawn phone whose screen shows a menu under
/// viewfinder brackets. No assets — a black frame, a light page of grey
/// text lines in two columns (dish, price), a grey header band and four
/// corner brackets.
///
/// On appear the phone scales in, the header band and the lines land one
/// after another, then the brackets lock on to the page like a camera
/// focusing and keep breathing gently until the screen goes.
struct DeviceMockup: View {
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var locked = false
    @State private var breath: CGFloat = 0

    private static let width: CGFloat = 236
    private static let height: CGFloat = 470
    private static let radius: CGFloat = 44
    private static let bezel: CGFloat = 10
    private static let bracketInset: CGFloat = 22
    private static let bracketInsetVertical: CGFloat = 64
    private static let headerHeight: CGFloat = 56
    private static let pageInset: CGFloat = 24
    private static let priceWidth: CGFloat = 26
    /// Dish-name widths as a share of the page, varied so the lines read as
    /// text rather than a grid.
    private static let dishShares: [CGFloat] = [0.62, 0.46, 0.70, 0.40, 0.56, 0.66, 0.48]

    /// How far outside their final inset the brackets start.
    private static let bracketSlack: CGFloat = 12
    /// The idle breath, either side of the final inset.
    private static let breathSwing: CGFloat = 3
    /// The band lands first; each line is this far behind the last.
    private static let linesStart = 0.15
    private static let lineGap = 0.04
    /// Each line lands on its own: a spring here left all seven half-in at
    /// once and the cascade read as a smear.
    private static let lineLanding = Animation.easeOut(duration: 0.22)

    private var motion: Bool { animated && !reduceMotion }
    private var on: Bool { shown || !motion }
    private var slack: CGFloat { locked || !motion ? 0 : Self.bracketSlack }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .fill(Theme.accent)

            screen
                .clipShape(.rect(cornerRadius: Self.radius - Self.bezel, style: .continuous))
                .padding(Self.bezel)

            // The notch: a small pill in the frame's colour over the screen.
            Capsule()
                .fill(Theme.accent)
                .frame(width: 72, height: 20)
                .padding(.top, Self.bezel + 10)
        }
        .frame(width: Self.width, height: Self.height)
        // Flattened before it fades: opacity applied per child let the
        // black frame show through the white screen, so the page read as
        // grey until the phone was fully in.
        .compositingGroup()
        .scaleEffect(on ? 1 : 0.92)
        .opacity(on ? 1 : 0)
        .animation(motion ? Theme.gentle.paced : nil, value: on)
        .accessibilityHidden(true)
        .task { await choreograph() }
        .onDisappear { breath = 0 }
    }

    private var screen: some View {
        let pageWidth = Self.width - Self.bezel * 2 - Self.pageInset * 2
        return ZStack {
            Theme.surface

            VStack(spacing: 0) {
                Theme.surfaceSunken
                    .frame(height: Self.headerHeight)
                    .reveal(on, motion: motion, delay: Self.linesStart, animation: Self.lineLanding)

                // Spread down the page, so the screen reads as a full menu
                // rather than a list hanging from the top.
                VStack(spacing: 30) {
                    ForEach(Array(Self.dishShares.enumerated()), id: \.offset) { index, share in
                        HStack(spacing: 0) {
                            Capsule()
                                .fill(Theme.track)
                                .frame(width: pageWidth * share, height: 8)
                            Spacer(minLength: 0)
                            Capsule()
                                .fill(Theme.track)
                                .frame(width: Self.priceWidth, height: 8)
                        }
                        .reveal(on, motion: motion, delay: Self.linesStart + Self.lineGap * Double(index + 1), animation: Self.lineLanding)
                    }
                }
                .padding(.horizontal, Self.pageInset)
                // Below the top brackets' legs (measured from the screen's
                // top, so less the header band above), so the lines sit
                // inside the viewfinder rather than under its corners.
                .padding(.top, Self.bracketInsetVertical + 28 + Theme.Space.sm - Self.headerHeight)

                Spacer(minLength: 0)
            }

            // One clean grey stroke, centred on the page below the notch
            // and header band. Grey reads over the white page in light and
            // over the dark screen in dark; a white line with an ink halo
            // read as a bevelled double line.
            // The lock-on and the breath move the shape's own inset, not
            // its padding: padding is layout, and re-laying out the phone
            // every frame of the idle loop re-rasterised it offscreen.
            ViewfinderCorners(length: 28, inset: -slack + breath)
                .stroke(Theme.inkSecondary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .padding(.horizontal, Self.bracketInset)
                .padding(.vertical, Self.bracketInsetVertical)
        }
    }

    private func choreograph() async {
        guard motion, await settled(stepSettle) else { return }
        shown = true

        // The brackets lock on once the last line has landed — the beat the
        // title rises on.
        guard await settled(Self.linesStart + Self.lineGap * Double(Self.dishShares.count + 1) + 0.08) else { return }
        withAnimation(Theme.snap.paced) { locked = true }

        // Half a breath out, then the loop between the two extremes.
        guard await settled(0.45) else { return }
        withAnimation(.easeInOut(duration: Theme.paced(0.8))) { breath = Self.breathSwing }
        guard await settled(0.8) else { return }
        withAnimation(.easeInOut(duration: Theme.paced(1.6)).repeatForever(autoreverses: true)) {
            breath = -Self.breathSwing
        }
    }
}

/// Four L-shaped corner marks, each `length` long, at the corners of the
/// rect inset by `inset` (negative = outside it). The inset animates.
private struct ViewfinderCorners: Shape {
    let length: CGFloat
    var inset: CGFloat = 0

    var animatableData: CGFloat {
        get { inset }
        set { inset = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + length))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + length, y: r.minY))

        p.move(to: CGPoint(x: r.maxX - length, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + length))

        p.move(to: CGPoint(x: r.maxX, y: r.maxY - length))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - length, y: r.maxY))

        p.move(to: CGPoint(x: r.minX + length, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - length))
        return p
    }
}

// MARK: - Celebration ring

/// Pastel gradient ring with a white centre and a scatter of small dots —
/// the frame around every celebration moment in the reference.
///
/// On appear the ring scales in as its gradient fades up, the dots pop in
/// one by one after the centre has had its moment, then twinkle until the
/// screen goes. The content is left alone: the screen that owns the icon
/// pops it and gives it its gesture.
struct CelebrationRing<Content: View>: View {
    var animated: Bool = true
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var twinkling = false

    private let dots: [(CGFloat, CGFloat, CGFloat)] = [
        (0.30, 0.18, 4), (0.72, 0.16, 3), (0.20, 0.38, 3), (0.82, 0.36, 4),
        (0.16, 0.60, 4), (0.86, 0.62, 3), (0.28, 0.82, 3), (0.74, 0.84, 4),
        (0.50, 0.12, 3), (0.50, 0.88, 3),
    ]

    /// The dots follow the centre icon's pop (0.2 s in, a snap long); each
    /// is this far behind the last. (Computed: a generic type cannot hold
    /// static stored properties.)
    private static var dotsStart: Double { 0.35 }
    private static var dotGap: Double { 0.03 }

    private var motion: Bool { animated && !reduceMotion }
    private var on: Bool { shown || !motion }

    var body: some View {
        ZStack {
            ZStack {
                Circle()
                    .strokeBorder(Theme.ringGradient, lineWidth: 32)
                Circle()
                    .fill(Theme.surface)
                    .padding(32)
            }
            .scaleEffect(on ? 1 : 0.85)
            .opacity(on ? 1 : 0)
            .animation(motion ? Theme.gentle.paced : nil, value: on)

            GeometryReader { geo in
                ForEach(Array(dots.enumerated()), id: \.offset) { index, dot in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Theme.ink)
                        .frame(width: dot.2, height: dot.2)
                        .rotationEffect(.degrees(28))
                        .scaleEffect(on ? 1 : 0)
                        .animation(motion ? Theme.snap.paced.delay(Theme.paced(Self.dotsStart + Self.dotGap * Double(index))) : nil, value: on)
                        .opacity(twinkling ? 0.35 : 1)
                        .animation(twinkling ? Self.twinkle(index) : nil, value: twinkling)
                        .position(x: geo.size.width * dot.0, y: geo.size.height * dot.1)
                }
            }
            .padding(44)
            .accessibilityHidden(true)

            content
        }
        .frame(width: 240, height: 240)
        .task {
            guard motion, await settled(stepSettle) else { return }
            shown = true
            // Once the last dot has popped.
            guard await settled(Self.dotsStart + Self.dotGap * Double(dots.count) + 0.35) else { return }
            twinkling = true
        }
        .onDisappear { twinkling = false }
    }

    /// Each dot on its own period, 1.4–2.2 s, and its own start, so they
    /// never dim as a group: in step, the first half-cycle read as the ring
    /// blinking.
    private static func twinkle(_ index: Int) -> Animation {
        let period = 1.4 + 0.8 * Double((index * 7) % 10) / 9
        return .easeInOut(duration: Theme.paced(period))
            .repeatForever(autoreverses: true)
            .delay(Theme.paced(Double(index) * 0.17))
    }
}

// MARK: - Privacy card

/// The trust screen's promise: a grey card with a white lock disc floating
/// half above its top edge, a short title and one line under it.
struct PrivacyCard: View {
    let title: String
    private let message: String

    private static let discSize: CGFloat = 44

    init(title: String, body: String) {
        self.title = title
        self.message = body
    }

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            Text(title)
                .scaledFont(size: 17, weight: .semibold, relativeTo: .headline)
                .foregroundStyle(Theme.ink)
            Text(message)
                .scaledFont(size: 13, relativeTo: .footnote)
                .foregroundStyle(Theme.inkSecondary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.l + Self.discSize / 2)
        .padding(.bottom, Theme.Space.l)
        .background(Theme.surfaceSunken, in: .rect(cornerRadius: Theme.Radius.inner, style: .continuous))
        .overlay(alignment: .top) {
            ZStack {
                Circle()
                    .fill(Theme.surface)
                    .cardShadow()
                Image(systemName: "lock.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .frame(width: Self.discSize, height: Self.discSize)
            .offset(y: -Self.discSize / 2)
            .accessibilityHidden(true)
        }
        // Room above for the half of the disc that floats over the edge.
        .padding(.top, Self.discSize / 2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Two-level cards

/// Light outer card with a heading; put white `InnerCard`s inside.
struct SectionCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .scaledFont(size: 22, weight: .bold, relativeTo: .title2)
                    .foregroundStyle(Theme.ink)
                if let subtitle {
                    Text(subtitle)
                        .scaledFont(size: 16, relativeTo: .callout)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.l)
        .background(Theme.sectionCard, in: .rect(cornerRadius: Theme.Radius.section, style: .continuous))
    }
}

struct InnerCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.m)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous)
                    .fill(Theme.surface)
                    .shadow(color: .black.opacity(0.03), radius: 8, y: 2)
            }
            // The shadow vanishes in dark; the edge is white-on-white in light.
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous)
                    .strokeBorder(Theme.cardEdge, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

// MARK: - Check stamp

/// The summary's black stamp, drawing itself: the disc scales in, then the
/// tick is stroked from its short arm to its long one.
struct CheckStamp: View {
    var size: CGFloat = 48
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    /// The tick starts once the disc has mostly settled.
    private static let tickDelay = 0.3
    private static let tickDraw = 0.35

    private var motion: Bool { animated && !reduceMotion }
    private var on: Bool { shown || !motion }

    var body: some View {
        ZStack {
            Circle().fill(Theme.accent)
            CheckMark()
                .trim(from: 0, to: on ? 1 : 0)
                .stroke(Theme.onAccent, style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round, lineJoin: .round))
                .animation(motion ? .easeOut(duration: Theme.paced(Self.tickDraw)).delay(Theme.paced(Self.tickDelay)) : nil, value: on)
        }
        .frame(width: size, height: size)
        .scaleEffect(on ? 1 : 0.5)
        .opacity(on ? 1 : 0)
        .animation(motion ? Theme.gentle.paced : nil, value: on)
        .accessibilityHidden(true)
        .task {
            // Without motion the stamp is already there; the tap still is.
            guard motion else { Haptic.success(); return }
            guard await settled(stepSettle) else { return }
            shown = true
            // As the tick's long arm lands.
            guard await settled(Self.tickDelay + Self.tickDraw * 0.7) else { return }
            Haptic.success()
        }
    }
}

/// A tick in the proportions of the bold SF checkmark: a short arm down,
/// a long arm up.
private struct CheckMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.28, y: r.minY + r.height * 0.53))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.44, y: r.minY + r.height * 0.68))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.72, y: r.minY + r.height * 0.36))
        return p
    }
}

// MARK: - Editable tiles

/// One cell of the summary's 2×2 grid: a small tinted icon beside its
/// label, the value in bold under them, and a pencil in the bottom-right
/// corner that jumps back to the question.
struct SummaryTile: View {
    let icon: String
    let tint: Color
    let label: String
    let value: String
    let onEdit: () -> Void

    var body: some View {
        InnerCard {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.s) {
                    ZStack {
                        Circle().fill(tint.opacity(0.14)).frame(width: 28, height: 28)
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    .accessibilityHidden(true)
                    Text(label)
                        .scaledFont(size: 15, weight: .medium, relativeTo: .subheadline)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text(value)
                    .scaledFont(size: 22, weight: .bold, relativeTo: .title2)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Its own row, not beside the value: a half-width tile
                // leaves "Vegetarian" ~88pt next to a pencil, and it broke
                // mid-word. Not an overlay either: a two-line value would
                // run under a pencil pinned to the corner.
                HStack {
                    Spacer(minLength: 0)
                    PencilButton(label: label, action: onEdit)
                }
            }
            // Fills whatever height its row settles on, so two tiles whose
            // values wrap unevenly still share one bottom edge.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

private struct PencilButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            Image(systemName: "pencil")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle().inset(by: -8))
        }
        .buttonStyle(.press)
        .accessibilityLabel("Edit \(label)")
        // Tucked into the card's corner, past the content padding.
        .offset(x: Theme.Space.xs, y: Theme.Space.xs)
    }
}

/// "Label: **Value**" with an icon — the rows of the "Your info" card.
struct InfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text("\(label): \(Text(value).bold())")
                .scaledFont(size: 17, relativeTo: .body)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Without / with comparison

/// Two white cards. On appear they fade up, then the ✗ lines tick in one by
/// one and the ✓ lines after them, with a selection tick on the first ✓.
/// The lavender card around them belongs to the screen.
struct ComparisonCard: View {
    let withoutTitle: String
    let without: [String]
    let withTitle: String
    let with: [String]
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    /// The first ✗ lands once the cards are mostly up; each line is a
    /// `tickGap` behind the last, and the ✓ column starts a beat after the
    /// ✗ column has finished.
    private static let firstTick = 0.3
    private static let tickGap = 0.06
    private static let firstCheck = 0.6

    private var motion: Bool { animated && !reduceMotion }
    private var on: Bool { shown || !motion }

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            InnerCard {
                column(title: withoutTitle, lines: without, glyph: "xmark", tint: Theme.danger, start: Self.firstTick)
            }
            // The lavender card around them carries the rise; a second one
            // here had the white cards sliding inside a sliding card.
            .reveal(on, motion: motion, rise: 0)
            InnerCard {
                column(title: withTitle, lines: with, glyph: "checkmark", tint: Theme.great, start: Self.firstCheck)
            }
            .reveal(on, motion: motion, delay: 0.08, rise: 0)
        }
        .task {
            guard motion, await settled(stepSettle) else { return }
            shown = true
            guard await settled(Self.firstCheck) else { return }
            Haptic.select()
        }
    }

    private func column(title: String, lines: [String], glyph: String, tint: Color, start: Double) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(title).scaledFont(size: 18, weight: .semibold, relativeTo: .title3).foregroundStyle(Theme.ink)
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                let at = start + Self.tickGap * Double(index)
                HStack(spacing: 10) {
                    Image(systemName: glyph)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                        .pop(on, motion: motion, delay: at, from: 0.4)
                    Text(line)
                        .scaledFont(size: 17, relativeTo: .body)
                        .foregroundStyle(Theme.ink)
                        .reveal(on, motion: motion, delay: at)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Trend chart

/// Two smooth curves over dashed gridlines: the app's line rising, the
/// "without" line falling away. Illustrative, and captioned as such.
///
/// On appear the curves draw from left to right — "Guessing" first, ours
/// a beat behind — their fills fade up as they finish, the endpoints pop
/// where each curve arrives and the labels follow. The caption under the
/// chart belongs to the screen and rises last.
struct TrendChart: View {
    let title: String
    let ourLabel: String
    let theirLabel: String
    let startLabel: String
    let endLabel: String
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    /// The draw, in seconds after the chart starts.
    private static let theirsDraw = 0.9
    private static let oursDelay = 0.2
    private static let oursDraw = 1.1
    private static let fillFade = 0.4
    private static var oursArrives: Double { oursDelay + oursDraw }

    private var motion: Bool { animated && !reduceMotion }
    private var on: Bool { shown || !motion }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(title)
                .scaledFont(size: 24, weight: .semibold, relativeTo: .title2)
                .foregroundStyle(Theme.ink)
                .reveal(on, motion: motion, rise: 14)

            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack(alignment: .topLeading) {
                    ForEach([0.15, 0.55], id: \.self) { y in
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: h * y))
                            p.addLine(to: CGPoint(x: w, y: h * y))
                        }
                        // A token with opacity, like the fills: the track
                        // grey vanished on the lavender card in light.
                        .stroke(Theme.inkTertiary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }

                    // Up is better: the chart is titled for the outcome, so
                    // the reference's falling weight curve is mirrored here.
                    // "Without": a lucky pick, then back down to the bottom.
                    let theirsPts: [(CGFloat, CGFloat)] = [(0, 0.80), (0.35, 0.38), (0.70, 0.70), (1.0, 0.96)]
                    area(w: w, h: h, points: theirsPts)
                        .fill(LinearGradient(colors: [Theme.danger.opacity(0.16), .clear], startPoint: .top, endPoint: .bottom))
                        .opacity(on ? 1 : 0)
                        .animation(fade(delay: Self.theirsDraw - Self.fillFade), value: on)
                    curve(w: w, h: h, points: theirsPts)
                        .trim(from: 0, to: on ? 1 : 0)
                        .stroke(Theme.danger, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .animation(draw(Self.theirsDraw, delay: 0), value: on)

                    // Ours: holds, then climbs to the top.
                    let oursPts: [(CGFloat, CGFloat)] = [(0, 0.80), (0.30, 0.78), (0.62, 0.30), (1.0, 0.06)]
                    area(w: w, h: h, points: oursPts)
                        .fill(LinearGradient(colors: [Theme.ink.opacity(0.14), .clear], startPoint: .top, endPoint: .bottom))
                        .opacity(on ? 1 : 0)
                        .animation(fade(delay: Self.oursArrives - Self.fillFade), value: on)
                    curve(w: w, h: h, points: oursPts)
                        .trim(from: 0, to: on ? 1 : 0)
                        .stroke(Theme.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .animation(draw(Self.oursDraw, delay: Self.oursDelay), value: on)

                    endpoint(at: CGPoint(x: 0, y: h * 0.80), arrives: 0)
                    endpoint(at: CGPoint(x: w, y: h * 0.06), arrives: Self.oursArrives)

                    Text(theirLabel)
                        .scaledFont(size: 15, relativeTo: .subheadline)
                        .foregroundStyle(Theme.ink)
                        .reveal(on, motion: motion, delay: Self.theirsDraw)
                        .position(x: w * 0.32, y: h * 0.28)

                    Text(ourLabel)
                        .scaledFont(size: 14, weight: .semibold, relativeTo: .footnote)
                        .foregroundStyle(Theme.ink)
                        .reveal(on, motion: motion, delay: Self.oursArrives)
                        .position(x: w * 0.68, y: h * 0.10)
                }
            }
            .frame(height: 190)

            HStack {
                Text(startLabel)
                Spacer()
                Text(endLabel)
            }
            .scaledFont(size: 15, relativeTo: .subheadline)
            .foregroundStyle(Theme.ink)
            .reveal(on, motion: motion, delay: 0.1)
        }
        // One element: six loose labels said nothing about the picture.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(ourLabel) rises from \(startLabel) to \(endLabel). \(theirLabel) sinks.")
        .task {
            guard motion, await settled(stepSettle) else { return }
            shown = true
        }
    }

    private func draw(_ duration: Double, delay: Double) -> Animation? {
        motion ? .easeInOut(duration: Theme.paced(duration)).delay(Theme.paced(delay)) : nil
    }

    private func fade(delay: Double) -> Animation? {
        motion ? .easeInOut(duration: Theme.paced(Self.fillFade)).delay(Theme.paced(delay)) : nil
    }

    /// The open line. Stroking a closed path would draw its closing edges
    /// too — a vertical line up the right side and a baseline.
    private func curve(w: CGFloat, h: CGFloat, points: [(CGFloat, CGFloat)]) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: CGPoint(x: w * first.0, y: h * first.1))
        for i in 1 ..< points.count {
            let a = points[i - 1], b = points[i]
            let ax = w * a.0, ay = h * a.1, bx = w * b.0, by = h * b.1
            let mid = (ax + bx) / 2
            p.addCurve(to: CGPoint(x: bx, y: by), control1: CGPoint(x: mid, y: ay), control2: CGPoint(x: mid, y: by))
        }
        return p
    }

    /// The same line closed down to the baseline, for the fill only.
    private func area(w: CGFloat, h: CGFloat, points: [(CGFloat, CGFloat)]) -> Path {
        var p = curve(w: w, h: h, points: points)
        p.addLine(to: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: 0, y: h))
        p.closeSubpath()
        return p
    }

    /// A hollow dot that pops when a curve reaches it.
    private func endpoint(at point: CGPoint, arrives: Double) -> some View {
        Circle()
            .fill(Theme.surface)
            .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 3))
            .frame(width: 18, height: 18)
            .pop(on, motion: motion, delay: arrives)
            .position(point)
    }
}

// MARK: - Setting-up progress

struct GradientProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(Theme.progressGradient)
                    .frame(width: max(0, geo.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: 10)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((min(max(progress, 0), 1) * 100).rounded())) percent")
    }
}

struct ChecklistCard: View {
    let title: String
    let items: [String]
    let completed: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(title)
                .scaledFont(size: 17, weight: .semibold, relativeTo: .headline)
                .foregroundStyle(Theme.ink)
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack {
                    Text("•").foregroundStyle(Theme.ink)
                    Text(item).scaledFont(size: 17, relativeTo: .body).foregroundStyle(Theme.ink)
                    Spacer()
                    if index < completed {
                        ZStack {
                            Circle().fill(Theme.accent).frame(width: 24, height: 24)
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.onAccent)
                        }
                        // Each tick scales in with a snap as its step lands.
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item)
                .accessibilityValue(index < completed ? "Done" : "")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Theme.Space.l)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Theme.snap.paced, value: completed)
    }
}
