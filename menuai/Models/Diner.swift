//
//  Diner.swift
//  menuai
//
//  The people you eat with.
//
//  Eating out is social, and the awkward part of a foreign menu is rarely
//  your own order — it's working out what the person across the table can
//  actually have. Because scoring is deterministic, adding a companion costs
//  nothing at scan time: the same parsed dishes get re-ranked locally against
//  their profile, with no extra model call and no extra wait.
//

import SwiftUI

struct Diner: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// Index into `Diner.palette`, so a person keeps their colour everywhere.
    var colorIndex: Int = 0
    var diet: Diet = .omnivore
    var allergies: [String] = []
    var dislikes: [String] = []
    var spiceTolerance: Int = 1
    var adventurousness: Int = 2

    var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    var color: Color {
        Diner.palette[abs(colorIndex) % Diner.palette.count]
    }

    /// A one-line summary for the companion list.
    var summary: String {
        var parts: [String] = []
        if diet != .omnivore { parts.append(diet.label) }
        if !allergies.isEmpty { parts.append("no " + allergies.map { $0.lowercased() }.joined(separator: ", ")) }
        if parts.isEmpty {
            parts.append("Heat: " + Choices.labels.spice[min(max(spiceTolerance, 0), 3)])
        }
        return parts.joined(separator: " · ")
    }

    /// Their preferences in the shape the scorer wants. Language comes from
    /// the account holder — it belongs to the phone, not to the person
    /// sitting opposite.
    func preferences(inheriting base: UserPreferences) -> UserPreferences {
        var prefs = base
        prefs.diet = diet
        prefs.allergies = allergies
        prefs.dislikes = dislikes
        prefs.spiceTolerance = spiceTolerance
        prefs.adventurousness = adventurousness
        prefs.lovedCuisines = []
        prefs.notes = ""
        // A goal is personal: what the account holder is going for tonight
        // says nothing about the person opposite.
        prefs.goal = .none
        prefs.goalNote = ""
        return prefs
    }

    static var palette: [Color] { Theme.avatars }
}

enum DinerStore {
    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("diners.json")
    }

    static func load() -> [Diner] {
        guard let data = try? Data(contentsOf: url),
              let diners = try? JSONDecoder().decode([Diner].self, from: data)
        else { return [] }
        return diners
    }

    static func save(_ diners: [Diner]) {
        guard let data = try? JSONEncoder().encode(diners) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
