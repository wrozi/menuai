//
//  AllergenSafetyTests.swift
//  menuaiTests
//
//  The allergen matcher is the one part of this app that can hurt somebody by
//  being wrong, in either direction: a miss puts an allergen on the plate, and
//  a false alarm on a safe dish teaches people to ignore the warnings.
//
//  Every case here is a real bug found while testing against actual menus, so
//  the suite is a record of what has already gone wrong once.
//

import Foundation
import Testing
@testable import menuai

private func dish(
    _ name: String,
    original: String = "",
    description: String = "",
    ingredients: [String] = [],
    cuisine: String = "Italian"
) -> Dish {
    Dish(
        originalName: original.isEmpty ? name : original,
        translatedName: name,
        pronunciation: "",
        description: description,
        price: "",
        cuisine: cuisine,
        ingredients: ingredients,
        allergens: [],
        dietaryTags: [],
        spiceLevel: 0,
        matchScore: 50,
        matchReason: "",
        warnings: [],
        imageSearchQuery: ""
    )
}

private func profile(
    allergies: [String] = [],
    diet: Diet = .omnivore,
    dislikes: [String] = [],
    notes: String = "",
    spice: Int = 1
) -> UserPreferences {
    var prefs = UserPreferences()
    prefs.allergies = allergies
    prefs.diet = diet
    prefs.dislikes = dislikes
    prefs.notes = notes
    prefs.spiceTolerance = spice
    return prefs
}

private func scored(_ dish: Dish, _ prefs: UserPreferences, source: String = "") -> Dish {
    DishScorer.score(dish, prior: 50, sourceText: source, preferences: prefs, memory: TasteMemory(orders: []))
}

@Suite("Allergen matching")
struct AllergenSafetyTests {
    // MARK: - Must catch

    @Test("Catches an allergen named in the ingredients")
    func catchesIngredient() {
        let result = scored(
            dish("Prawn linguine", ingredients: ["prawns", "garlic", "chilli"]),
            profile(allergies: ["Shellfish"])
        )
        #expect(result.isBlocked)
        #expect(result.matchScore <= 10)
    }

    @Test("Catches an allergen only present in the printed menu line")
    func catchesFromSourceText() {
        // The model dropped the pistachios from its output on some runs; the
        // printed menu still said "pistacchi".
        let result = scored(
            dish("Burrata with Mortadella", original: "Burrata con Mortadella", ingredients: ["burrata", "mortadella"]),
            profile(allergies: ["Tree nuts"]),
            source: "Burrata con Mortadella burrata pugliese, pistacchi € 14"
        )
        #expect(result.isBlocked, "Italian 'pistacchi' must trip a tree-nut allergy")
    }

    @Test("Matches foreign spellings, not just English", arguments: [
        ("Gamberi in Padella", "gamberi rossi, aglio", "Shellfish"),
        ("Torta di Nocciole", "nocciole piemontesi", "Tree nuts"),
        ("Zuppa di Sedano", "sedano, patate", "Celery"),
        ("Tagliatelle", "farina, uova", "Gluten"),
    ])
    func matchesForeignSpellings(name: String, line: String, allergy: String) {
        let result = scored(dish(name, original: name), profile(allergies: [allergy]), source: "\(name) \(line)")
        #expect(result.isBlocked, "'\(line)' should trip \(allergy)")
    }

    // MARK: - Must NOT catch
    //
    // Short stems used to match inside longer, unrelated words.

    @Test("Aubergine does not trip an egg allergy")
    func eggplantIsNotEgg() {
        let result = scored(
            dish("Eggplant parmigiana", ingredients: ["eggplant", "tomato", "basil"]),
            profile(allergies: ["Eggs"])
        )
        #expect(!result.isBlocked, "'eggplant' contains 'egg' but is not an egg")
    }

    @Test("Nutmeg does not trip a tree-nut allergy")
    func nutmegIsNotANut() {
        let result = scored(
            dish("Spinach gratin", ingredients: ["spinach", "nutmeg", "cream"]),
            profile(allergies: ["Tree nuts"])
        )
        #expect(!result.isBlocked, "'nutmeg' contains 'nut' but is not a nut")
    }

    @Test("A dish cooked in a pan does not trip a gluten allergy")
    func panIsNotBread() {
        // "pan " was in the gluten list as Spanish for bread, and matched the
        // English word in "Shrimp in Pan".
        let result = scored(
            dish("Shrimp in Pan", original: "Gamberi in Padella", ingredients: ["shrimp", "garlic", "parsley"]),
            profile(allergies: ["Gluten"])
        )
        #expect(!result.isBlocked, "a pan is not bread")
    }

    @Test("Peeled prawns do not trip a fish allergy")
    func peeledIsNotEel() {
        let result = scored(
            dish("Peeled prawns", ingredients: ["peeled prawns", "lemon"]),
            profile(allergies: ["Fish"])
        )
        #expect(!result.isBlocked, "'peeled' contains 'eel' but is not an eel")
    }

    // MARK: - Diet

    @Test("Meat is blocked for a vegetarian, with the reason named")
    func vegetarianBlocksMeat() {
        let result = scored(
            dish("Saltimbocca", ingredients: ["veal", "prosciutto", "sage"]),
            profile(diet: .vegetarian)
        )
        #expect(result.isBlocked)
        #expect(result.warnings.first?.contains("veal") == true)
    }

    @Test("A vegetable dish is fine for a vegetarian")
    func vegetarianAllowsVegetables() {
        let result = scored(
            dish("Carciofi alla Giudia", ingredients: ["artichokes", "salt", "olive oil"]),
            profile(diet: .vegetarian)
        )
        #expect(!result.isBlocked)
    }

    @Test("Pork is not halal")
    func halalBlocksPork() {
        let result = scored(
            dish("Amatriciana", ingredients: ["guanciale", "tomato", "pecorino"]),
            profile(diet: .halal)
        )
        #expect(result.isBlocked)
    }

    // MARK: - Dislikes are a penalty, not a block

    @Test("A disliked ingredient lowers the score without blocking the dish")
    func dislikesPenaliseButDoNotBlock() {
        let liked = scored(dish("Oxtail stew", ingredients: ["oxtail", "tomato"]), profile(dislikes: ["celery"]))
        let disliked = scored(
            dish("Coda alla Vaccinara", ingredients: ["oxtail", "celery", "cocoa"]),
            profile(dislikes: ["celery"])
        )
        #expect(!disliked.isBlocked, "a dislike is not an allergy")
        #expect(disliked.matchScore < liked.matchScore)
    }

    @Test("Dislikes match foreign spellings too")
    func dislikesMatchForeignSpellings() {
        let result = scored(
            dish("Coda alla Vaccinara", original: "Coda alla Vaccinara", ingredients: ["coda di bue"]),
            profile(dislikes: ["celery"]),
            source: "Coda alla Vaccinara coda di bue, sedano, cacao"
        )
        #expect(result.matchScore < 50, "Italian 'sedano' should register as celery")
    }

    // MARK: - Warning wording

    @Test("Warnings quote the word printed on the menu, not the internal stem")
    func warningsQuoteThePrintedWord() {
        let result = scored(
            dish("Burrata", original: "Burrata con Mortadella"),
            profile(allergies: ["Tree nuts"]),
            source: "Burrata con Mortadella burrata pugliese, pistacchi"
        )
        let warning = try? #require(result.warnings.first)
        #expect(warning?.contains("pistacchi") == true, "should say 'pistacchi', not 'pistac'")
        #expect(warning?.contains("pistac ") != true)
    }
}

@Suite("Menu assembly")
struct MenuAssemblyTests {
    @Test("Overlapping chunks repeat lines so a split dish survives")
    func chunksOverlap() {
        let transcript = (1 ... 60).map { "Dish number \($0) with a description € \($0)" }.joined(separator: "\n")
        let chunks = OnDeviceEngine.chunk(transcript)
        #expect(chunks.count > 1)
        for (a, b) in zip(chunks, chunks.dropFirst()) {
            let tail = a.components(separatedBy: .newlines).suffix(2)
            let head = b.components(separatedBy: .newlines)
            #expect(tail.contains { head.contains($0) }, "each chunk should re-open with the previous one's tail")
        }
    }

    @Test("Deduplication keeps the richer copy and merges the evidence")
    func dedupeMergesEvidence() {
        let sparse = ParsedDish(
            dish: dish("Burrata", original: "Burrata con Mortadella"),
            notability: 50,
            sourceText: "Burrata con Mortadella"
        )
        var richDish = dish("Burrata with Mortadella", original: "Burrata con Mortadella", ingredients: ["burrata", "mortadella"])
        richDish.allergens = ["dairy"]
        let rich = ParsedDish(dish: richDish, notability: 70, sourceText: "burrata pugliese, pistacchi")

        let result = OnDeviceEngine.deduplicate([sparse, rich])
        #expect(result.count == 1, "same printed name is the same dish")
        #expect(result[0].sourceText.contains("pistacchi"), "evidence from the dropped copy must survive")
    }

    @Test("Price lines and headings are not mistaken for dishes")
    func junkIsRejected() {
        let junk = [
            ParsedDish(dish: dish("€ 22", original: "€ 22"), notability: 50, sourceText: ""),
            ParsedDish(dish: dish("ANTIPASTI", original: "ANTIPASTI"), notability: 50, sourceText: ""),
            ParsedDish(dish: dish("Carbonara", original: "Carbonara", ingredients: ["egg"]), notability: 50, sourceText: ""),
        ]
        let result = OnDeviceEngine.deduplicate(junk)
        #expect(result.count == 1)
        #expect(result[0].dish.displayName == "Carbonara")
    }

    @Test("A missing currency symbol is restored from the menu")
    func pricesRegainTheirCurrency() {
        var bare = dish("Tiramisu", original: "Tiramisu")
        bare.price = "9"
        let result = OnDeviceEngine.normalisePrices(
            [ParsedDish(dish: bare, notability: 50, sourceText: "")],
            fallback: "€"
        )
        #expect(result[0].dish.price == "€9")
    }

    @Test("A dish's own menu line is attributed to it, not its neighbour's")
    func sourceSnippetIsPerDish() {
        let chunk = """
        Gamberi in Padella
        gamberi rossi, aglio, prezzemolo
        Carciofi alla Giudia
        carciofi fritti, sale
        """
        let snippet = OnDeviceEngine.sourceSnippet(
            for: dish("Jewish-style artichokes", original: "Carciofi alla Giudia"),
            in: chunk
        )
        #expect(snippet.contains("carciofi"))
        #expect(!snippet.contains("gamberi"), "one dish's shellfish must not leak onto another")
    }
}


@Suite("Religious diets")
struct ReligiousDietTests {
    @Test("Cooking wine is flagged for a halal diner", arguments: [
        "Coq au vin", "Risotto al Marsala", "Penne alla Vodka",
    ])
    func halalFlagsCookingAlcohol(name: String) {
        let result = scored(dish(name, original: name), profile(diet: .halal))
        #expect(result.isBlocked, "\(name) is cooked with alcohol")
    }

    @Test("Cured pork is flagged for a halal diner whatever it's called", arguments: [
        "guanciale", "prosciutto", "speck", "chorizo", "mortadella", "lardo",
    ])
    func halalFlagsCuredPork(ingredient: String) {
        let result = scored(dish("Antipasto", ingredients: [ingredient]), profile(diet: .halal))
        #expect(result.isBlocked, "\(ingredient) is pork")
    }

    @Test("Gelatin is queried rather than assumed safe")
    func gelatinIsQueried() {
        let result = scored(
            dish("Panna cotta", ingredients: ["cream", "gelatin", "vanilla"]),
            profile(diet: .halal)
        )
        #expect(result.isBlocked)
        #expect(result.warnings.first?.contains("ask before ordering") == true)
    }

    @Test("Fish without fins and scales is flagged for a kosher diner")
    func kosherFlagsNonKosherFish() {
        let result = scored(dish("Grilled swordfish", ingredients: ["swordfish", "lemon"]), profile(diet: .kosher))
        #expect(result.isBlocked)
    }

    @Test("Meat and dairy together is flagged for a kosher diner, naming both")
    func kosherFlagsMeatWithDairy() {
        let result = scored(
            dish("Veal parmigiana", ingredients: ["veal", "mozzarella", "tomato"]),
            profile(diet: .kosher)
        )
        #expect(result.isBlocked)
        let warning = result.warnings.first ?? ""
        #expect(warning.contains("veal"), "should name the meat")
        #expect(warning.contains("Mixes"), "should say why the combination is the problem")
    }

    @Test("Meat that clears the rules is still not presented as verified")
    func kosherMeatIsCaveated() {
        let meat = scored(dish("Grilled lamb", ingredients: ["lamb", "rosemary"]), profile(diet: .kosher))
        let veg = scored(dish("Artichokes", ingredients: ["artichokes", "olive oil"]), profile(diet: .kosher))
        #expect(!meat.isBlocked, "lamb is a kosher species — the menu just can't prove the preparation")
        #expect(meat.matchScore < veg.matchScore, "the unverifiable dish should rank below the one with nothing to verify")
        #expect(meat.matchReason.contains("checking") || meat.matchReason.contains("kitchen"))
    }
}

@Suite("Free-text notes")
struct NotesTests {
    @Test("Extracts things to avoid from ordinary phrasing", arguments: [
        ("No raw fish please", "raw"),
        ("I'm pregnant, avoid unpasteurised cheese", "unpasteurised"),
        ("can't eat gelatin", "gelatin"),
        ("Allergic to kiwi", "kiwi"),
    ])
    func extractsAvoidTerms(notes: String, expected: String) {
        #expect(DishScorer.avoidTerms(fromNotes: notes).contains(expected))
    }

    @Test("Does not harvest things the diner said they like")
    func doesNotHarvestPositives() {
        let terms = DishScorer.avoidTerms(fromNotes: "I love garlic and really like anchovies")
        #expect(terms.isEmpty, "only explicit avoid phrasing should count")
    }

    @Test("A dish matching a note is flagged")
    func notesBlockMatchingDishes() {
        let result = scored(
            dish("Steak tartare", ingredients: ["raw beef", "egg yolk", "capers"]),
            profile(notes: "I'm pregnant so no raw meat or unpasteurised cheese")
        )
        #expect(result.isBlocked)
        #expect(result.warnings.first?.contains("asked us to avoid") == true)
    }

    @Test("Notes leave unrelated dishes alone")
    func notesDoNotOverreach() {
        let result = scored(
            dish("Margherita pizza", ingredients: ["tomato", "mozzarella", "basil"]),
            profile(notes: "no raw fish")
        )
        #expect(!result.isBlocked)
    }
}

@Suite("Ranking reflects the diner")
struct RankingTests {
    @Test("A vegetable-led dish outranks a technically-meatless one for a vegetarian")
    func plantForwardDishesRankHigher() {
        let hero = scored(
            dish("Melanzane alla Parmigiana", ingredients: ["aubergine", "tomato", "basil"]),
            profile(diet: .vegetarian)
        )
        let filler = scored(
            dish("Mixed leaves", ingredients: ["lettuce", "oil"]),
            profile(diet: .vegetarian)
        )
        #expect(hero.matchScore > filler.matchScore)
    }

    @Test("A dish too spicy for the diner ranks below one that suits them")
    func spiceMismatchIsPenalised() {
        var fiery = dish("Diavola", ingredients: ["salami", "chilli"])
        fiery.spiceLevel = 3
        var mild = dish("Margherita", ingredients: ["tomato", "mozzarella"])
        mild.spiceLevel = 0

        let prefs = profile(spice: 0)
        #expect(scored(fiery, prefs).matchScore < scored(mild, prefs).matchScore)
    }

    @Test("Preferences outweigh how celebrated a dish is")
    func preferencesBeatNotability() {
        let prefs = profile(dislikes: ["mushrooms"])
        // A famous dish the diner has said they don't want...
        let famousButUnwanted = DishScorer.score(
            dish("Tagliatelle ai Funghi", ingredients: ["mushrooms", "butter"]),
            prior: 95,
            preferences: prefs,
            memory: TasteMemory(orders: [])
        )
        // ...against an ordinary one with nothing against it.
        let plainButFine = DishScorer.score(
            dish("Pomodoro", ingredients: ["tomato", "basil"]),
            prior: 45,
            preferences: prefs,
            memory: TasteMemory(orders: [])
        )
        #expect(plainButFine.matchScore > famousButUnwanted.matchScore,
                "a chooser that ignores what the diner told it is not a chooser")
    }

    @Test("A dish like one they rated highly ranks above an unrelated dish")
    func learnedTasteLifts() {
        let loved = OrderedDish(
            from: dish("Cacio e Pepe", ingredients: ["pasta", "pecorino", "pepper"]),
            restaurant: "Da Silvio",
            imageFileName: nil
        )
        var rated = loved
        rated.rating = 5
        let memory = TasteMemory(orders: [rated])

        let similar = DishScorer.score(
            dish("Tonnarelli Cacio", ingredients: ["pasta", "pecorino", "butter"]),
            prior: 50, preferences: profile(), memory: memory
        )
        let unrelated = DishScorer.score(
            dish("Mixed salad", ingredients: ["lettuce", "cucumber"]),
            prior: 50, preferences: profile(), memory: memory
        )
        #expect(similar.matchScore > unrelated.matchScore)
    }
}
