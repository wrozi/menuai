//
//  FormControls.swift
//  menuai
//
//  Inputs shared by onboarding, You and the companion editor, so the three
//  can't drift.
//

import SwiftUI

struct ChipGrid: View {
    let options: [String]
    let selected: Set<String>
    let onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options, id: \.self) { option in
                ToggleChip(text: option, isOn: selected.contains(option)) {
                    onTap(option)
                }
            }
        }
    }
}

// MARK: - Option row

/// The one answer row every single-choice question uses. Matched to the
/// reference: a tall pill-cornered card that turns black when chosen, with a
/// white disc holding the glyph — no checkmark, no border, no shadow. The
/// fill is the whole signal. With no icon the title sits centred, the way
/// the reference lays out its short two- and three-way choices.
struct OptionRow: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    init(title: String, subtitle: String? = nil, icon: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.isSelected = isSelected
        self.action = action
    }

    private var minHeight: CGFloat { subtitle == nil ? 72 : 88 }

    var body: some View {
        Button {
            // A tap on the chosen row changes nothing; the press scale
            // already acknowledges it.
            guard !isSelected else { return }
            Haptic.select()
            withAnimation(Theme.snap) { action() }
        } label: {
            HStack(spacing: Theme.Space.m) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isSelected ? Theme.accent : Theme.ink)
                        .frame(width: 44, height: 44)
                        .background(isSelected ? Theme.onAccent : Theme.surfaceSunken, in: .circle)
                        .accessibilityHidden(true)
                }

                VStack(alignment: icon == nil ? .center : .leading, spacing: 2) {
                    Text(title)
                        .scaledFont(size: 17, weight: .semibold, relativeTo: .headline)
                        .foregroundStyle(isSelected ? Theme.onAccent : Theme.ink)
                    if let subtitle {
                        Text(subtitle)
                            .scaledFont(size: 13, relativeTo: .footnote)
                            .foregroundStyle(isSelected ? Theme.onAccent.opacity(0.75) : Theme.inkSecondary)
                    }
                }
                .multilineTextAlignment(icon == nil ? .center : .leading)
                .frame(maxWidth: .infinity, alignment: icon == nil ? .center : .leading)
            }
            .padding(.horizontal, Theme.Space.m)
            // Room to grow at the largest text sizes, so a two-line row
            // never clips its second line.
            .padding(.vertical, Theme.Space.sm)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(
                isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surface),
                in: .rect(cornerRadius: Theme.Radius.inner, style: .continuous)
            )
        }
        .buttonStyle(.press(scale: 0.96))
        .accessibilityAddTraits(isSelected ? AccessibilityTraits([.isButton, .isSelected]) : AccessibilityTraits.isButton)
    }
}

/// Big tappable option row used for single-choice questions. Pass no icon
/// for a text-only row with the title centred — the diet list is drawn that
/// way in onboarding, on You and in the companion editor alike.
struct SelectableRow: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        OptionRow(title: title, icon: icon, isSelected: isSelected, action: action)
    }
}

/// Text field plus Add button, for allergies and dislikes.
struct AddField: View {
    let placeholder: String
    @Binding var text: String
    let onAdd: () -> Void

    private var canAdd: Bool { !text.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            TextField(placeholder, text: $text)
                .font(Theme.callout)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .padding(.horizontal, Theme.Space.sm)
                .frame(height: 44)
                .background(Theme.surfaceSunken, in: .capsule)
                .onSubmit(onAdd)

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 44, height: 44)
                    .background(Theme.accent, in: .circle)
            }
            .buttonStyle(.press)
            .accessibilityLabel("Add")
            .disabled(!canAdd)
            .opacity(canAdd ? 1 : 0.35)
            .animation(Theme.snap, value: canAdd)
        }
    }
}

/// A 0…n scale as tappable rows. A slider makes you aim; rows show every
/// option at once. Each option is (title, subtitle, icon).
struct ChoiceList: View {
    let options: [(String, String, String)]
    @Binding var selection: Int

    var body: some View {
        VStack(spacing: Theme.Space.m) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                OptionRow(title: option.0, subtitle: option.1, icon: option.2, isSelected: selection == index) {
                    selection = index
                }
            }
        }
    }
}

/// The one line under the goal rows for their own words. Dressed as an
/// unselected row so it reads as part of the list, on the ground or in a
/// sheet alike.
struct GoalNoteField: View {
    @Binding var text: String

    var body: some View {
        TextField("Anything else? e.g. low carb", text: $text)
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
}

/// The language picker in an unselected row's clothes, so the one system
/// control lines up with the rows around it.
struct LanguageRow: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 26)
                .accessibilityHidden(true)
            Picker("Language", selection: $selection) {
                ForEach(supportedLanguages, id: \.code) { Text($0.name).tag($0.code) }
            }
            .pickerStyle(.menu)
            .tint(Theme.ink)
            .font(Theme.headline)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.inner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        }
    }
}

// MARK: - Binding helpers

extension Binding where Value == [String] {
    /// Adds the value if it is missing, removes it if it is there.
    func toggle(_ value: String) {
        if let index = wrappedValue.firstIndex(of: value) {
            wrappedValue.remove(at: index)
        } else {
            wrappedValue.append(value)
        }
    }

    /// Adds what was typed, one entry per comma, skipping blanks and
    /// repeats, and clears the field.
    func add(from field: Binding<String>) {
        var values: [String] = []
        for part in field.wrappedValue.split(separator: ",") {
            let value = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty, !wrappedValue.contains(value), !values.contains(value) {
                values.append(value)
            }
        }
        guard !values.isEmpty else { return }
        Haptic.tap()
        withAnimation(Theme.snap) {
            wrappedValue.append(contentsOf: values)
            field.wrappedValue = ""
        }
    }
}

extension Binding where Value == EatingGoal {
    /// `ChoiceList` takes a row index; the goal is an enum. Bridged through
    /// `allCases` so the rows and the stored value can't disagree.
    var index: Binding<Int> {
        Binding<Int>(
            get: { EatingGoal.allCases.firstIndex(of: wrappedValue) ?? 0 },
            set: { index in
                let cases = EatingGoal.allCases
                wrappedValue = cases[Swift.min(Swift.max(index, 0), cases.count - 1)]
            }
        )
    }
}

extension View {
    /// Done above the keyboard for multi-line fields, which otherwise have no
    /// way to give it up.
    func keyboardDone() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .font(Theme.headline)
            }
        }
    }
}

/// The wording for the two scale questions, shared so onboarding, You and
/// the companion editor can never drift apart.
enum Choices {
    static let spice: [(String, String, String)] = [
        ("None", "Keep it mild", "drop"),
        ("A little", "Some warmth", "flame"),
        ("Hot", "Bring it", "flame.fill"),
        ("As hot as it gets", "The spiciest thing there is", "flame.circle.fill"),
    ]

    static let adventure: [(String, String, String)] = [
        ("Keep it familiar", "Things I already know", "house"),
        ("Mostly familiar", "One surprise is fine", "signpost.right"),
        ("Happy to explore", "Show me what's local", "binoculars"),
        ("Surprise me", "The stranger the better", "sparkles"),
    ]

    static let labels = (
        spice: ["None", "A little", "Hot", "As hot as it gets"],
        adventure: ["Familiar", "Mostly familiar", "Explorer", "Surprise me"]
    )
}
