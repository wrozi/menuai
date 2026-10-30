//
//  GoalTests.swift
//  menuaiTests
//
//  The eating goal is a soft nudge on the ranking. These pin two things: that
//  it moves dishes the way the diner asked, and that it never does anything
//  the safety chain does — no goal can block a dish or add a warning, and no
//  goal at all leaves every score exactly where it was.
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

private func profile(goal: EatingGoal = .none, goalNote: String = "") -> UserPreferences {
    var prefs = UserPreferences()
    prefs.goal = goal
    prefs.goalNote = goalNote
    return prefs
}

private func scored(_ dish: Dish, _ prefs: UserPreferences, source: String = "") -> Dish {
    DishScorer.score(dish, prior: 50, sourceText: source, preferences: prefs, memory: TasteMemory(orders: []))
}

@Suite("Eating goal")
struct GoalTests {
    @Test("Eating well lifts a salad over a fry-up")
    func healthyPrefersFresh() {
        let prefs = profile(goal: .healthy)
        let salad = scored(dish("Rocket salad", original: "Insalata di rucola", ingredients: ["rocket", "parmesan"]), prefs)
        let fried = scored(dish("Mixed fried seafood", original: "Fritto misto", ingredients: ["squid", "prawns"]), prefs)
        #expect(salad.matchScore > fried.matchScore)
        #expect(salad.matchReason.contains("fresh pick") || salad.matchScore > 50)
    }

    @Test("Keeping it light penalises a heavy dish, and fuelling up lifts it")
    func lightAndHeartyDisagreeAboutTheFryUp() {
        let fried = dish("Mixed fried seafood", original: "Fritto misto", ingredients: ["squid", "prawns"])
        let baseline = scored(fried, profile()).matchScore
        let light = scored(fried, profile(goal: .light))
        let hearty = scored(fried, profile(goal: .hearty))
        #expect(light.matchScore < baseline)
        #expect(hearty.matchScore > baseline)
        #expect(light.matchReason.contains("a heavy one"))
        #expect(hearty.matchReason.contains("proper plateful"))
    }

    @Test("More protein lifts grilled chicken")
    func proteinLiftsChicken() {
        let chicken = dish("Grilled chicken", original: "Pollo alla griglia", ingredients: ["chicken", "rosemary"])
        let baseline = scored(chicken, profile()).matchScore
        let lifted = scored(chicken, profile(goal: .protein))
        #expect(lifted.matchScore > baseline)
        #expect(lifted.matchReason.contains("packs protein"))
    }

    @Test("A goal note is a penalty, never a warning")
    func goalNoteLowersWithoutBlocking() {
        let tiramisu = dish("Tiramisu", original: "Tiramisù", ingredients: ["mascarpone", "sugar", "coffee"])
        let plain = scored(tiramisu, profile())
        let noted = scored(tiramisu, profile(goalNote: "no sugar"))
        #expect(noted.warnings.isEmpty, "a goal is not a rule")
        #expect(!noted.isBlocked)
        #expect(plain.matchScore - noted.matchScore == 10)
    }

    @Test("Softer phrasing in the goal note still counts")
    func softGoalNotePhrasingCounts() {
        let carbonara = dish("Carbonara", original: "Spaghetti alla carbonara", ingredients: ["pecorino cheese", "egg", "guanciale"])
        let plain = scored(carbonara, profile())
        let noted = scored(carbonara, profile(goalNote: "less cheese please"))
        #expect(noted.warnings.isEmpty)
        #expect(plain.matchScore - noted.matchScore == 10)
        #expect(DishScorer.softAvoidTerms(fromGoalNote: "low carb, no sugar") == ["sugar", "carb"] || DishScorer.softAvoidTerms(fromGoalNote: "low carb, no sugar").sorted() == ["carb", "sugar"])
    }

    @Test("No goal changes nothing")
    func noGoalIsInert() {
        var explicit = UserPreferences()
        explicit.goal = .none
        explicit.goalNote = ""
        for sample in [
            dish("Rocket salad", original: "Insalata di rucola", ingredients: ["rocket"]),
            dish("Mixed fried seafood", original: "Fritto misto", ingredients: ["squid"]),
            dish("Tiramisu", original: "Tiramisù", ingredients: ["mascarpone", "sugar"]),
        ] {
            let before = scored(sample, UserPreferences())
            let after = scored(sample, explicit)
            #expect(before.matchScore == after.matchScore)
            #expect(before.matchReason == after.matchReason)
            #expect(before.matchScore == 50, "the goal stage must add exactly nothing without a goal")
        }
    }

    @Test("Scored dishes always carry a health and heaviness reading")
    func scorerFillsTheBlanks() {
        let result = scored(dish("Mixed fried seafood", original: "Fritto misto"), profile())
        #expect(result.heaviness == 3)
        #expect(result.healthScore != nil)
        #expect(result.heavinessLabel == "Hearty")
    }

    @Test("Fried food reads as hearty")
    func friedIsHeavy() {
        #expect(DishScorer.estimatedHeaviness(for: dish("Mixed fried seafood", original: "Fritto misto")) == 3)
    }

    @Test("A salad reads as healthy")
    func saladIsHealthy() {
        #expect(DishScorer.estimatedHealth(for: dish("Salad", original: "Insalata")) >= 7)
    }

    @Test("The goal reaches the engines' prompt only when set")
    func goalAppearsInPrompt() {
        #expect(!profile().promptDescription.contains("Goal:"))
        let prefs = profile(goal: .healthy, goalNote: "low carb")
        #expect(prefs.promptDescription.contains("Goal: eat well"))
        #expect(prefs.promptDescription.contains("In their own words: low carb"))
        #expect(prefs.tasteOnlyDescription.contains("Goal: eat well"))
    }

    @Test("Companions never inherit the goal")
    func companionsHaveNoGoal() {
        let companion = Diner(name: "Sam")
        let prefs = companion.preferences(inheriting: profile(goal: .light, goalNote: "no sugar"))
        #expect(prefs.goal == .none)
        #expect(prefs.goalNote.isEmpty)
    }
}

@Suite("Fish by menu name")
struct FishByNameTests {
    private func profile() -> UserPreferences {
        var p = UserPreferences(); p.diet = .vegetarian; return p
    }
    private func scored(_ name: String, original: String, ingredients: [String]) -> Dish {
        let dish = Dish(originalName: original, translatedName: name, pronunciation: "", description: "", price: "",
                        cuisine: "Italian", ingredients: ingredients, allergens: [], dietaryTags: [], spiceLevel: 0,
                        matchScore: 60, matchReason: "", warnings: [], imageSearchQuery: "")
        return DishScorer.score(dish, prior: 60, preferences: profile(), memory: TasteMemory(orders: []))
    }

    @Test("Sea bass, bream and trout are fish even when 'fish' is never printed")
    func regionalFishNamesBlockForVegetarians() {
        #expect(scored("Oven-baked sea bass", original: "Branzino al forno", ingredients: ["sea bass", "lemon"]).isBlocked)
        #expect(scored("Grilled bream", original: "Orata alla griglia", ingredients: ["orata"]).isBlocked)
        #expect(scored("Trout with almonds", original: "Trucha con almendras", ingredients: ["trucha"]).isBlocked)
    }

    @Test("Sun-dried tomatoes are not sole")
    func soleTheSunIsNotFish() {
        #expect(!scored("Sun-dried tomatoes", original: "Pomodori secchi al sole", ingredients: ["tomato"]).isBlocked)
    }
}

@Suite("Goal compatibility")
struct GoalCompatibilityTests {
    @Test("Preferences saved before the goal existed still load")
    func oldPreferencesDecode() throws {
        let json = """
        {"displayLanguage":"en","diet":"vegetarian","allergies":["Peanuts"],"dislikes":[],
         "lovedCuisines":["Thai"],"spiceTolerance":2,"adventurousness":1,"notes":"no raw fish",
         "hasCompletedOnboarding":true}
        """
        let prefs = try JSONDecoder().decode(UserPreferences.self, from: Data(json.utf8))
        #expect(prefs.goal == .none)
        #expect(prefs.goalNote.isEmpty)
        #expect(prefs.diet == .vegetarian)
        #expect(prefs.hasCompletedOnboarding)
    }

    @Test("Preferences round-trip with the goal")
    func preferencesRoundTrip() throws {
        let prefs = profile(goal: .protein, goalNote: "low carb")
        let data = try JSONEncoder().encode(prefs)
        let back = try JSONDecoder().decode(UserPreferences.self, from: data)
        #expect(back == prefs)
    }

    @Test("Menus saved before the health fields existed still load")
    func oldDishDecodes() throws {
        let json = """
        {"originalName":"Tiramisù","translatedName":"Tiramisu","pronunciation":"","description":"",
         "price":"€8","cuisine":"Italian","ingredients":["mascarpone"],"allergens":["dairy"],
         "dietaryTags":[],"spiceLevel":0,"matchScore":70,"matchReason":"Safe bet.","warnings":[],
         "imageSearchQuery":"tiramisu"}
        """
        let dish = try JSONDecoder().decode(Dish.self, from: Data(json.utf8))
        #expect(dish.healthScore == nil)
        #expect(dish.heaviness == nil)
        #expect(dish.heavinessLabel == nil)
        #expect(dish.matchScore == 70)
    }

    @Test("A dish round-trips its health fields")
    func dishRoundTrip() throws {
        var sample = dish("Tiramisu", original: "Tiramisù")
        sample.healthScore = 3
        sample.heaviness = 3
        let data = try JSONEncoder().encode(sample)
        let back = try JSONDecoder().decode(Dish.self, from: data)
        #expect(back.healthScore == 3)
        #expect(back.heaviness == 3)
        #expect(back.heavinessLabel == "Hearty")
    }

    @Test("Snake-case fields from the Claude engine map onto the dish")
    func snakeCaseDecodes() throws {
        let json = """
        {"original_name":"Tiramisù","translated_name":"Tiramisu","pronunciation":"","description":"",
         "price":"€8","cuisine":"Italian","ingredients":[],"allergens":[],"dietary_tags":[],
         "spice_level":0,"match_score":70,"match_reason":"","warnings":[],"image_search_query":"",
         "health_score":2,"heaviness":3}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dish = try decoder.decode(Dish.self, from: Data(json.utf8))
        #expect(dish.healthScore == 2)
        #expect(dish.heaviness == 3)
    }

    @Test("Every goal has a label, a detail and a choice row")
    func goalChoicesLineUp() {
        #expect(EatingGoal.choices.count == EatingGoal.allCases.count)
        for (goal, choice) in zip(EatingGoal.allCases, EatingGoal.choices) {
            #expect(choice.0 == goal.label)
            #expect(choice.1 == goal.detail)
            #expect(choice.2 == goal.icon)
            #expect(!goal.label.contains("!"))
        }
    }
}
