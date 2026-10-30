//
//  OrderedDish.swift
//  menuai
//
//  What you actually ate. Every dish you mark as ordered is kept with its
//  rating and note, and the resulting history is fed back into the next
//  menu's scoring — so the app converges on your taste instead of restating
//  the same onboarding answers forever.
//

import Foundation

struct OrderedDish: Codable, Identifiable, Hashable {
    var id = UUID()

    // A snapshot rather than a reference: the menu it came from may be
    // deleted, and the dish should survive that.
    var name: String
    var originalName: String
    var restaurant: String
    var cuisineHint: String
    var description: String
    var price: String
    var imageSearchQuery: String
    var ingredients: [String]

    var orderedAt: Date = .now
    /// 0 means ordered but not yet rated.
    var rating: Int = 0
    var note: String = ""
    /// Thumbnail of the menu it came from, if we still have it.
    var imageFileName: String?

    var isRated: Bool { rating > 0 }

    init(from dish: Dish, restaurant: String, imageFileName: String?) {
        name = dish.displayName
        originalName = dish.originalName
        self.restaurant = restaurant
        cuisineHint = dish.cuisine
        description = dish.description
        price = dish.price
        imageSearchQuery = dish.imageSearchQuery
        ingredients = dish.ingredients
        self.imageFileName = imageFileName
    }
}

// MARK: - Taste memory

/// The distilled history that gets injected into the next scan's prompt.
/// Deliberately small — a handful of loved and disliked dishes teaches the
/// model more than fifty lukewarm ones, and keeps the on-device model's
/// limited context free for the menu itself.
struct TasteMemory {
    var loved: [OrderedDish]
    var disliked: [OrderedDish]

    init(orders: [OrderedDish]) {
        let rated = orders.filter(\.isRated)

        loved = rated.filter { $0.rating >= 4 }
            .sorted { ($0.rating, $0.orderedAt) > ($1.rating, $1.orderedAt) }
            .prefix(6).map { $0 }

        disliked = rated.filter { $0.rating <= 2 }
            .sorted { $0.orderedAt > $1.orderedAt }
            .prefix(4).map { $0 }
    }

    var isEmpty: Bool { loved.isEmpty && disliked.isEmpty }

    /// Prose for the prompt. Includes the user's own notes because that is
    /// where the real signal lives ("too sweet", "loved the char on it").
    var promptDescription: String {
        guard !isEmpty else { return "" }
        var lines = ["Their dining history so far (weigh this heavily — it is real evidence, unlike the stated preferences above):"]

        for dish in loved {
            var line = "- LOVED (\(dish.rating)/5): \(dish.name)"
            if !dish.cuisineHint.isEmpty { line += " [\(dish.cuisineHint)]" }
            if !dish.note.isEmpty { line += " — they wrote: \"\(dish.note)\"" }
            lines.append(line)
        }

        for dish in disliked {
            var line = "- DISLIKED (\(dish.rating)/5): \(dish.name)"
            if !dish.cuisineHint.isEmpty { line += " [\(dish.cuisineHint)]" }
            if !dish.note.isEmpty { line += " — they wrote: \"\(dish.note)\"" }
            lines.append(line)
        }

        lines.append("Favour dishes sharing ingredients, technique, or cuisine with what they loved. Penalise echoes of what they disliked, and say so in the reason.")
        return lines.joined(separator: "\n")
    }
}
