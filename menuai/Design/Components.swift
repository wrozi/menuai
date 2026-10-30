//
//  Components.swift
//  menuai
//
//  The shared vocabulary: rings, pills, stars, chips. Every screen is built
//  from these so nothing drifts.
//

import SwiftUI

// MARK: - Score ring

/// The signature element. A ring that fills to the match score, with the
/// number counting up alongside it so the motion and the value agree.
struct ScoreRing: View {
    let score: Int
    var blocked: Bool = false
    var size: CGFloat = 52
    var lineWidth: CGFloat = 5

    @State private var animated: Double = 0

    private var color: Color { Theme.scoreColor(score, blocked: blocked) }
    private var target: Double { Double(min(max(score, 0), 100)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(blocked ? color.opacity(0.18) : Theme.track, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: blocked ? 1 : max(animated / 100, 0.008))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            if blocked {
                Image(systemName: "exclamationmark")
                    .font(Theme.number(size * 0.38, weight: .heavy))
                    .foregroundStyle(color)
            } else {
                CountingNumber(value: animated)
                    .font(Theme.number(size * 0.34))
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(blocked ? "Not for you" : "\(score) percent match")
        .onAppear { run() }
        .onChange(of: score) { _, _ in withAnimation(Theme.gentle) { animated = target } }
    }

    private func run() {
        guard !blocked else { return }
        withAnimation(.easeOut(duration: 0.9)) { animated = target }
    }
}

/// Renders a whole number that animates through the intermediate values.
///
/// `Text` alone would jump straight to the final number, because SwiftUI
/// animates the view's geometry rather than the value behind its string.
/// Conforming to `Animatable` makes the interpolated value available on every
/// frame, which is both smoother and far cheaper than scheduling one timer
/// block per integer step.
struct CountingNumber: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(value.rounded()))")
            .monospacedDigit()
    }
}

// MARK: - Buttons

/// The one press response every tappable thing uses. `isPressed` comes from
/// the platform's button tracking, so a scroll that starts on a row cancels
/// it cleanly — a hand-rolled DragGesture never gets `onEnded` in that case.
struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect)
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Theme.snap, value: configuration.isPressed)
    }
}
extension ButtonStyle where Self == PressStyle {
    static var press: PressStyle { PressStyle() }
    static func press(scale: CGFloat) -> PressStyle { PressStyle(scale: scale) }
}

/// The back button: a flat light-grey circle in place of the system's glass
/// disc and its shadow, with the reference's straight arrow rather than a
/// chevron. Pops the screen unless given something else to do, as the
/// onboarding header does.
struct BackCircleButton: View {
    var action: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            Haptic.tap()
            if let action { action() } else { dismiss() }
        } label: {
            Image(systemName: "arrow.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .background(Theme.surfaceSunken, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.press(scale: 0.94))
        .accessibilityLabel("Back")
    }
}

extension View {
    /// Puts `BackCircleButton` where the system back button was, on a bar
    /// painted opaque in the page's `ground` so nothing scrolls through it,
    /// and keeps a swipe back. Hiding the system button makes UIKit refuse
    /// its own pop gesture, and handing that recogniser a new delegate pops
    /// the UIKit stack without telling the `NavigationStack`, which left Home
    /// drawn under a stale bar. So the swipe is SwiftUI's: a drag from a strip
    /// along the left bezel that dismisses. It animates rather than tracks
    /// the finger, and the path stays in step.
    ///
    /// The strip, not a gesture over the whole page: a drag attached
    /// simultaneously to the content fires whatever button it ends over, so
    /// a swipe that finished on a card popped this screen and pushed that
    /// dish in the same breath.
    func circleBackButton(ground: Color = Theme.bg) -> some View {
        modifier(CircleBackButton(ground: ground))
    }
}

private struct CircleBackButton: ViewModifier {
    let ground: Color

    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbarBackground(ground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { BackCircleButton() }
                    .sharedBackgroundVisibility(.hidden)
            }
            .overlay(alignment: .leading) {
                Color.clear
                    .frame(width: 20)
                    .contentShape(.rect)
                    .gesture(
                        DragGesture(minimumDistance: 20, coordinateSpace: .global)
                            .onEnded { value in
                                // Mostly sideways and far enough to mean it.
                                guard value.translation.width > 80,
                                      abs(value.translation.height) < value.translation.width
                                else { return }
                                dismiss()
                            }
                    )
                    .accessibilityHidden(true)
            }
    }
}

/// Full-width high-contrast CTA. There is at most one of these on a screen.
struct PillButton: View {
    let title: String
    var icon: String?
    /// 54 on its own; the pinned bottom bar asks for 52 to match its
    /// outlined neighbour.
    var height: CGFloat = 54
    /// Semibold on its own; the pinned bottom bar asks for medium, the
    /// reference's lighter pair.
    var weight: Font.Weight = .semibold
    let action: () -> Void

    var body: some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).scaledFont(size: 16, weight: weight, relativeTo: .headline) }
                Text(title).scaledFont(size: 17, weight: weight, relativeTo: .headline).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, Theme.Space.sm)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Theme.accent, in: .capsule)
        }
        .buttonStyle(.press)
    }
}

/// Secondary action — same geometry, no fill.
struct GhostButton: View {
    let title: String
    var icon: String?
    let action: () -> Void

    var body: some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).scaledFont(size: 16, weight: .semibold, relativeTo: .headline) }
                Text(title).font(Theme.headline)
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Theme.surfaceSunken, in: .capsule)
        }
        .buttonStyle(.press)
    }
}

/// The quiet half of a pair: same capsule, drawn as an outline. Sits to the
/// left of a filled `PillButton` in the pinned bottom bar, and nowhere else
/// needs more than one of them.
private struct OutlinedPillButton: View {
    let title: String
    var icon: String?
    let action: () -> Void

    var body: some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).scaledFont(size: 16, weight: .medium, relativeTo: .headline) }
                Text(title).scaledFont(size: 17, weight: .medium, relativeTo: .headline).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, Theme.Space.sm)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .overlay { Capsule().strokeBorder(Theme.ink, lineWidth: 1.5) }
            .contentShape(.capsule)
        }
        .buttonStyle(.press)
    }
}

/// The filled capsule pinned under a pushed screen, with an optional outlined
/// one to its left. Attach with `.safeAreaInset(edge: .bottom, spacing: 0)`;
/// the white runs down behind the home indicator and the buttons stay above it.
struct BottomActionBar: View {
    struct Item {
        let title: String
        var icon: String?
        let action: () -> Void

        init(title: String, icon: String? = nil, action: @escaping () -> Void) {
            self.title = title
            self.icon = icon
            self.action = action
        }
    }

    var secondary: Item? = nil
    let primary: Item

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Half a screen each is all a pair of labels gets. From xxLarge the
        // glyphs give their room to the words, and the words stop growing at
        // xxxLarge — a verb cut to "Show the w…" is worse than a 23pt one.
        let showsIcons = typeSize < .xxLarge
        return HStack(spacing: Theme.Space.s) {
            if let secondary {
                OutlinedPillButton(title: secondary.title, icon: showsIcons ? secondary.icon : nil, action: secondary.action)
            }
            PillButton(title: primary.title, icon: showsIcons ? primary.icon : nil, height: 52, weight: .medium, action: primary.action)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, Theme.Space.m)
        .padding(.top, Theme.Space.m)
        .padding(.bottom, Theme.Space.s)
        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
    }
}

// MARK: - Stars

/// Vivino-style rating. Read-only when `onRate` is nil.
struct StarRating: View {
    let rating: Int
    var size: CGFloat = 16
    var onRate: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: onRate == nil ? size * 0.18 : 0) {
            ForEach(1 ... 5, id: \.self) { value in
                if let onRate {
                    Button {
                        guard value != rating else { return }
                        Haptic.select()
                        withAnimation(Theme.snap) { onRate(value) }
                    } label: {
                        star(value)
                            .frame(width: max(size * 1.5, 30), height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.press(scale: 0.85))
                } else {
                    star(value)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue(rating == 0 ? "Not rated" : "\(rating) of 5")
        .accessibilityAdjustableAction { direction in
            guard let onRate else { return }
            switch direction {
            case .increment: if rating < 5 { onRate(rating + 1) }
            case .decrement: if rating > 1 { onRate(rating - 1) }
            @unknown default: break
            }
        }
    }

    private func star(_ value: Int) -> some View {
        Image(systemName: value <= rating ? "star.fill" : "star")
            .font(.system(size: size))
            .foregroundStyle(value <= rating ? Theme.star : Theme.inkTertiary)
            .contentTransition(.symbolEffect(.replace))
    }
}

// MARK: - Chips & tags

struct Chip: View {
    let text: String
    var icon: String?
    var tint: Color = Theme.inkSecondary

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).scaledFont(size: 10, weight: .bold, relativeTo: .caption2) }
            Text(text).lineLimit(1).font(Theme.micro)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: .capsule)
    }
}

/// Selectable chip; FormControls builds the pickers from it.
struct ToggleChip: View {
    let text: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptic.select()
            withAnimation(Theme.snap) { action() }
        } label: {
            Text(text)
                .lineLimit(1)
                .font(Theme.caption)
                .foregroundStyle(isOn ? Theme.onAccent : Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surfaceSunken),
                    in: .capsule
                )
                .overlay {
                    if !isOn {
                        Capsule().strokeBorder(Theme.hairline, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.press(scale: 0.96))
    }
}

// MARK: - Structure

/// Empty state: an icon, a title and one line.
struct EmptyBlock: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.inkTertiary)
                .accessibilityHidden(true)
            Text(title).font(Theme.headline).foregroundStyle(Theme.ink)
            if !message.isEmpty {
                Text(message)
                    .font(Theme.callout)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.xl)
    }
}

// MARK: - Flow layout

/// Wrapping row layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0

        for subview in subviews {
            let raw = subview.sizeThatFits(.unspecified)
            let size = CGSize(width: min(raw.width, maxWidth), height: raw.height)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let maxWidth = proposal.width ?? bounds.width
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0

        for subview in subviews {
            let raw = subview.sizeThatFits(.unspecified)
            let size = CGSize(width: min(raw.width, maxWidth), height: raw.height)
            if x - bounds.minX + size.width > maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Pills & small stats (reference style)

/// The rank pill a pick wears.
struct RankBadge: View {
    let rank: Int

    var body: some View {
        Text("#\(rank)")
            .font(Theme.micro)
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.accent, in: .capsule)
    }
}

/// The small grey capsule that carries a time on a card.
struct TimePill: View {
    let text: String

    var body: some View {
        Text(text)
            .scaledFont(size: 12, weight: .medium, relativeTo: .caption)
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, 5)
            .background(Theme.surfaceSunken, in: .capsule)
            .fixedSize()
    }
}

/// A coloured glyph and a short figure — one of the macros along the bottom
/// of a reference card.
struct IconStat: View {
    let icon: String
    var tint: Color = Theme.inkSecondary
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .scaledFont(size: 13, weight: .semibold, relativeTo: .footnote)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .scaledFont(size: 13, weight: .medium, relativeTo: .footnote)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
        }
    }
}

/// A bold heading that sits straight on the page ground, with room for a
/// small trailing figure — "Recently uploaded", "Ingredients", "Nutritions".
struct GroundHeader<Trailing: View>: View {
    let title: String
    private let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text(title)
                .scaledFont(size: 20, weight: .bold, relativeTo: .title3)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 2)
    }
}

extension GroundHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

// MARK: - Media card (reference style)

/// A card with a square photo set inside it — its own rounded corners, a
/// small margin from the card's edge — and the text to its right. The card
/// grows with its content; the photo keeps its size and stays centred on it.
struct MediaCard<Content: View>: View {
    let thumbnail: String?
    let placeholder: String
    private let content: Content

    @State private var image: UIImage?

    /// The photo's side. With its margin on three sides the card is 120pt.
    private static var photoSide: CGFloat { 96 }

    init(thumbnail: String?, placeholder: String, @ViewBuilder content: () -> Content) {
        self.thumbnail = thumbnail
        self.placeholder = placeholder
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            // A fixed square; the photo rides on it as an overlay so its own
            // size never drives layout, and the clip cuts the overflow.
            Theme.track
                .frame(width: Self.photoSide, height: Self.photoSide)
                .overlay {
                    if let shown = image ?? ThumbnailCache.cached(thumbnail) {
                        Image(uiImage: shown).resizable().scaledToFill()
                    } else {
                        Image(systemName: placeholder)
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }
                .clipShape(.rect(cornerRadius: Theme.Radius.chip, style: .continuous))
                .padding([.top, .leading, .bottom], Theme.Space.sm)
                .accessibilityHidden(true)

            content
                .padding(Theme.Space.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: Self.photoSide + Theme.Space.sm * 2)
        // Ideal height, whatever the container offers — never the full screen.
        .fixedSize(horizontal: false, vertical: true)
        .card(padding: 0)
        .contentShape(.rect(cornerRadius: Theme.Radius.card, style: .continuous))
        .task(id: thumbnail) {
            // Reset from the cache first so a reused row whose name changed
            // never shows the previous bitmap.
            image = ThumbnailCache.cached(thumbnail)
            guard image == nil, let thumbnail, !thumbnail.isEmpty else { return }
            image = await ThumbnailCache.load(thumbnail)
        }
    }
}

// MARK: - Processing card (reference style)

/// The Recent card a menu wears while it is still being read: the photo
/// where the thumbnail will be, "Reading your menu…" where the title goes,
/// and a small ring filling in on the right. Same geometry as `MediaCard`,
/// so the finished card takes its place without the list shifting.
struct ProcessingCard: View {
    let image: UIImage?
    let progress: Double
    let message: String

    @State private var preview: UIImage?

    private static var photoSide: CGFloat { 96 }
    private static var ringSide: CGFloat { 36 }

    private var fraction: Double { min(max(progress, 0), 1) }
    private var percent: Int { Int((fraction * 100).rounded()) }

    var body: some View {
        HStack(spacing: 0) {
            Theme.track
                .frame(width: Self.photoSide, height: Self.photoSide)
                .overlay {
                    if let shown = preview ?? image {
                        Image(uiImage: shown).resizable().scaledToFill()
                    } else {
                        Image(systemName: "doc.text.image")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }
                .clipShape(.rect(cornerRadius: Theme.Radius.chip, style: .continuous))
                .padding([.top, .leading, .bottom], Theme.Space.sm)

            HStack(spacing: Theme.Space.s) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    // Two lines at the largest text sizes; beside the ring
                    // one line cut it to "Reading your men…".
                    Text("Reading your menu…")
                        .scaledFont(size: 16, weight: .semibold, relativeTo: .callout)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(message)
                        .scaledFont(size: 13, weight: .regular, relativeTo: .footnote)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                        .animation(Theme.gentle, value: message)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ring
            }
            .padding(Theme.Space.sm)
        }
        .frame(minHeight: Self.photoSide + Theme.Space.sm * 2)
        .fixedSize(horizontal: false, vertical: true)
        .card(padding: 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reading your menu, \(percent) percent")
        .accessibilityValue(message)
        .task(id: image) {
            // A camera frame is far larger than 96pt; decode it once at the
            // size it is drawn rather than on every layout pass.
            guard let image, image.size.width > 0, image.size.height > 0 else { preview = nil; return }
            let side = Self.photoSide * 3
            let scale = min(1, max(side / image.size.width, side / image.size.height))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            preview = await image.byPreparingThumbnail(ofSize: size)
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Theme.track, lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(fraction, 0.02))
                .stroke(Theme.ink, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            CountingNumber(value: fraction * 100)
                .font(Theme.number(11))
                .foregroundStyle(Theme.ink)
        }
        .frame(width: Self.ringSide, height: Self.ringSide)
        .animation(Theme.gentle, value: progress)
    }
}
