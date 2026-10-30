//
//  Menu.swift
//  menuai
//
//  The shape a parsed menu takes, whichever engine produced it. Both the
//  Claude and on-device engines map their output into these types, so every
//  screen downstream is engine-agnostic.
//

import Foundation

/// Which engine read the menu. Kept on the saved menu and in the self-test log.
enum MenuEngineKind: String, Codable, Hashable {
    case claude
    case onDevice

    var label: String {
        switch self {
        case .claude: "Claude"
        case .onDevice: "On-device"
        }
    }

    var icon: String {
        switch self {
        case .claude: "sparkles"
        case .onDevice: "iphone"
        }
    }
}

struct Dish: Codable, Identifiable, Hashable {
    /// Assigned locally after decoding so SwiftUI has a stable identity.
    var id = UUID()

    var originalName: String
    var translatedName: String
    /// Phonetic hint for ordering out loud. Empty when the original is
    /// already in the diner's script.
    var pronunciation: String
    var description: String
    var price: String
    /// e.g. "Thai", "Neapolitan". Matched against loved cuisines and past orders.
    var cuisine: String
    var ingredients: [String]
    var allergens: [String]
    var dietaryTags: [String]
    /// 0 (not spicy) through 3 (very hot).
    var spiceLevel: Int
    /// 0–100 fit for this diner.
    var matchScore: Int
    var matchReason: String
    /// Allergy or diet conflicts. Non-empty means the dish is blocked.
    var warnings: [String]
    /// English photo-search query, specific enough to find the real dish.
    var imageSearchQuery: String
    /// 1 indulgent … 10 very healthy. The engine's read, or the scorer's
    /// estimate when the engine left it blank.
    var healthScore: Int? = nil
    /// 1 light, 2 medium, 3 hearty.
    var heaviness: Int? = nil

    private enum CodingKeys: String, CodingKey {
        case originalName, translatedName, pronunciation, description, price
        case cuisine, ingredients, allergens, dietaryTags, spiceLevel
        case matchScore, matchReason, warnings, imageSearchQuery
        case healthScore, heaviness
    }

    var isBlocked: Bool { !warnings.isEmpty }

    var heavinessLabel: String? {
        switch heaviness {
        case 1: "Light"
        case 2: "Medium"
        case 3: "Hearty"
        default: nil
        }
    }

    /// The same estimate in the words people actually use.
    var calorieLabel: String? {
        switch heaviness {
        case 1: "Low"
        case 2: "Medium"
        case 3: "High"
        default: nil
        }
    }

    var displayName: String {
        translatedName.isEmpty ? originalName : translatedName
    }

    /// Show the original underneath only when it actually differs.
    var subtitleName: String? {
        let translated = translatedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = originalName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty, original.caseInsensitiveCompare(translated) != .orderedSame else {
            return nil
        }
        return original
    }

    /// Best-effort search string when the model didn't supply one.
    var resolvedSearchQuery: String {
        let query = imageSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty { return query }
        return [originalName, translatedName, cuisine, "dish"]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

extension Dish {
    /// Lives in an extension so the memberwise initialiser survives.
    ///
    /// `healthScore` and `heaviness` were added after menus had already been
    /// saved, so both decode as optional. Encoding stays synthesised, which
    /// writes them only when present.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        originalName = try container.decode(String.self, forKey: .originalName)
        translatedName = try container.decode(String.self, forKey: .translatedName)
        pronunciation = try container.decode(String.self, forKey: .pronunciation)
        description = try container.decode(String.self, forKey: .description)
        price = try container.decode(String.self, forKey: .price)
        cuisine = try container.decode(String.self, forKey: .cuisine)
        ingredients = try container.decode([String].self, forKey: .ingredients)
        allergens = try container.decode([String].self, forKey: .allergens)
        dietaryTags = try container.decode([String].self, forKey: .dietaryTags)
        spiceLevel = try container.decode(Int.self, forKey: .spiceLevel)
        matchScore = try container.decode(Int.self, forKey: .matchScore)
        matchReason = try container.decode(String.self, forKey: .matchReason)
        warnings = try container.decode([String].self, forKey: .warnings)
        imageSearchQuery = try container.decode(String.self, forKey: .imageSearchQuery)
        healthScore = try container.decodeIfPresent(Int.self, forKey: .healthScore)
        heaviness = try container.decodeIfPresent(Int.self, forKey: .heaviness)
    }
}

struct MenuSection: Codable, Identifiable, Hashable {
    var id = UUID()

    var name: String
    var originalName: String
    var dishes: [Dish]

    private enum CodingKeys: String, CodingKey {
        case name, originalName, dishes
    }
}

struct ParsedMenu: Codable, Identifiable, Hashable {
    var id = UUID()

    var detectedLanguages: [String]
    var restaurantName: String
    var currency: String
    var summary: String
    var sections: [MenuSection]

    var scannedAt: Date = .now
    var imageFileName: String?
    var engine: MenuEngineKind = .claude

    private enum CodingKeys: String, CodingKey {
        case detectedLanguages, restaurantName, currency, summary, sections
        case scannedAt, imageFileName, engine
    }

    var allDishes: [Dish] {
        sections.flatMap(\.dishes)
    }

    /// The shortlist: the three best matches that aren't blocked.
    var topPicks: [Dish] {
        allDishes
            .filter { !$0.isBlocked }
            .sorted { $0.matchScore > $1.matchScore }
            .prefix(3)
            .map { $0 }
    }

    var blockedCount: Int {
        allDishes.filter(\.isBlocked).count
    }

    var title: String {
        restaurantName.isEmpty ? "Menu" : restaurantName
    }

    /// Cuisine the menu as a whole reads as — used to tag orders that come
    /// from dishes the engine didn't label individually.
    var dominantCuisine: String {
        let cuisines = allDishes.map(\.cuisine).filter { !$0.isEmpty }
        guard !cuisines.isEmpty else { return "" }
        let counts = Dictionary(grouping: cuisines, by: { $0 }).mapValues(\.count)
        return counts.max { $0.value < $1.value }?.key ?? ""
    }
}
