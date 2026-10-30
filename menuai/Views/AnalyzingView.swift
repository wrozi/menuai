//
//  AnalyzingView.swift
//  menuai
//
//  Shown over the whole screen while a menu is being read. It displays the
//  photo you just took with a scan line sweeping it, so the wait reads as the
//  app working on *your* menu rather than a generic spinner.
//

import SwiftUI

struct AnalyzingView: View {
    let image: UIImage?
    let progress: Double
    let message: String

    @State private var sweep: CGFloat = 0
    @State private var appeared = false
    @State private var preview: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: Theme.Space.xl) {
                Spacer()

                photo

                VStack(spacing: Theme.Space.m) {
                    Text(message)
                        .font(Theme.headline)
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.opacity)
                        .animation(Theme.gentle, value: message)

                    track
                }
                .padding(.horizontal, Theme.Space.xl)

                Spacer()
                Spacer()
            }
        }
        .onAppear {
            appeared = true
            AccessibilityNotification.Announcement(message).post()
            if !reduceMotion {
                withAnimation(.linear(duration: 1.7).repeatForever(autoreverses: false)) {
                    sweep = 1
                }
            }
        }
        .task(id: image) {
            guard let image, image.size.width > 0, image.size.height > 0 else { preview = nil; return }
            // Fill 220x290pt at 3x without stretching: preparingThumbnail ignores aspect ratio.
            let scale = min(1, max(660 / image.size.width, 870 / image.size.height))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            preview = await image.byPreparingThumbnail(ofSize: size)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onChange(of: message) { _, new in AccessibilityNotification.Announcement(new).post() }
    }

    private var photo: some View {
        ZStack {
            if let shown = preview ?? image {
                Image(uiImage: shown)
                    .resizable()
                    .scaledToFill()
            } else {
                Theme.surfaceSunken
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .frame(width: 220, height: 290)
        .clipShape(.rect(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            if !reduceMotion {
                scanLine.clipShape(.rect(cornerRadius: Theme.Radius.card, style: .continuous))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        }
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.surface)
                .cardShadow()
        }
        .scaleEffect(appeared ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
        .animation(Theme.gentle, value: appeared)
        .accessibilityHidden(true)
    }

    /// A soft band travelling top to bottom, brightest at its centre.
    private var scanLine: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [
                    .clear,
                    Color.white.opacity(0.05),
                    Color.white.opacity(0.55),
                    Color.white.opacity(0.05),
                    .clear,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 90)
            .blur(radius: 5)
            .offset(y: -90 + sweep * (geo.size.height + 90))
        }
        .allowsHitTesting(false)
    }

    private var track: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: max(8, geo.size.width * min(max(progress, 0), 1)))
                    .animation(Theme.gentle, value: progress)
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((min(max(progress, 0), 1) * 100).rounded())) percent")
    }
}
