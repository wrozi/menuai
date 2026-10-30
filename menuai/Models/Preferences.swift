//
//  Preferences.swift
//  menuai
//
//  What the user told us: asked once in onboarding, edited in place on You.
//  The engines read it as prose; the scorer ranks every dish against it.
//

import Foundation

enum Diet: String, Codable, CaseIterable, Identifiable {
    case omnivore, vegetarian, vegan, pescatarian, halal, kosher

    var id: String { rawValue }

    var label: String {
        switch self {
        case .omnivore: "No restrictions"
        case .vegetarian: "Vegetarian"
        case .vegan: "Vegan"
        case .pescatarian: "Pescatarian"
        case .halal: "Halal"
        case .kosher: "Kosher"
        }
    }

    var icon: String {
        switch self {
        case .omnivore: "fork.knife"
        case .vegetarian: "leaf"
        case .vegan: "carrot"
        case .pescatarian: "fish"
        case .halal: "moon.stars"
        // No hexagram exists in SF Symbols, and an icon that doesn't exist
        // renders as an empty gap rather than failing loudly. A seal is both
        // valid and accurate — kosher status is a certification.
        case .kosher: "checkmark.seal"
        }
    }
}

/// What the diner is going for at this meal. A soft nudge on the ranking —
/// it never blocks a dish and never touches the allergy or diet checks.
enum EatingGoal: String, Codable, CaseIterable, Identifiable {
    case none, healthy, light, hearty, protein

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "No goal"
        case .healthy: "Eat well"
        case .light: "Keep it light"
        case .hearty: "Fuel up"
        case .protein: "More protein"
        }
    }

    var detail: String {
        switch self {
        case .none: "Anything goes"
        case .healthy: "Fresh, balanced, not fried"
        case .light: "Fewer calories"
        case .hearty: "Big and filling"
        case .protein: "Lean meat, fish, eggs, beans"
        }
    }

    var icon: String {
        switch self {
        // Not the fork that heads "No restrictions" one list up.
        case .none: "target"
        case .healthy: "heart.fill"
        // Not the leaf beside Vegetarian, on the same screen.
        case .light: "wind"
        case .hearty: "bolt.fill"
        case .protein: "dumbbell.fill"
        }
    }

    /// (label, detail, icon) in `allCases` order, the shape `ChoiceList` takes.
    static var choices: [(String, String, String)] {
        allCases.map { ($0.label, $0.detail, $0.icon) }
    }

    /// The one line the engines see. Nil for `.none`.
    var promptLine: String? {
        switch self {
        case .none: nil
        case .healthy: "Goal: eat well — prefers fresh, balanced dishes over fried or rich ones."
        case .light: "Goal: keep it light — prefers lighter, lower-calorie dishes."
        case .hearty: "Goal: fuel up — prefers big, filling dishes."
        case .protein: "Goal: more protein — prefers lean meat, fish, eggs and beans."
        }
    }
}

/// Common allergens offered as one-tap chips. The user can add free-text ones too.
enum CommonAllergen: String, CaseIterable, Identifiable {
    case peanuts, treeNuts = "tree nuts", dairy, eggs, gluten, shellfish
    case fish, soy, sesame, mustard, celery, sulfites

    var id: String { rawValue }
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// The common chips, then any custom ones already chosen.
    static func options(including custom: [String]) -> [String] {
        let common = allCases.map(\.label)
        return common + custom.filter { !common.contains($0) }
    }
}

let cuisineOptions = [
    "Italian", "Japanese", "Thai", "Mexican", "Indian", "Chinese", "French",
    "Korean", "Vietnamese", "Greek", "Spanish", "Turkish", "Lebanese",
    "Ethiopian", "Peruvian", "American BBQ", "Seafood", "Steakhouse",
]

let supportedLanguages: [(code: String, name: String)] = [
    ("en", "English"), ("es", "Español"), ("fr", "Français"), ("de", "Deutsch"),
    ("it", "Italiano"), ("pt", "Português"), ("nl", "Nederlands"), ("he", "עברית"),
    ("ar", "العربية"), ("ru", "Русский"), ("uk", "Українська"), ("pl", "Polski"),
    ("tr", "Türkçe"), ("el", "Ελληνικά"), ("ja", "日本語"), ("ko", "한국어"),
    ("zh", "中文"), ("th", "ไทย"), ("vi", "Tiếng Việt"), ("hi", "हिन्दी"),
]

struct UserPreferences: Codable, Equatable {
    /// BCP-47 code of the language the user wants the menu translated *into*.
    /// Falls back to English when the device language isn't one we offer, so
    /// the picker and the stored value always agree on first run.
    var displayLanguage: String = {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return supportedLanguages.contains { $0.code == code } ? code : "en"
    }()
    var diet: Diet = .omnivore
    var allergies: [String] = []
    var dislikes: [String] = []
    var lovedCuisines: [String] = []
    /// 0 = no spice at all, 3 = the hotter the better.
    var spiceTolerance: Int = 1
    /// 0 = stick to what I know, 3 = give me the weirdest thing on the menu.
    var adventurousness: Int = 2
    var notes: String = ""
    /// What they're going for at the table. Personal, so companions never
    /// inherit it.
    var goal: EatingGoal = .none
    /// Their own words on the goal, e.g. "low carb". Read by the engines and,
    /// for explicit "no X" phrasing, nudged softly by the scorer.
    var goalNote: String = ""
    var hasCompletedOnboarding: Bool = false

    private enum CodingKeys: String, CodingKey {
        case displayLanguage, diet, allergies, dislikes, lovedCuisines
        case spiceTolerance, adventurousness, notes, goal, goalNote
        case hasCompletedOnboarding
    }

    /// Human-readable name of the target language, for the prompt.
    var displayLanguageName: String {
        Locale(identifier: "en").localizedString(forLanguageCode: displayLanguage)
            ?? displayLanguage
    }

    /// Taste only — no allergy or diet text.
    ///
    /// Apple's on-device guardrail rejects prompts carrying medical-sounding
    /// content: sending the full profile made the model refuse with
    /// "May contain unsafe content" and skip the comparison entirely. The
    /// comparison pass never needs it anyway, because dishes that conflict
    /// with an allergy or diet have already been filtered out before it runs.
    var tasteOnlyDescription: String {
        var lines: [String] = []
        let spice = ["avoids spice entirely", "mild only", "likes a decent kick", "seeks out the spiciest option"]
        lines.append("Spice: \(spice[min(max(spiceTolerance, 0), 3)]).")

        let adventure = [
            "wants familiar, safe choices",
            "mostly familiar, open to one small surprise",
            "happy to try unfamiliar dishes",
            "actively wants the most unusual or local dish on the menu",
        ]
        lines.append("Adventurousness: \(adventure[min(max(adventurousness, 0), 3)]).")

        if !lovedCuisines.isEmpty {
            lines.append("Cuisines they love: \(lovedCuisines.joined(separator: ", ")).")
        }
        if !dislikes.isEmpty {
            lines.append("Ingredients they dislike: \(dislikes.joined(separator: ", ")).")
        }
        lines.append(contentsOf: goalLines)
        return lines.joined(separator: "\n")
    }

    /// The goal as one line, plus their own words when they gave any.
    private var goalLines: [String] {
        var lines: [String] = []
        if let line = goal.promptLine { lines.append(line) }
        let note = goalNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { lines.append("In their own words: \(note)") }
        return lines
    }

    /// The taste profile as Claude sees it. Kept as prose because the model
    /// reasons about nuance ("mild peanut allergy" vs "anaphylactic") better
    /// from a sentence than from a flag.
    var promptDescription: String {
        var lines: [String] = []
        lines.append("Target language for all translations: \(displayLanguageName) (\(displayLanguage)).")
        lines.append("Diet: \(diet.label).")

        if allergies.isEmpty {
            lines.append("Allergies: none reported.")
        } else {
            lines.append("ALLERGIES (treat as safety-critical): \(allergies.joined(separator: ", ")).")
        }

        if !dislikes.isEmpty {
            lines.append("Dislikes / avoids: \(dislikes.joined(separator: ", ")).")
        }
        if !lovedCuisines.isEmpty {
            lines.append("Cuisines they love: \(lovedCuisines.joined(separator: ", ")).")
        }

        let spice = ["avoids spice entirely", "mild only", "likes a decent kick", "seeks out the spiciest option"]
        lines.append("Spice tolerance: \(spice[min(max(spiceTolerance, 0), 3)]).")

        let adventure = [
            "wants familiar, safe choices",
            "mostly familiar, open to one small surprise",
            "happy to try unfamiliar dishes",
            "actively wants the most unusual, local, or challenging dish on the menu",
        ]
        lines.append("Adventurousness: \(adventure[min(max(adventurousness, 0), 3)]).")

        lines.append(contentsOf: goalLines)

        if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Free-text notes from the user: \(notes)")
        }
        return lines.joined(separator: "\n")
    }
}

extension UserPreferences {
    /// Lives in an extension so the struct keeps its synthesised `init()`.
    ///
    /// `goal` and `goalNote` arrived after people had already saved their
    /// preferences, so both are optional on the way in. Encoding stays
    /// synthesised.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayLanguage = try container.decode(String.self, forKey: .displayLanguage)
        diet = try container.decode(Diet.self, forKey: .diet)
        allergies = try container.decode([String].self, forKey: .allergies)
        dislikes = try container.decode([String].self, forKey: .dislikes)
        lovedCuisines = try container.decode([String].self, forKey: .lovedCuisines)
        spiceTolerance = try container.decode(Int.self, forKey: .spiceTolerance)
        adventurousness = try container.decode(Int.self, forKey: .adventurousness)
        notes = try container.decode(String.self, forKey: .notes)
        goal = try container.decodeIfPresent(EatingGoal.self, forKey: .goal) ?? .none
        goalNote = try container.decodeIfPresent(String.self, forKey: .goalNote) ?? ""
        hasCompletedOnboarding = try container.decode(Bool.self, forKey: .hasCompletedOnboarding)
    }
}
