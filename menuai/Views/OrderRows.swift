//
//  OrderRows.swift
//  menuai
//
//  One thing you ordered, and the sheet behind it. Rate straight from the
//  row — the whole point is that it stays a two-second job, because the
//  ratings are what make the next menu good.
//

import SwiftUI

// MARK: - Row

/// One thing you ordered: the menu's photo set inside the card, the name
/// with its date pill, where you had it, then the stars — live, so rating
/// never needs a second screen.
struct OrderRow: View {
    let order: OrderedDish
    let onOpen: () -> Void
    let onRate: (Int) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var dateText: String {
        order.orderedAt.formatted(
            Calendar.current.isDate(order.orderedAt, equalTo: .now, toGranularity: .year)
                ? .dateTime.day().month()
                : .dateTime.day().month().year()
        )
    }

    private var spokenLabel: String {
        var parts = [order.name]
        if !order.restaurant.isEmpty { parts.append(order.restaurant) }
        parts.append(dateText)
        if !order.note.isEmpty { parts.append(order.note) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Button {
            Haptic.tap()
            onOpen()
        } label: {
            MediaCard(thumbnail: order.imageFileName, placeholder: "fork.knife") {
                VStack(alignment: .leading, spacing: 6) {
                    titleRow

                    if !order.restaurant.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "mappin.and.ellipse")
                                .scaledFont(size: 13, weight: .medium, relativeTo: .footnote)
                            Text(order.restaurant)
                                .scaledFont(size: 14, weight: .medium, relativeTo: .subheadline)
                                .lineLimit(1)
                        }
                        .foregroundStyle(Theme.ink)
                    }

                    // The stars keep their 44pt targets; the negative padding
                    // only takes the slack out of the layout, and the leading
                    // pull lines the first star up with the text above it.
                    StarRating(rating: order.rating, size: 18, onRate: onRate)
                        .padding(.vertical, -7)
                        .padding(.leading, -5)

                    if !order.note.isEmpty {
                        Text(order.note)
                            .scaledFont(size: 13, relativeTo: .footnote)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.press(scale: 0.985))
        // One element: double-tap opens the note, swipe up or down rates.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityValue(order.rating == 0 ? "Not rated" : "\(order.rating) of 5")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if order.rating < 5 { onRate(order.rating + 1) }
            case .decrement: if order.rating > 1 { onRate(order.rating - 1) }
            @unknown default: break
            }
        }
    }

    /// Name and date share a line until the text is large enough that the
    /// pill would squeeze the name to nothing; then the pill drops below.
    @ViewBuilder private var titleRow: some View {
        if typeSize >= .xLarge {
            VStack(alignment: .leading, spacing: 6) {
                name
                TimePill(text: dateText)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                name
                Spacer(minLength: 0)
                TimePill(text: dateText)
            }
        }
    }

    private var name: some View {
        Text(order.name)
            .scaledFont(size: 16, weight: .semibold, relativeTo: .callout)
            .foregroundStyle(Theme.ink)
            // The name is the only thing that says what you're rating.
            .lineLimit(2)
    }
}

// MARK: - Note sheet

struct OrderNoteSheet: View {
    let order: OrderedDish

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var note: String
    @State private var showPhotos = false
    @State private var confirmDelete = false

    init(order: OrderedDish) {
        self.order = order
        _note = State(initialValue: order.note)
    }

    /// The photo browser works off a Dish, so rebuild a minimal one from the
    /// stored order.
    private var asDish: Dish {
        Dish(
            originalName: order.originalName,
            translatedName: order.name,
            pronunciation: "",
            description: order.description,
            price: order.price,
            cuisine: order.cuisineHint,
            ingredients: order.ingredients,
            allergens: [],
            dietaryTags: [],
            spiceLevel: 0,
            matchScore: 0,
            matchReason: "",
            warnings: [],
            imageSearchQuery: order.imageSearchQuery
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(order.name)
                            .scaledFont(size: 24, weight: .bold, relativeTo: .title2)
                            .foregroundStyle(Theme.ink)
                        if !order.restaurant.isEmpty {
                            Text(order.restaurant)
                                .font(Theme.callout)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        GroundHeader("Your note")
                        TextField("A note for next time", text: $note, axis: .vertical)
                            .font(Theme.body)
                            .lineLimit(3 ... 8)
                            .padding(Theme.Space.s)
                            .background(Theme.surfaceSunken, in: .rect(cornerRadius: Theme.Radius.chip, style: .continuous))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()
                    }

                    if !order.description.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            GroundHeader("What it is")
                            Text(order.description)
                                .font(Theme.body)
                                .foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .card()
                        }
                    }

                    GhostButton(title: "See photos", icon: "photo.on.rectangle.angled") {
                        showPhotos = true
                    }

                    Button(role: .destructive) { confirmDelete = true } label: {
                        Text("Delete")
                            .font(Theme.callout)
                            .foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.press(scale: 0.985))
                    .padding(.top, Theme.Space.xs)
                }
                .padding(.horizontal, Theme.Space.m)
                .padding(.bottom, Theme.Space.xl)
            }
            .background(Theme.bg)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .keyboardDone()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Theme.headline)
                }
            }
            .sheet(isPresented: $showPhotos) { PhotoBrowserView(dish: asDish) }
        }
        // Saves on any dismissal, including a drag down; setNote is a no-op once the order is deleted.
        .onDisappear { store.setNote(note, for: order) }
        .confirmationDialog("Delete this dish?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.delete(order)
                dismiss()
            }
        }
    }
}
