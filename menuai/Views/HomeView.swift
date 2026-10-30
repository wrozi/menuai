//
//  HomeView.swift
//  menuai
//
//  Home: what you open at the table. The wordmark, one big card that
//  starts the camera, a quieter way in from the photo library, and the
//  menus you have already read. A menu still being read sits at the top
//  of Recent as a processing card, so the screen never goes away for it.
//

import SwiftUI

struct HomeView: View {
    /// The root stack's path. Menus and the You screen are pushed onto it
    /// from here; the root registers the destinations.
    @Binding var path: NavigationPath

    @Environment(AppStore.self) private var store
    @State private var appeared = false

    /// True while a new menu is being read. The ways in go quiet and the
    /// processing card leads Recent until the menu takes its place.
    private var isReading: Bool { store.isReadingNewMenu }

    var body: some View {
        // One List, so swipe to delete can own each menu row; the rows above
        // them are the same whether or not any menus exist.
        List {
            header
                .riseIn(0, isActive: appeared)
                .homeRow(top: Theme.Space.s, bottom: Theme.Space.s)

            hero
                .riseIn(1, isActive: appeared)
                .quiet(isReading)
                .homeRow(top: Theme.Space.xs, bottom: 5)

            choosePhoto
                .riseIn(2, isActive: appeared)
                .quiet(isReading)
                .homeRow(top: 5, bottom: Theme.Space.xs)

            recentSection
        }
        .animation(Theme.gentle, value: isReading)
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 1)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, Theme.Space.xl, for: .scrollContent)
        .background(Theme.bg)
        // With no bar, rows would otherwise scroll up behind the clock.
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: 0).background(Theme.bg)
        }
        // Hidden on this root only; pushed screens keep theirs.
        .toolbar(.hidden, for: .navigationBar)
        .task {
            appeared = true
            #if DEBUG
            if SelfTest.showsReading {
                if let name = store.savedMenus.first?.imageFileName {
                    store.pendingImage = await ThumbnailCache.load(name)
                }
                store.scanState = .analyzing(progress: 0.42, message: "Reading page 1…")
            }
            if SelfTest.opensFirstMenu, let first = store.savedMenus.first {
                path.append(first)
                // The dish as a tap on its row would pass it: rescored, so a
                // block added on You since the photo shows on the dish too.
                let shown = store.menu(rescored: first)
                if SelfTest.opensFirstDish, let dish = shown.topPicks.first ?? shown.allDishes.first {
                    path.append(DebugDishRoute(dish: dish, menu: first))
                }
            }
            #endif
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Space.s) {
            HStack(spacing: 8) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityHidden(true)
                Text("MenuAI")
                    .scaledFont(size: 26, weight: .bold, relativeTo: .title)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
            }

            Spacer(minLength: Theme.Space.s)

            Button {
                Haptic.tap()
                path.append(AppRoute.you)
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 40, height: 40)
                    .background { Circle().fill(Theme.surface).cardShadow() }
                    .overlay { Circle().strokeBorder(Theme.cardEdge, lineWidth: 1) }
                    .contentShape(.circle)
            }
            .buttonStyle(.press(scale: 0.94))
            .accessibilityLabel("You")
        }
        .frame(minHeight: 40)
    }

    // MARK: - Hero

    /// The only big thing on the screen: the whole card opens the camera.
    private var hero: some View {
        Button {
            Haptic.tap()
            store.captureRequest = .camera
        } label: {
            VStack(spacing: Theme.Space.m) {
                // The one obvious target on the screen: the same black disc
                // the onboarding summary uses for its check.
                ZStack {
                    Circle().fill(Theme.accent).frame(width: 72, height: 72)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                }
                .accessibilityHidden(true)

                VStack(spacing: Theme.Space.xs) {
                    Text("Point at a menu")
                        .scaledFont(size: 24, weight: .bold, relativeTo: .title2)
                        .foregroundStyle(Theme.ink)
                    Text("Any language. Ranked for you.")
                        .scaledFont(size: 15, relativeTo: .subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .multilineTextAlignment(.center)
            }
            // About 220pt with the card's own padding around it.
            .frame(maxWidth: .infinity, minHeight: 176)
            .card(padding: Theme.Space.l)
            .contentShape(.rect(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.press(scale: 0.985))
        .accessibilityLabel("Point at a menu")
        .accessibilityHint("Opens the camera")
    }

    /// The quieter way in, for a menu photographed earlier.
    private var choosePhoto: some View {
        Button {
            Haptic.tap()
            store.captureRequest = .library
        } label: {
            Text("Choose a photo")
                .font(Theme.callout.weight(.medium))
                .foregroundStyle(Theme.ink)
                .padding(.vertical, Theme.Space.s)
                .padding(.horizontal, Theme.Space.m)
                .contentShape(.rect)
        }
        .buttonStyle(.press)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Recent menus

    /// Header and rows laid flat so the List owns each row — swipe to delete
    /// needs the row itself, not a stack wrapping it. The section is always
    /// here; with nothing saved it says where the menus will go, and a menu
    /// being read leads it as a processing card.
    @ViewBuilder private var recentSection: some View {
        GroundHeader("Recent")
            .riseIn(3, isActive: appeared)
            .homeRow(top: Theme.Space.sm, bottom: Theme.Space.xs)

        if isReading, case let .analyzing(progress, message) = store.scanState {
            ProcessingCard(image: store.pendingImage, progress: progress, message: message)
                .riseIn(4, isActive: appeared)
                .homeRow(top: Theme.Space.xs, bottom: Theme.Space.xs)
                .transition(.opacity)
        } else if store.savedMenus.isEmpty {
            Text("Menus you point at show up here.")
                .font(Theme.callout)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Space.m)
                .frame(maxWidth: .infinity, minHeight: 88)
                .card(padding: 0)
                .riseIn(4, isActive: appeared)
                .homeRow(top: Theme.Space.xs, bottom: Theme.Space.xs)
        }

        ForEach(Array(store.savedMenus.enumerated()), id: \.element.id) { index, menu in
            // Read through the live safety check, so the card agrees with the
            // screen it opens. The raw menu is what the path carries.
            let shown = store.menu(rescored: menu)
            // A Button onto the path rather than a NavigationLink(value:):
            // the same push, without the disclosure chevron a List adds.
            Button {
                Haptic.tap()
                path.append(menu)
            } label: {
                RecentMenuCard(menu: shown)
            }
            .buttonStyle(.press(scale: 0.985))
            .riseIn(index + (isReading ? 5 : 4), isActive: appeared)
            .homeRow(top: Theme.Space.xs, bottom: Theme.Space.xs)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    withAnimation(Theme.gentle) { store.delete(menu) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .contextMenu {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    withAnimation(Theme.gentle) { store.delete(menu) }
                }
            }
        }
    }
}

// MARK: - Row plumbing

private extension View {
    /// A bare List row on the page ground with the screen's side margins.
    func homeRow(top: CGFloat, bottom: CGFloat) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: top, leading: Theme.Space.m, bottom: bottom, trailing: Theme.Space.m))
    }

    /// Fades a way in and takes it out of reach while a menu is being read.
    /// One read at a time; a second photo would only queue behind the first.
    func quiet(_ isQuiet: Bool) -> some View {
        self
            .opacity(isQuiet ? 0.5 : 1)
            .allowsHitTesting(!isQuiet)
            .disabled(isQuiet)
    }
}

// MARK: - Menu card

/// One saved menu: its photo set inside the card, the place and when on one
/// line, the dish to order on the next, and how many to avoid when there
/// are any.
private struct RecentMenuCard: View {
    let menu: ParsedMenu

    @Environment(\.dynamicTypeSize) private var typeSize

    private var bestDish: Dish? { menu.topPicks.first }
    private var avoidCount: Int { menu.blockedCount }

    /// Never fresher than a minute: "in 0 sec" and "5 sec ago" flicker
    /// on the way back from a menu you just read.
    private var when: String {
        let at = min(menu.scannedAt, .now.addingTimeInterval(-60))
        return at.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
    }

    var body: some View {
        MediaCard(thumbnail: menu.imageFileName, placeholder: "doc.text.image") {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                titleRow

                if let bestDish {
                    HStack(alignment: .center, spacing: 6) {
                        RankBadge(rank: 1)
                            .accessibilityLabel("Top pick")
                        Text(bestDish.displayName)
                            .scaledFont(size: 14, weight: .medium, relativeTo: .subheadline)
                            .lineLimit(1)
                    }
                    .foregroundStyle(Theme.ink)
                }

                if avoidCount > 0 {
                    IconStat(icon: "exclamationmark.triangle.fill", tint: Theme.danger,
                             text: "\(avoidCount) to avoid")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Place and time share a line until the text is large enough that the
    /// pill would squeeze the name to nothing; then the pill drops below.
    @ViewBuilder private var titleRow: some View {
        if typeSize >= .xLarge {
            VStack(alignment: .leading, spacing: 6) {
                title
                TimePill(text: when)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                title
                Spacer(minLength: 0)
                TimePill(text: when)
            }
        }
    }

    private var title: some View {
        Text(menu.title)
            .scaledFont(size: 16, weight: .semibold, relativeTo: .callout)
            .foregroundStyle(Theme.ink)
            .lineLimit(typeSize >= .xLarge ? 2 : 1)
    }
}
