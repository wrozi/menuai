//
//  MenuResultView.swift
//  menuai
//

import PhotosUI
import SwiftUI

struct MenuResultView: View {
    /// Held in state because a menu grows: photographing page two merges into
    /// this same menu rather than starting a new one.
    @State private var menu: ParsedMenu

    @Environment(AppStore.self) private var store
    @State private var appeared = false
    /// nil means the account holder.
    @State private var diner: Diner?
    @State private var showPageCamera = false
    @State private var pagePickerItem: PhotosPickerItem?
    @State private var showAddPage = false
    @State private var showLibraryForPage = false
    @State private var showWaiter = false

    /// The menu as the selected person sees it.
    ///
    /// Held in state rather than computed: a computed property would re-score
    /// every dish on the menu each time SwiftUI evaluated the body, which is
    /// many times per scroll frame. Recomputed only when the selection
    /// actually changes.
    @State private var shown: ParsedMenu

    init(menu: ParsedMenu) {
        _menu = State(initialValue: menu)
        _shown = State(initialValue: menu)
    }

    /// Always against what the person eats now, not what they ate when the
    /// menu was read — see `AppStore.menu(rescored:)`.
    private func rescore() {
        guard let diner else {
            shown = store.menu(rescored: menu)
            return
        }
        shown = store.menu(menu, scoredFor: diner)
    }

    /// What the waiter must know, before anything is chosen: nil when there
    /// is nothing to say.
    private var waiterLine: (local: String, english: String)? {
        Phrasebook.waiterLine(
            allergens: store.preferences.allergies,
            diet: store.preferences.diet,
            language: Phrasebook.language(for: menu)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                if !menu.summary.isEmpty || shown.blockedCount > 0 {
                    header.riseIn(0, isActive: appeared)
                }

                // Only shown once there is somebody to switch between. A solo
                // diner should never see a control that does nothing.
                if !store.diners.isEmpty {
                    dinerBar.riseIn(1, isActive: appeared)
                }

                if !shown.topPicks.isEmpty {
                    topPicks.riseIn(2, isActive: appeared)
                }

                list
            }
            .padding(.horizontal, Theme.Space.m)
            // Nothing floats over the content; the pinned bar is already
            // accounted for by the inset below.
            .padding(.bottom, Theme.Space.xl)
        }
        .background(Theme.bg)
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .navigationTitle(menu.title)
        .navigationBarTitleDisplayMode(.inline)
        .circleBackButton()
        .task {
            appeared = true
            rescore()
        }
        .onChange(of: diner?.id) { _, _ in withAnimation(Theme.gentle) { rescore() } }
        .onChange(of: store.preferences) { _, _ in withAnimation(Theme.gentle) { rescore() } }
        .onChange(of: store.diners) { _, diners in
            withAnimation(Theme.gentle) {
                if let current = diner { diner = diners.first { $0.id == current.id } }
                rescore()
            }
        }
        .fullScreenCover(isPresented: $showWaiter) {
            OrderCardView(
                dish: nil,
                menu: menu,
                allergies: store.preferences.allergies,
                diet: store.preferences.diet
            )
        }
        .modifier(
            AddPageFlow(
                menu: $menu,
                showChooser: $showAddPage,
                showCamera: $showPageCamera,
                showLibrary: $showLibraryForPage,
                pickerItem: $pagePickerItem,
                onMerged: { rescore() }
            )
        )
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if !menu.summary.isEmpty {
                Text(menu.summary)
                    .font(Theme.body)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if shown.blockedCount > 0 {
                Chip(
                    text: "\(shown.blockedCount) to avoid",
                    icon: "exclamationmark.triangle.fill",
                    tint: Theme.danger
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Top picks

    private var topPicks: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            GroundHeader(diner.map { "For \($0.name)" } ?? "For you")

            ForEach(Array(shown.topPicks.enumerated()), id: \.element.id) { index, dish in
                NavigationLink {
                    DishDetailView(dish: dish, menu: menu, diner: diner)
                } label: {
                    TopPickCard(dish: dish, rank: index + 1)
                }
                .buttonStyle(.press(scale: 0.985))
                .simultaneousGesture(TapGesture().onEnded { Haptic.tap() })
            }
        }
        // The same air above a ground header as on Home.
        .padding(.top, Theme.Space.xs)
    }

    // MARK: - Who's eating

    private var dinerBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Space.s) {
                DinerChip(name: "You", color: Theme.inkSecondary, initial: "Y", isSelected: diner == nil) {
                    diner = nil
                }
                ForEach(store.diners) { companion in
                    DinerChip(
                        name: companion.name,
                        color: companion.color,
                        initial: companion.initial,
                        isSelected: diner?.id == companion.id
                    ) {
                        diner = companion
                    }
                }
                NavigationLink(value: AppRoute.companions) {
                    HStack(spacing: 5) {
                        Image(systemName: "pencil").scaledFont(size: 11, weight: .bold, relativeTo: .caption2)
                        Text("Edit").font(Theme.micro)
                    }
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(Theme.surfaceSunken, in: .capsule)
                }
                .buttonStyle(.press)
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
        .animation(Theme.snap, value: diner?.id)
    }

    /// Add a page on the left; on the right what the waiter must know. With
    /// nothing to tell them, adding a page is the one action.
    private var actionBar: some View {
        let addPage = BottomActionBar.Item(title: "Add a page", icon: "plus.viewfinder") { showAddPage = true }
        return waiterLine == nil
            ? BottomActionBar(primary: addPage)
            : BottomActionBar(secondary: addPage, primary: .init(title: "Show the waiter", icon: "hand.raised.fill") { showWaiter = true })
    }

    // MARK: - List

    private var list: some View {
        LazyVStack(alignment: .leading, spacing: Theme.Space.l) {
            ForEach(Array(shown.sections.enumerated()), id: \.element.id) { index, section in
                if !section.dishes.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        VStack(alignment: .leading, spacing: 2) {
                            GroundHeader(section.name)
                            if let subtitle = sectionSubtitle(section) {
                                Text(subtitle)
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.inkTertiary)
                                    .padding(.horizontal, 2)
                            }
                        }
                        dishRows(section.dishes, offset: 3 + index)
                    }
                }
            }
        }
        .padding(.top, Theme.Space.xs)
    }

    private func dishRows(_ dishes: [Dish], offset: Int) -> some View {
        ForEach(Array(dishes.enumerated()), id: \.element.id) { index, dish in
            NavigationLink {
                DishDetailView(dish: dish, menu: menu, diner: diner)
            } label: {
                DishRow(dish: dish, ordered: store.hasOrdered(dish))
            }
            .buttonStyle(.press(scale: 0.985))
            .simultaneousGesture(TapGesture().onEnded { Haptic.tap() })
            .riseIn(index + offset, isActive: appeared)
        }
    }

    private func sectionSubtitle(_ section: MenuSection) -> String? {
        guard !section.originalName.isEmpty,
              section.originalName.caseInsensitiveCompare(section.name) != .orderedSame
        else { return nil }
        return section.originalName
    }
}

// MARK: - Cards

/// The three recommendations at the top. Bigger, warmer, and rank-numbered so
/// they read as a shortlist rather than more list.
private struct TopPickCard: View {
    let dish: Dish
    let rank: Int

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            ScoreRing(score: dish.matchScore, size: 54)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    RankBadge(rank: rank)

                    if !dish.price.isEmpty {
                        Text(dish.price)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.ink)
                    }
                    if dish.spiceLevel > 0 { SpiceIndicator(level: dish.spiceLevel) }
                }

                Text(dish.displayName)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let original = dish.subtitleName {
                    Text(original)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                }

                if !dish.matchReason.isEmpty {
                    Text(dish.matchReason)
                        .font(Theme.callout)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        // Plain white like every other card on the reference; the ring
        // carries the colour. A hairline in the score colour is all that
        // separates the shortlist from the list below it.
        .card()
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.scoreColor(dish.matchScore).opacity(0.35), lineWidth: 1.5)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DishRow: View {
    let dish: Dish
    var ordered: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            ScoreRing(score: dish.matchScore, blocked: dish.isBlocked, size: 44, lineWidth: 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(dish.displayName)
                        .font(Theme.headline)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    if ordered {
                        Image(systemName: "checkmark.circle.fill")
                            .scaledFont(size: 12, relativeTo: .caption)
                            .foregroundStyle(Theme.great)
                    }
                }

                if let original = dish.subtitleName {
                    Text(original)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                }

                if let warning = dish.warnings.first {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.micro)
                        .foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !dish.matchReason.isEmpty {
                    Text(dish.matchReason)
                        .font(Theme.callout)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(2)
                }

                if !dish.price.isEmpty || dish.spiceLevel > 0 {
                    HStack(spacing: 8) {
                        if !dish.price.isEmpty {
                            Text(dish.price)
                                .font(Theme.caption)
                                .foregroundStyle(Theme.ink)
                        }
                        if dish.spiceLevel > 0 { SpiceIndicator(level: dish.spiceLevel) }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .card(padding: Theme.Space.sm)
        .opacity(dish.isBlocked ? 0.68 : 1)
        .accessibilityElement(children: .combine)
    }
}

private struct SpiceIndicator: View {
    let level: Int

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0 ..< min(max(level, 0), 3), id: \.self) { _ in
                Image(systemName: "flame.fill").scaledFont(size: 10, relativeTo: .caption2)
            }
        }
        .foregroundStyle(Theme.okay)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spice \(level) of 3")
    }
}

// MARK: - Diner chip

private struct DinerChip: View {
    let name: String
    let color: Color
    let initial: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptic.select()
            withAnimation(Theme.snap) { action() }
        } label: {
            HStack(spacing: 7) {
                ZStack {
                    Circle().fill(color).frame(width: 24, height: 24)
                    Text(initial)
                        .font(Theme.number(11))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)
                Text(name)
                    .font(Theme.caption)
                    .foregroundStyle(isSelected ? Theme.onAccent : Theme.ink)
            }
            .padding(.leading, 7)
            .padding(.trailing, 13)
            .frame(height: 38)
            .background(
                isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surface),
                in: .capsule
            )
            .overlay {
                if !isSelected {
                    Capsule().strokeBorder(Theme.hairline, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.press(scale: 0.96))
    }
}

// MARK: - Add-page flow

/// Camera or library, for the next page of the menu on screen.
private struct AddPageSheet: View {
    let onChoose: (CaptureSource) -> Void

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            Capsule().fill(Theme.hairline).frame(width: 36, height: 5).padding(.top, 8)

            Text("Add a page")
                .scaledFont(size: 24, weight: .bold, relativeTo: .title2)
                .foregroundStyle(Theme.ink)
                .padding(.top, Theme.Space.xs)

            VStack(spacing: Theme.Space.s) {
                if CameraPicker.isAvailable {
                    PillButton(title: "Take a photo", icon: "camera.fill") { onChoose(.camera) }
                }
                GhostButton(title: "Choose a photo", icon: "photo.on.rectangle") { onChoose(.library) }
            }
            .padding(.top, Theme.Space.s)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.m)
        .background(Theme.bg)
        .presentationDetents([.height(CameraPicker.isAvailable ? 250 : 190)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(Theme.Radius.sheet)
    }
}

/// All the plumbing for photographing a second page, kept out of the results
/// body — chaining this many modifiers inline defeats the type checker.
private struct AddPageFlow: ViewModifier {
    @Binding var menu: ParsedMenu
    @Binding var showChooser: Bool
    @Binding var showCamera: Bool
    @Binding var showLibrary: Bool
    @Binding var pickerItem: PhotosPickerItem?
    let onMerged: () -> Void

    @Environment(AppStore.self) private var store
    /// The choice made in the sheet, acted on once the sheet has gone — a
    /// camera presented while a sheet is still dismissing never appears.
    @State private var queued: CaptureSource?

    /// Refuses before the photo is taken, not after — the root alert then
    /// explains why.
    private func ready() -> Bool {
        guard let reason = EngineRouter.notReadyReason(apiKey: store.apiKey) else { return true }
        store.isAddingPage = true
        store.notReady = true
        store.scanState = .failed(reason)
        return false
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showChooser, onDismiss: {
                switch queued {
                case .camera: if ready() { showCamera = true }
                case .library: if ready() { showLibrary = true }
                case nil: break
                }
                queued = nil
            }) {
                AddPageSheet { source in
                    queued = source
                    showChooser = false
                }
            }
            .photosPicker(isPresented: $showLibrary, selection: $pickerItem, matching: .images)
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    Task { await store.addPage(image: image, to: menu) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    await store.analyze(item, addingTo: menu)
                    pickerItem = nil
                }
            }
            .onChange(of: store.mergedMenu) { _, merged in
                guard let merged, merged.id == menu.id else { return }
                withAnimation(Theme.gentle) {
                    menu = merged
                    onMerged()
                }
                store.mergedMenu = nil
            }
    }
}
