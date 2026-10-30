//
//  DishDetailView.swift
//  menuai
//

import SwiftUI

struct DishDetailView: View {
    let dish: Dish
    let menu: ParsedMenu
    /// Whose ranking this is being viewed under. nil = the account holder.
    var diner: Diner?

    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showPhotos = false
    @State private var showOrderCard = false
    @State private var appeared = false
    @State private var noteDraft = ""
    @State private var confirmRemove = false
    @FocusState private var noteFocused: Bool
    @State private var keyboardInset: CGFloat = 0

    private var order: OrderedDish? { store.order(for: dish) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    nameBlock.riseIn(0, isActive: appeared)

                    // Safety first: anything that blocks the dish sits above
                    // every figure about it.
                    if !dish.warnings.isEmpty {
                        warningsBlock.riseIn(1, isActive: appeared)
                    }

                    if let previous = store.previousOrder(of: dish, excluding: order?.id) {
                        previousOrderBlock(previous).riseIn(2, isActive: appeared)
                    }

                    // One grid: the same 12pt gutter down as across.
                    VStack(spacing: Theme.Space.sm) {
                        matchTile.riseIn(3, isActive: appeared)

                        // Only for someone with a goal: with none set, a
                        // health figure is tracking furniture. Filled by the
                        // scorer, so menus saved before it existed go without.
                        if let health = dish.healthScore, store.preferences.goal != .none {
                            healthTile(health).riseIn(4, isActive: appeared)
                        }

                        factTiles.riseIn(5, isActive: appeared)

                        // Rating is the account holder's own record. Companions are
                        // there to be catered for, not to keep a diary on this phone.
                        if diner == nil {
                            orderBlock.riseIn(6, isActive: appeared)
                        }
                    }

                    if !dish.description.isEmpty {
                        DetailSection(title: "What it is") {
                            Text(dish.description)
                                .font(Theme.body)
                                .foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .riseIn(7, isActive: appeared)
                    }

                    if !dish.ingredients.isEmpty {
                        DetailSection(title: "Ingredients") {
                            FlowLayout(spacing: 6) {
                                ForEach(dish.ingredients, id: \.self) { Chip(text: $0) }
                            }
                        }
                        .riseIn(8, isActive: appeared)
                    }

                    if !dish.dietaryTags.isEmpty {
                        DetailSection(title: "Good to know") {
                            FlowLayout(spacing: 6) {
                                ForEach(dish.dietaryTags, id: \.self) {
                                    Chip(text: $0, tint: Theme.good)
                                }
                            }
                        }
                        .riseIn(9, isActive: appeared)
                    }
                }
                .padding(.horizontal, Theme.Space.m)
                .padding(.bottom, Theme.Space.xl)
            }
            // A white page, as on the reference: the tiles are told apart by
            // their hairline alone, and the grey pill and icon wells show.
            .background(Theme.surface)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .keyboardDone()
            .safeAreaPadding(.bottom, keyboardInset)
            .background {
                // The inset is the keyboard's overlap with this scroll view, not its
                // whole height — the pinned bar and home indicator are already
                // under it. The bar is attached below this reader, so the safe
                // area measured here ends at the bar's top edge.
                GeometryReader { geo in
                    Color.clear
                        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                            guard let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
                            let window = UIApplication.shared.connectedScenes
                                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                                .first
                            let keyboardTop = window.map { $0.coordinateSpace.convert(end, from: $0.screen.coordinateSpace).minY } ?? end.minY
                            let visibleBottom = geo.frame(in: .global).maxY - geo.safeAreaInsets.bottom
                            keyboardInset = max(0, visibleBottom - keyboardTop)
                        }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // The waiter card is the reason to be here; a web photo of
                // the dish is the nicety.
                BottomActionBar(
                    secondary: .init(title: "See photos", icon: "photo.on.rectangle.angled") {
                        showPhotos = true
                    },
                    primary: .init(title: "Show the waiter", icon: "hand.raised.fill") {
                        showOrderCard = true
                    }
                )
            }
            .onChange(of: keyboardInset) { _, inset in
                guard inset > 0, noteFocused else { return }
                withAnimation(Theme.gentle) { proxy.scrollTo("note", anchor: .center) }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .circleBackButton(ground: Theme.surface)
            .sheet(isPresented: $showPhotos) { PhotoBrowserView(dish: dish) }
            .fullScreenCover(isPresented: $showOrderCard) {
                OrderCardView(
                    dish: dish,
                    menu: menu,
                    allergies: diner?.allergies ?? store.preferences.allergies,
                    diet: diner?.diet ?? store.preferences.diet
                )
            }
            .confirmationDialog("Remove your rating and note?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    withAnimation(Theme.snap) {
                        store.toggleOrdered(dish, from: menu)
                        noteDraft = ""
                    }
                }
            }
            .task {
                appeared = true
                noteDraft = order?.note ?? ""
                #if DEBUG
                if SelfTest.presentsOrderCard {
                    try? await Task.sleep(for: .milliseconds(500))
                    showOrderCard = true
                }
                #endif
            }
            .onDisappear {
                if let order, noteDraft != order.note { store.setNote(noteDraft, for: order) }
            }
        }
    }

    // MARK: - Name

    /// Headings that say nothing a diner doesn't know already.
    private static let genericSections: Set<String> = ["menu", "menù", "carta", "la carte", "speisekarte"]

    /// The menu heading this dish was printed under. Dishes scored for a
    /// companion are copies, so fall back to matching by name. Empty when the
    /// heading would only repeat the place's name or the word "menu".
    private var sectionLabel: String {
        let section = menu.sections.first { section in
            section.dishes.contains { $0.id == dish.id }
        } ?? menu.sections.first { section in
            section.dishes.contains {
                $0.originalName == dish.originalName && $0.translatedName == dish.translatedName
            }
        }
        let name = (section.map { $0.name.isEmpty ? $0.originalName : $0.name } ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty
            || Self.genericSections.contains(name.lowercased())
            || name.caseInsensitiveCompare(menu.title) == .orderedSame {
            return ""
        }
        return name
    }

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if !sectionLabel.isEmpty {
                Text(sectionLabel)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }

            // Beside the title until the text is too large for both to fit.
            let row = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.s))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Theme.Space.sm))
            row {
                Text(dish.displayName)
                    .scaledFont(size: 26, weight: .bold, relativeTo: .title)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)

                if !dish.price.isEmpty {
                    Text(dish.price)
                        .scaledFont(size: 17, weight: .semibold, relativeTo: .headline)
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }

            if let original = dish.subtitleName {
                Text(original)
                    .scaledFont(size: 19, weight: .regular, relativeTo: .title3)
                    .foregroundStyle(Theme.inkSecondary)
            }

            if !dish.pronunciation.isEmpty {
                Label("\u{201C}\(dish.pronunciation)\u{201D}", systemImage: "quote.bubble")
                    .font(Theme.callout)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Space.s)
    }

    /// The moment the memory earns its keep: you are looking at a dish you
    /// have eaten before and had forgotten you had an opinion about.
    private func previousOrderBlock(_ order: OrderedDish) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.star)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text("You've had this before")
                    .font(Theme.headline)
                    .foregroundStyle(Theme.ink)

                HStack(spacing: 8) {
                    if order.isRated { StarRating(rating: order.rating, size: 14) }
                    Text(order.restaurant.isEmpty
                        ? order.orderedAt.formatted(.dateTime.month().year())
                        : "\(order.restaurant), \(order.orderedAt.formatted(.dateTime.month().year()))")
                        .font(Theme.micro)
                        .foregroundStyle(Theme.inkTertiary)
                }

                if !order.note.isEmpty {
                    Text("\u{201C}\(order.note)\u{201D}")
                        .font(Theme.callout)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .tile()
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .strokeBorder(Theme.star.opacity(0.35), lineWidth: 1.5)
        }
    }

    private var warningsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(dish.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.callout.weight(.medium))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tile()
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .strokeBorder(Theme.danger.opacity(0.35), lineWidth: 1.5)
        }
    }

    // MARK: - Match

    /// The reference's score tile: an icon in a light square, the label with
    /// its figure at the far right, and a thin bar underneath.
    private var matchTile: some View {
        let tint = Theme.scoreColor(dish.matchScore, blocked: dish.isBlocked)
        let score = min(max(dish.matchScore, 0), 100)

        return VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.sm) {
                // The thumbs-up from "Learns your taste": the heart belongs to
                // the health tile beneath, and two hearts in a row said nothing.
                Image(systemName: dish.isBlocked ? "xmark" : "hand.thumbsup.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 56, height: 56)
                    .background(Theme.surfaceSunken, in: .rect(cornerRadius: Self.iconWellRadius, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        Text(dish.isBlocked ? (diner.map { "Not for \($0.name)" } ?? "Not for you") : "Match")
                            .scaledFont(size: 17, weight: .medium, relativeTo: .headline)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if !dish.isBlocked {
                            Text("\(score)%")
                                .scaledFont(size: 17, weight: .semibold, relativeTo: .headline)
                                .foregroundStyle(Theme.ink)
                                .monospacedDigit()
                        }
                    }
                    MatchBar(progress: dish.isBlocked ? 0 : Double(score) / 100, tint: tint)
                }
            }

            // A blocked dish's reason is its first warning, already in coral
            // above; saying it twice adds nothing.
            if !dish.matchReason.isEmpty, !dish.warnings.contains(dish.matchReason) {
                Text(dish.matchReason)
                    .scaledFont(size: 15, relativeTo: .subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tile()
        .accessibilityElement(children: .combine)
    }

    /// The 56pt icon square's corner, as measured on the reference.
    private static let iconWellRadius: CGFloat = 14

    // MARK: - Health

    /// The reference's health-score tile, in the match tile's clothes: the
    /// heart in its light square, the figure out of ten, the bar beneath.
    private func healthTile(_ health: Int) -> some View {
        let score = min(max(health, 1), 10)
        let tint: Color = switch score {
        case 7...: Theme.great
        // Tan below 7, never coral: coral means "you can't eat this" here.
        default: Theme.okay
        }

        return HStack(spacing: Theme.Space.sm) {
            Image(systemName: "heart.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 56, height: 56)
                .background(Theme.surfaceSunken, in: .rect(cornerRadius: Self.iconWellRadius, style: .continuous))

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text("Health")
                        .scaledFont(size: 17, weight: .medium, relativeTo: .headline)
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                    Text("\(score)/10")
                        .scaledFont(size: 17, weight: .semibold, relativeTo: .headline)
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                }
                MatchBar(progress: Double(score) / 10, tint: tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tile()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Health, \(score) of 10")
    }

    // MARK: - Facts

    private var heat: String {
        switch dish.spiceLevel {
        case ...0: "None"
        case 1: "Mild"
        case 2: "Medium"
        default: "Hot"
        }
    }

    /// What to print on the tile: the word, not a count. Someone with a
    /// peanut allergy needs "Peanuts", and the flagged ones come first — a
    /// dish can be blocked on the printed line alone, with nothing in its
    /// own allergen list, so the warnings are never left out.
    private var allergenValue: String {
        let names = dish.warnings.isEmpty ? dish.allergens : dish.warnings.map(Self.subject)
        guard let first = names.first, !first.isEmpty else { return "Not listed" }
        let word = first.prefix(1).uppercased() + first.dropFirst()
        return names.count == 1 ? word : "\(word) +\(names.count - 1)"
    }

    /// The thing a warning is about: "Likely contains pistacchi — that's
    /// tree nuts, which you're allergic to." → "pistacchi".
    private nonisolated static func subject(of warning: String) -> String {
        var text = warning
        for prefix in ["Likely contains ", "Contains ", "Made with ", "Mixes "] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        let end = text.firstIndex { $0 == "," || $0 == "—" || $0 == "." } ?? text.endIndex
        return text[..<end].trimmingCharacters(in: .whitespaces)
    }

    private var factTiles: some View {
        let row = typeSize >= .xLarge
            ? AnyLayout(VStackLayout(spacing: Theme.Space.sm))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Space.sm))
        return row {
            // Tan, the flame's colour on the results rows, when there is
            // heat; grey when there is none, like the tile beside it. Never
            // coral: a red flame over "None" read as a spice warning on a
            // salad, and coral means "you can't eat this" on this page.
            FactTile(
                icon: "flame.fill",
                tint: dish.spiceLevel > 0 ? Theme.okay : Theme.inkTertiary,
                label: "Heat",
                value: heat,
                valueColor: dish.spiceLevel > 0 ? Theme.ink : Theme.inkSecondary
            )
            // Only for someone with a goal, like the health bar above. Menus
            // saved before the scorer sized dishes show a dash.
            if store.preferences.goal != .none {
                FactTile(
                    icon: "bolt.fill",
                    tint: Theme.good,
                    label: "Calories",
                    value: dish.calorieLabel ?? "\u{2014}",
                    spokenValue: dish.calorieLabel == nil ? "Not listed" : nil
                )
            }
            // Names what the dish contains, not what is flagged for this
            // diner — the red block at the top is the only thing that means
            // that. It goes amber only when one of those actually applies
            // to them. "Not listed" rather than a bare zero: a "0" beside a
            // hazard sign reads as a guarantee this check can't give.
            FactTile(
                icon: "exclamationmark.triangle.fill",
                tint: !dish.warnings.isEmpty ? Theme.okay : Theme.inkTertiary,
                label: "Allergens",
                value: allergenValue,
                valueColor: allergenValue == "Not listed" ? Theme.inkSecondary : Theme.ink
            )
        }
    }

    // MARK: - Order & rate
    //
    // The loop that makes the app get better: mark what you ordered, rate it,
    // and the next menu is scored partly on that.

    private var orderBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Button {
                if let order, order.isRated || !order.note.isEmpty || !noteDraft.isEmpty {
                    confirmRemove = true
                } else {
                    withAnimation(Theme.snap) {
                        store.toggleOrdered(dish, from: menu)
                        noteDraft = store.order(for: dish)?.note ?? ""
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(order == nil ? "Ordered this?" : "You ordered this")
                            .font(Theme.headline)
                            .foregroundStyle(Theme.ink)
                        if let order {
                            Text(order.orderedAt.formatted(.dateTime.day().month().year()))
                                .font(Theme.micro)
                                .foregroundStyle(Theme.inkTertiary)
                        }
                    }
                    Spacer()
                    Image(systemName: order == nil ? "circle" : "checkmark.circle.fill")
                        .font(.system(size: 27))
                        .foregroundStyle(order == nil ? Theme.ink : Theme.great)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.press(scale: 0.985))
            .accessibilityLabel(order == nil ? "Mark as ordered" : "Ordered")
            .accessibilityAddTraits(order == nil ? [] : .isSelected)

            if let order {
                Divider().overlay(Theme.hairline)

                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("How was it?")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)

                    StarRating(rating: order.rating, size: 27) { stars in
                        store.rate(order, stars: stars)
                    }

                    TextField("A note for next time", text: $noteDraft, axis: .vertical)
                        .font(Theme.callout)
                        .lineLimit(2 ... 5)
                        .focused($noteFocused)
                        .padding(Theme.Space.s)
                        .background(Theme.surfaceSunken, in: .rect(cornerRadius: Theme.Radius.chip, style: .continuous))
                        .onChange(of: noteFocused) { _, focused in
                            if !focused { store.setNote(noteDraft, for: order) }
                        }
                        .id("note")
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tile()
        .animation(Theme.gentle, value: order?.id)
    }
}

// MARK: - Pieces

/// The thin bar under the match figure. Fills from empty, like the rings.
private struct MatchBar: View {
    /// 0…1.
    let progress: Double
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    private var target: Double {
        progress.isFinite ? min(max(progress, 0), 1) : 0
    }

    var body: some View {
        Capsule()
            .fill(Theme.track)
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(tint)
                        // Never narrower than its own round ends.
                        .frame(width: shown > 0 ? max(geo.size.width * shown, 6) : 0)
                }
            }
            .accessibilityHidden(true)
            .onAppear {
                if reduceMotion { shown = target } else { withAnimation(Theme.gentle.delay(0.15)) { shown = target } }
            }
            .onChange(of: target) { _, new in
                if reduceMotion { shown = new } else { withAnimation(Theme.gentle) { shown = new } }
            }
    }
}

/// One of the three small tiles: a coloured glyph in a light circle beside
/// its label, the value in bold beneath.
private struct FactTile: View {
    let icon: String
    let tint: Color
    let label: String
    let value: String
    /// What VoiceOver says when the value is only a dash.
    var spokenValue: String?
    /// Grey for a value that reports an absence ("Not listed"), so it
    /// doesn't carry the same weight as a real figure.
    var valueColor: Color = Theme.ink

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(Theme.surfaceSunken, in: .circle)
                Text(label)
                    .scaledFont(size: 13, relativeTo: .footnote)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(value)
                .scaledFont(size: 16, weight: .bold, relativeTo: .callout)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tile(padding: Theme.Space.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(spokenValue ?? value)")
    }
}

/// A bold heading on the ground with its content in a tile beneath.
private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            GroundHeader(title)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .tile()
        }
        // With the page's 16pt gap, the 28pt every ground header gets.
        .padding(.top, Theme.Space.sm)
    }
}
