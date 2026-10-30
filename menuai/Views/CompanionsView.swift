//
//  CompanionsView.swift
//  menuai
//
//  The people you eat with. Kept deliberately shallow — a name and the two
//  things that actually change a recommendation (what they can't have, and
//  how much heat they take). Anything more and nobody fills it in.
//
//  Pushed onto the root stack as `AppRoute.companions` — from You's "Who you
//  eat with" card and from the Menu screen's Edit chip — so it owns no
//  navigation container of its own; back returns to whichever sent it.
//

import SwiftUI

struct CompanionsView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: Diner?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.m) {
                if store.diners.isEmpty {
                    Text("Every menu gets ranked for them too.")
                        .font(Theme.callout)
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.Space.m)
                        .frame(maxWidth: .infinity, minHeight: 88)
                        .card(padding: 0)
                } else {
                    VStack(spacing: Theme.Space.s) {
                        ForEach(store.diners) { diner in
                            Button {
                                Haptic.tap()
                                editing = diner
                            } label: {
                                CompanionRow(diner: diner)
                            }
                            .buttonStyle(.press(scale: 0.985))
                        }
                    }
                }

                PillButton(title: "Add someone", icon: "plus") {
                    editing = Diner(
                        name: "",
                        colorIndex: (0 ..< Diner.palette.count).first { index in
                            !store.diners.contains { abs($0.colorIndex) % Diner.palette.count == index }
                        } ?? store.diners.count,
                        allergies: [],
                        dislikes: []
                    )
                }
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.bottom, Theme.Space.xl)
            .animation(Theme.gentle, value: store.diners.count)
        }
        .background(Theme.bg)
        .scrollIndicators(.hidden)
        .navigationTitle("Who you eat with")
        .navigationBarTitleDisplayMode(.inline)
        .circleBackButton()
        .sheet(item: $editing) { CompanionEditor(diner: $0) }
    }
}

private struct CompanionRow: View {
    let diner: Diner

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            ZStack {
                Circle().fill(diner.color).frame(width: 44, height: 44)
                Text(diner.initial)
                    .font(Theme.number(18))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(diner.name).font(Theme.headline).foregroundStyle(Theme.ink)
                // Their allergies are summarised here and nowhere else, so
                // it is not the least legible text on the screen.
                Text(diner.summary)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
                .accessibilityHidden(true)
        }
        .card(padding: Theme.Space.sm)
        .accessibilityElement(children: .combine)
    }
}

private struct CompanionEditor: View {
    @State var diner: Diner
    private let original: Diner
    @State private var saved = false

    init(diner: Diner) {
        _diner = State(initialValue: diner)
        original = diner
    }

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var customAllergy = ""
    @State private var dislikeInput = ""
    @FocusState private var nameFocused: Bool
    @State private var confirmRemove = false

    private var isNew: Bool {
        !store.diners.contains { $0.id == diner.id }
    }

    private var removeName: String { diner.name.isEmpty ? "this person" : diner.name }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.l) {
                    section("Name") {
                        TextField("e.g. Maya", text: $diner.name)
                            .font(Theme.body)
                            .focused($nameFocused)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit { nameFocused = false }
                            .padding(.horizontal, Theme.Space.sm)
                            .frame(height: 44)
                            .background(Theme.surfaceSunken, in: .capsule)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()
                    }

                    section("How they eat") {
                        VStack(spacing: Theme.Space.m) {
                            ForEach(Diet.allCases) { diet in
                                SelectableRow(
                                    title: diet.label,
                                    isSelected: diner.diet == diet
                                ) { diner.diet = diet }
                            }
                        }
                    }

                    section("Allergies") {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            ChipGrid(
                                options: CommonAllergen.options(including: diner.allergies),
                                selected: Set(diner.allergies)
                            ) { $diner.allergies.toggle($0) }

                            AddField(placeholder: "Something else", text: $customAllergy) {
                                $diner.allergies.add(from: $customAllergy)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }

                    section("Heat") {
                        ChoiceList(options: Choices.spice, selection: $diner.spiceTolerance)
                    }

                    section("Rather avoid") {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            if !diner.dislikes.isEmpty {
                                ChipGrid(
                                    options: diner.dislikes,
                                    selected: Set(diner.dislikes)
                                ) { $diner.dislikes.toggle($0) }
                            }
                            AddField(placeholder: "e.g. coriander", text: $dislikeInput) {
                                $diner.dislikes.add(from: $dislikeInput)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }

                    if !isNew {
                        Button(role: .destructive) {
                            confirmRemove = true
                        } label: {
                            Text("Remove \(removeName)")
                                .font(Theme.callout)
                                .foregroundStyle(Theme.danger)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.press)
                        .padding(.top, Theme.Space.xs)
                    }
                }
                .padding(.horizontal, Theme.Space.m)
                .padding(.bottom, Theme.Space.xl)
            }
            .background(Theme.bg)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .keyboardDone()
            .navigationTitle(isNew ? "Add someone" : diner.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        guard !saved else { return }
                        saved = true
                        $diner.allergies.add(from: $customAllergy)
                        $diner.dislikes.add(from: $dislikeInput)
                        if isNew { store.addDiner(diner) } else { store.updateDiner(diner) }
                        dismiss()
                    }
                    .font(Theme.headline)
                    .disabled(diner.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .interactiveDismissDisabled(diner != original)
        .task { if isNew { nameFocused = true } }
        .confirmationDialog("Remove \(removeName)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                store.removeDiner(diner)
                dismiss()
            }
        }
    }

    /// A ground header, then the controls, in one 10pt rhythm — the shape
    /// You gives every section, so the two editors match.
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            GroundHeader(title)
            content()
        }
        .padding(.top, Theme.Space.xs)
    }
}
