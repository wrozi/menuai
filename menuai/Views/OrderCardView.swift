//
//  OrderCardView.swift
//  menuai
//
//  The dish name, printed large in the language the waiter reads, and the
//  one thing they must know about you, in their language too.
//
//  This is the moment the whole app exists for: you have decided, and now you
//  have to say a word you cannot pronounce to someone in a hurry. Holding up
//  a phone solves it in one second. The screen brightens on open, because
//  restaurants are dark and the whole point is that somebody else can read it.
//
//  Without a dish it is the allergy card alone, for when the waiter arrives
//  before anything has been chosen.
//

import SwiftUI
import UIKit

struct OrderCardView: View {
    /// nil shows only what the waiter must know, before anything is chosen.
    let dish: Dish?
    /// Decides the language the card speaks.
    let menu: ParsedMenu
    /// Named on the card so the kitchen hears about them too.
    let allergies: [String]
    let diet: Diet

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var previousBrightness: CGFloat?
    @State private var screen: UIScreen?

    /// `UIScreen.main` is deprecated in iOS 26; the screen has to come from
    /// the scene the app is actually showing in.
    private static var activeScreen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .screen
    }

    private var language: String { Phrasebook.language(for: menu) }

    private var waiterLine: (local: String, english: String)? {
        Phrasebook.waiterLine(allergens: allergies, diet: diet, language: language)
    }

    /// Text in the waiter's language, tagged so VoiceOver reads it in that
    /// language rather than in the user's voice.
    private func local(_ text: String) -> AttributedString {
        var string = AttributedString(text)
        string.languageIdentifier = language
        return string
    }

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()

            VStack(spacing: Theme.Space.l) {
                Spacer()

                if let dish {
                    VStack(spacing: Theme.Space.m) {
                        Text(local(Phrasebook.orderLine(language: language)))
                            .scaledFont(size: 15, weight: .medium, relativeTo: .subheadline)
                            .foregroundStyle(Theme.inkSecondary)

                        Text(local(dish.originalName.isEmpty ? dish.displayName : dish.originalName))
                            .font(Theme.number(42))
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.4)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, Theme.Space.m)

                        if let translated = dish.subtitleName == nil ? nil : dish.displayName {
                            Text(translated)
                                .scaledFont(size: 15, relativeTo: .subheadline)
                                .foregroundStyle(Theme.inkTertiary)
                        }
                    }
                }

                if let waiterLine {
                    // The safety line is the loudest thing after the name.
                    // Each statement (allergies, then diet) gets its own
                    // line, centred so a right-to-left sentence sits the
                    // same as any other.
                    VStack(spacing: Theme.Space.s) {
                        VStack(spacing: Theme.Space.s) {
                            ForEach(Array(waiterLine.local.split(separator: "\n").enumerated()), id: \.offset) { _, line in
                                Text(local(String(line)))
                                    .scaledFont(size: 26, weight: .semibold, relativeTo: .title)
                                    .foregroundStyle(Theme.ink)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        // So you know what the card is saying for you.
                        if waiterLine.english != waiterLine.local {
                            VStack(spacing: Theme.Space.xs) {
                                ForEach(Array(waiterLine.english.split(separator: "\n").enumerated()), id: \.offset) { _, line in
                                    Text(String(line))
                                        .scaledFont(size: 13, relativeTo: .footnote)
                                        .foregroundStyle(Theme.inkTertiary)
                                        .multilineTextAlignment(.center)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.top, Theme.Space.xs)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .card()
                    .overlay {
                        // A warning at arm's length, not a hint.
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .strokeBorder(allergies.isEmpty ? Theme.hairline : Theme.danger, lineWidth: allergies.isEmpty ? 1 : 2)
                            .allowsHitTesting(false)
                    }
                    .padding(.horizontal, Theme.Space.l)
                }

                Spacer()

                PillButton(title: "Done") { dismiss() }
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.bottom, Theme.Space.m)
            }
        }
        .environment(\.colorScheme, .light)
        .statusBarHidden()
        .onAppear {
            guard let s = Self.activeScreen else { return }
            screen = s
            previousBrightness = s.brightness
            s.brightness = 1
        }
        .onDisappear {
            guard let screen, let previousBrightness else { return }
            screen.brightness = previousBrightness
        }
        .onChange(of: scenePhase) { _, phase in
            guard let screen else { return }
            if phase == .active {
                previousBrightness = previousBrightness ?? screen.brightness
                screen.brightness = 1
            } else if let previousBrightness {
                screen.brightness = previousBrightness
            }
        }
    }
}
