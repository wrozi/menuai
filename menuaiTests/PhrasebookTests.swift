//
//  PhrasebookTests.swift
//  menuaiTests
//
//  The waiter card is pure tables, so these pin the shape of every table
//  (nothing missing for any language) and the sentence that comes out of
//  them. They do not, and cannot, check that a translation reads well: a
//  native speaker has to do that.
//

import Foundation
import Testing
@testable import menuai

private func menu(languages: [String], names: [String], sections: [String] = []) -> ParsedMenu {
    let dishes = names.map {
        Dish(
            originalName: $0,
            translatedName: "",
            pronunciation: "",
            description: "",
            price: "",
            cuisine: "",
            ingredients: [],
            allergens: [],
            dietaryTags: [],
            spiceLevel: 0,
            matchScore: 50,
            matchReason: "",
            warnings: [],
            imageSearchQuery: ""
        )
    }
    return ParsedMenu(
        detectedLanguages: languages,
        restaurantName: "",
        currency: "",
        summary: "",
        sections: [MenuSection(name: "", originalName: sections.first ?? "", dishes: dishes)]
    )
}

@Suite("Phrasebook")
struct PhrasebookTests {
    private static let expected = ["en", "it", "es", "fr", "de", "pt", "nl", "el", "tr", "he", "ar",
                                   "ja", "zh-Hans", "zh-Hant", "ko", "th", "vi", "pl", "ru"]

    @Test("Every language the card speaks has a table")
    func languagesPresent() {
        for code in Self.expected {
            #expect(Phrasebook.tables[code] != nil, "no table for \(code)")
        }
    }

    @Test("Every table has both sentence shapes, all twelve nouns and all five diet lines")
    func tablesComplete() {
        for (code, table) in Phrasebook.tables {
            #expect(table.singular.contains("{item}"), "\(code) singular has no {item}")
            #expect(table.plural.contains("{list}"), "\(code) plural has no {list}")
            #expect(!table.singular.isEmpty && !table.plural.isEmpty)
            for allergen in CommonAllergen.allCases {
                let noun = table.nouns[allergen] ?? ""
                #expect(!noun.isEmpty, "\(code) has no word for \(allergen.rawValue)")
            }
            for diet in Diet.allCases where diet != .omnivore {
                let line = table.diets[diet] ?? ""
                #expect(!line.isEmpty, "\(code) has no line for \(diet.rawValue)")
            }
            #expect(table.diets[.omnivore] == nil, "\(code) says something for no restrictions")
            #expect(!table.order.isEmpty, "\(code) has no order line")
        }
    }

    @Test("No line is a form: nothing inflects for the speaker with a slash")
    func noGenderSlashes() {
        for (code, table) in Phrasebook.tables {
            let lines = [table.order, table.singular, table.plural] + Array(table.diets.values)
            for line in lines {
                #expect(!line.contains("/"), "\(code) still has a slash form: \(line)")
            }
            // A lowercase noun can only open a sentence where letters have case.
            if !["ja", "zh-Hans", "zh-Hant", "th"].contains(code) {
                #expect(!table.singular.hasPrefix("{item}"), "\(code) opens a sentence with a lowercase noun")
            }
        }
    }

    @Test("The order line follows the menu's language and falls back to English")
    func orderLine() {
        #expect(Phrasebook.orderLine(language: "it") == "Vorrei ordinare")
        #expect(Phrasebook.orderLine(language: "en") == "I'd like to order")
        #expect(Phrasebook.orderLine(language: "sv") == "I'd like to order")
        #expect(Phrasebook.orderLine(language: "zh-CN") == Phrasebook.tables["zh-Hans"]?.order)
    }

    @Test("An Italian menu is recognised from its name and from its dishes")
    func italianDetected() {
        #expect(Phrasebook.language(for: menu(languages: ["Italian"], names: [])) == "it")
        #expect(Phrasebook.language(for: menu(languages: ["it"], names: [])) == "it")
        // The on-device engine never fills detectedLanguages.
        let unnamed = menu(
            languages: [],
            names: ["Spaghetti alla carbonara", "Tagliatelle al ragù", "Insalata caprese", "Melanzane alla parmigiana", "Tiramisù"],
            sections: ["Primi piatti"]
        )
        #expect(Phrasebook.language(for: unnamed) == "it")
    }

    @Test("Nothing to say gives no card")
    func nothingToSay() {
        #expect(Phrasebook.waiterLine(allergens: [], diet: .omnivore, language: "it") == nil)
        #expect(Phrasebook.waiterLine(allergens: [" "], diet: .omnivore, language: "it") == nil)
    }

    @Test("Two allergies in Italian")
    func italianAllergies() throws {
        let line = try #require(Phrasebook.waiterLine(allergens: ["Peanuts", "Dairy"], diet: .omnivore, language: "it"))
        #expect(line.local.contains("arachidi"))
        #expect(line.local.contains("latticini"))
        #expect(line.local.contains(" e "))
        #expect(!line.local.contains("{"))
        #expect(line.english.contains("peanuts"))
        #expect(line.english.contains("dairy"))
        #expect(line.english.contains("any of these"))
    }

    @Test("One allergy uses the singular sentence")
    func singular() throws {
        let line = try #require(Phrasebook.waiterLine(allergens: ["Gluten"], diet: .omnivore, language: "es"))
        #expect(line.local.contains("gluten"))
        #expect(!line.local.contains("alguno"))
        #expect(line.english == "I'm allergic to gluten. Does this contain gluten?")
    }

    @Test("A custom allergen is carried over verbatim")
    func customVerbatim() throws {
        let line = try #require(Phrasebook.waiterLine(allergens: ["kiwi"], diet: .omnivore, language: "fr"))
        #expect(line.local.contains("kiwi"))
        #expect(line.english.contains("kiwi"))
        let mixed = try #require(Phrasebook.waiterLine(allergens: ["Peanuts", "kiwi"], diet: .omnivore, language: "de"))
        #expect(mixed.local.contains("Erdnüsse"))
        #expect(mixed.local.contains("kiwi"))
    }

    @Test("English gives the same sentence in both halves")
    func englishIdentical() throws {
        let line = try #require(Phrasebook.waiterLine(allergens: ["Shellfish", "Eggs"], diet: .vegetarian, language: "en"))
        #expect(line.local == line.english)
        #expect(line.local.contains("shellfish and eggs"))
        #expect(line.local.contains("I'm vegetarian"))
    }

    @Test("An unknown language falls back to English in both halves")
    func unknownFallsBack() throws {
        let line = try #require(Phrasebook.waiterLine(allergens: ["Soy"], diet: .omnivore, language: "sv"))
        #expect(line.local == line.english)
        #expect(line.local.contains("soy"))
    }

    @Test("The diet line stands on its own")
    func dietOnly() throws {
        let line = try #require(Phrasebook.waiterLine(allergens: [], diet: .vegan, language: "ja"))
        #expect(line.local == Phrasebook.tables["ja"]?.diets[.vegan])
        #expect(line.english == "I'm vegan — no meat, fish, eggs or dairy.")
    }

    @Test("Codes are folded to the tables' keys")
    func codeFolding() throws {
        #expect(Phrasebook.language(for: menu(languages: ["pt-BR"], names: [])) == "pt")
        #expect(Phrasebook.language(for: menu(languages: ["IT"], names: [])) == "it")
        #expect(Phrasebook.language(for: menu(languages: ["Traditional Chinese"], names: [])) == "zh-Hant")
        let line = try #require(Phrasebook.waiterLine(allergens: ["Fish"], diet: .omnivore, language: "zh-CN"))
        #expect(line.local.contains("鱼"))
    }

    @Test("Right-to-left tables join with an attached 'and'")
    func hebrewJoins() throws {
        let line = try #require(Phrasebook.waiterLine(allergens: ["Peanuts", "Dairy"], diet: .omnivore, language: "he"))
        #expect(line.local.contains("בוטנים ומוצרי חלב"))
    }
}
