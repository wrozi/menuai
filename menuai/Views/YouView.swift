//
//  YouView.swift
//  menuai
//
//  Everything about the person, on one screen, editable in place. The same
//  controls as onboarding in the same order, so nothing has to be relearned,
//  and every change saves as it is made. The key field for development
//  builds sits at the bottom and is compiled out of release.
//

import SwiftUI

struct YouView: View {
    @Environment(AppStore.self) private var store

    @State private var customAllergy = ""
    @State private var dislikeInput = ""
    @State private var editing: OrderedDish?
    #if DEBUG
    @State private var showAdvanced = false
    #endif

    var body: some View {
        @Bindable var store = store

        ScrollViewReader { proxy in
            ScrollView {
                // Allergies first: the one thing a person opens this screen
                // to check.
                VStack(spacing: Theme.Space.l) {
                    section("Allergies") {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            ChipGrid(
                                options: CommonAllergen.options(including: store.preferences.allergies),
                                selected: Set(store.preferences.allergies)
                            ) { $store.preferences.allergies.toggle($0) }

                            AddField(placeholder: "Something else", text: $customAllergy) {
                                $store.preferences.allergies.add(from: $customAllergy)
                            }

                            // Their own words, for what a chip can't say
                            // ("no raw fish"). It becomes a hard rule.
                            notesField

                            footnote("Always confirm with staff for anything serious.")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }

                    section("How you eat") {
                        VStack(spacing: Theme.Space.m) {
                            ForEach(Diet.allCases) { diet in
                                SelectableRow(
                                    title: diet.label,
                                    isSelected: store.preferences.diet == diet
                                ) { store.preferences.diet = diet }
                            }
                        }
                    }

                    section("What you're going for") {
                        ChoiceList(options: EatingGoal.choices, selection: $store.preferences.goal.index)
                        GoalNoteField(text: $store.preferences.goalNote)
                    }

                    section("Heat") {
                        ChoiceList(options: Choices.spice, selection: $store.preferences.spiceTolerance)
                    }

                    section("Adventure") {
                        ChoiceList(options: Choices.adventure, selection: $store.preferences.adventurousness)
                    }

                    section("Food you love") {
                        ChipGrid(
                            options: cuisineOptions,
                            selected: Set(store.preferences.lovedCuisines)
                        ) { $store.preferences.lovedCuisines.toggle($0) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }

                    section("Rather avoid") {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            if !store.preferences.dislikes.isEmpty {
                                ChipGrid(
                                    options: store.preferences.dislikes,
                                    selected: Set(store.preferences.dislikes)
                                ) { $store.preferences.dislikes.toggle($0) }
                            }
                            AddField(placeholder: "e.g. coriander", text: $dislikeInput) {
                                $store.preferences.dislikes.add(from: $dislikeInput)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }

                    section("Language") {
                        LanguageRow(selection: $store.preferences.displayLanguage)
                    }

                    section("Who you eat with") {
                        companionsCard
                    }

                    section("What you've eaten") {
                        eaten
                    }
                    .id("eaten")

                    #if DEBUG
                    advanced.id("advanced")
                    #endif
                }
                .padding(.horizontal, Theme.Space.m)
                .padding(.top, Theme.Space.s)
                .padding(.bottom, Theme.Space.xl)
            }
            .background(Theme.bg)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("You")
            .navigationBarTitleDisplayMode(.inline)
            .circleBackButton()
            .sheet(item: $editing) { OrderNoteSheet(order: $0) }
            .onDisappear {
                // Something typed but never added still counts.
                $store.preferences.allergies.add(from: $customAllergy)
                $store.preferences.dislikes.add(from: $dislikeInput)
            }
            #if DEBUG
            .task {
                // The screenshot harness lands on a section further down.
                guard let target = SelfTest.requestedScroll else { return }
                try? await Task.sleep(for: .milliseconds(500))
                switch target {
                case "eaten": proxy.scrollTo("eaten", anchor: .top)
                case "advanced": proxy.scrollTo("advanced", anchor: .bottom)
                default: break
                }
            }
            #endif
        }
    }

    // MARK: - Sections

    /// A ground header at the same inset as every other screen, then the
    /// controls, in one 10pt rhythm. The same 28pt of air above each header
    /// as Home and the results screen give theirs.
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            GroundHeader(title)
            content()
        }
        .padding(.top, Theme.Space.xs)
    }

    /// One line, dressed like the goal note field, so the two free-text
    /// inputs on this screen read as the same kind of thing.
    private var notesField: some View {
        @Bindable var store = store

        return TextField("Anything else you can't eat", text: $store.preferences.notes)
            .font(Theme.body)
            .submitLabel(.done)
            .padding(.horizontal, Theme.Space.m)
            .frame(minHeight: 56)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.inner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            }
    }

    private func footnote(_ text: String) -> some View {
        // 13pt secondary, not micro tertiary: the one safety line has to
        // clear the contrast floor.
        Text(text)
            .font(Theme.caption)
            .foregroundStyle(Theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Companions

    private var companionsCard: some View {
        NavigationLink(value: AppRoute.companions) {
            HStack(spacing: Theme.Space.s) {
                if store.diners.isEmpty {
                    ZStack {
                        Circle().fill(Theme.surfaceSunken).frame(width: 40, height: 40)
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .accessibilityHidden(true)
                } else {
                    // The same 40pt as the empty state's circle, so the row
                    // keeps its height whichever it shows.
                    HStack(spacing: -10) {
                        ForEach(store.diners.prefix(4)) { diner in
                            ZStack {
                                Circle().fill(diner.color).frame(width: 40, height: 40)
                                Circle().strokeBorder(Theme.surface, lineWidth: 2).frame(width: 40, height: 40)
                                Text(diner.initial)
                                    .font(Theme.number(15))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .accessibilityHidden(true)
                }

                Text(store.diners.isEmpty
                    ? "Nobody yet"
                    : store.diners.map(\.name).joined(separator: ", "))
                    .font(Theme.headline)
                    .foregroundStyle(store.diners.isEmpty ? Theme.inkSecondary : Theme.ink)
                    .lineLimit(2)

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
                    .accessibilityHidden(true)
            }
            .card()
        }
        .buttonStyle(.press(scale: 0.985))
        .simultaneousGesture(TapGesture().onEnded { Haptic.tap() })
        .accessibilityLabel(store.diners.isEmpty
            ? "Nobody yet"
            : "Eating with " + store.diners.map(\.name).joined(separator: ", "))
        .accessibilityHint(store.diners.isEmpty ? "Add the people you eat with" : "Edit who you eat with")
    }

    // MARK: - Eaten

    /// The last twenty orders, newest first. Rate from the row; tap for
    /// the note.
    @ViewBuilder private var eaten: some View {
        if store.orders.isEmpty {
            Text("Rate it. Every menu gets smarter.")
                .font(Theme.callout)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Space.m)
                .frame(maxWidth: .infinity, minHeight: 88)
                .card(padding: 0)
        } else {
            VStack(spacing: Theme.Space.sm) {
                ForEach(store.orders.prefix(20)) { order in
                    OrderRow(order: order) {
                        editing = order
                    } onRate: { stars in
                        store.rate(order, stars: stars)
                    }
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            withAnimation(Theme.gentle) { store.delete(order) }
                        }
                    }
                }
            }
            .animation(Theme.gentle, value: store.orders.count)
        }
    }

    #if DEBUG
    // MARK: - Advanced

    /// Development builds only. The key field is here for working against
    /// the Claude engine; release builds read every menu on the iPhone and
    /// never show this row.
    private var advanced: some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Button {
                Haptic.tap()
                withAnimation(Theme.snap) { showAdvanced.toggle() }
            } label: {
                HStack {
                    Text("Advanced")
                        .font(Theme.callout)
                        .foregroundStyle(Theme.inkSecondary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkTertiary)
                        .rotationEffect(.degrees(showAdvanced ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 56)
                .contentShape(.rect)
            }
            .buttonStyle(.press)
            .accessibilityValue(showAdvanced ? "Expanded" : "Collapsed")

            if showAdvanced {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    if store.hasAPIKey {
                        Text("Photos go to Anthropic, billed to you.")
                            .font(Theme.micro)
                            .foregroundStyle(Theme.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SecureField("Anthropic API key", text: $store.apiKey)
                        .font(Theme.callout)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(.horizontal, Theme.Space.sm)
                        .frame(height: 44)
                        .background(Theme.surfaceSunken, in: .capsule)
                }
                .padding(.bottom, Theme.Space.sm)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.m)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.row, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        }
    }
    #endif
}
