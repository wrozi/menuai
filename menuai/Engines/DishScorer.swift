//
//  DishScorer.swift
//  menuai
//
//  Deterministic scoring and safety checking.
//
//  Two jobs. For the on-device engine it does all the scoring, because a 3B
//  parameter model is good at saying what a dish IS and bad at weighing it
//  against a profile. For the Claude engine it runs afterwards as a safety
//  net: Claude scores, then this re-checks every dish against the stated
//  allergies and diet and adds any warning Claude missed. An allergy check
//  should never be a thing a language model can silently get wrong.
//

import Foundation

enum DishScorer {
    // MARK: - Lexicon
    //
    // Maps an allergy the user typed to the words that betray it on a menu.
    // Deliberately generous: a false positive costs a user one annoyed
    // glance, a false negative costs them an epi-pen.

    private static let allergenTerms: [String: [String]] = [
        "peanuts": ["peanut", "groundnut", "arachid", "cacahu", "erdnuss", "satay", "sate"],
        "tree nuts": ["almond", "mandorl", "amandel", "amêndoa", "amend", "cashew", "anacard",
                      "walnut", "noce", "noci", "nuez", "nuss", "pecan", "pistac", "pistaz",
                      "hazelnut", "nocciol", "avellan", "haselnuss", "noisette",
                      "macadamia", "praline", "marzipan", "marzapane", "nut", "noix",
                      "frangipane", "nougat", "torrone"],
        "dairy": ["milk", "latte", "leche", "lait", "milch", "cream", "panna", "crema",
                  "butter", "burro", "beurre", "cheese", "formagg", "queso", "fromage",
                  "käse", "kase", "yoghurt", "yogurt", "ghee", "parmesan", "parmigian",
                  "mozzarella", "ricotta", "mascarpone", "pecorino", "gorgonzola",
                  "custard", "béchamel", "bechamel", "paneer", "feta", "burrata",
                  "stracciatella", "crème", "creme", "gelato", "ice cream"],
        "eggs": ["egg", "uovo", "uova", "huevo", "oeuf", "œuf", "mayonnaise",
                 "mayo", "aioli", "meringue", "meringa", "hollandaise", "custard",
                 "frittata", "omelette", "omelet", "carbonara", "tortilla española"],
        "gluten": ["wheat", "grano", "trigo", "blé", "weizen", "flour", "farina",
                   "harina", "bread", "pane", "pain", "brot", "pasta",
                   "spaghett", "tonnarell", "penne", "linguin", "tagliatell",
                   "noodle", "barley", "orzo", "rye", "segale", "couscous",
                   "semolina", "semolino", "breaded", "impanat", "batter", "crouton",
                   "seitan", "bun", "tortilla", "pastry", "dumpling", "soy sauce",
                   "panko", "savoiard", "ladyfinger", "biscott", "torta", "cake",
                   "crostin", "bruschett", "focacc", "pizza"],
        "shellfish": ["shrimp", "gamber", "camarón", "camaron", "crevette", "garnele",
                      "prawn", "scampi", "crab", "granchio", "cangrejo", "crabe",
                      "lobster", "aragosta", "langosta", "homard", "crayfish",
                      "langoustine", "clam", "vongol", "almeja", "palourde",
                      "mussel", "cozze", "mejillón", "mejillon", "moule",
                      "oyster", "ostrica", "ostra", "huître", "huitre",
                      "scallop", "capesante", "vieira", "squid", "calamar",
                      "seppia", "octopus", "polpo", "pulpo", "poulpe",
                      "frutti di mare", "mariscos", "snail", "lumache", "escargot"],
        "fish": ["fish", "pesce", "pescado", "poisson", "fisch", "salmon", "salmone",
                 "saumon", "tuna", "tonno", "atún", "atun", "thon", "cod", "merluzz",
                 "bacalao", "morue", "anchov", "acciug", "alici", "anchoa",
                 "sardine", "sardina", "mackerel", "sgombro", "trout", "trota",
                 "bass", "branzino", "spigola", "halibut", "herring", "aringa",
                 "anguilla", "caviar", "caviale", "bottarga",
                 "fish sauce", "nam pla", "worcestershire", "bonito", "dashi",
                 "colatura"],
        "soy": ["soy", "soja", "soia", "tofu", "edamame", "miso", "tempeh",
                "tamari", "ponzu"],
        "sesame": ["sesame", "sesamo", "sésamo", "sésame", "tahini", "tahina",
                   "hummus", "halva", "za'atar", "zaatar", "gomashio"],
        "mustard": ["mustard", "senape", "mostaza", "moutarde", "dijon", "senf"],
        "celery": ["celery", "sedano", "apio", "céleri", "celeri", "sellerie",
                   "celeriac"],
        "sulfites": ["wine", "vino", "vin", "wein", "vinegar", "aceto", "vinagre",
                     "vinaigre", "dried fruit", "sulfite", "sulphite", "solfit"],
    ]

    private static let meatTerms = [
        "beef", "pork", "lamb", "chicken", "duck", "veal", "bacon", "ham", "sausage",
        "steak", "mutton", "goat", "rabbit", "venison", "turkey", "quail", "chorizo",
        "salami", "prosciutto", "pancetta", "meat", "brisket", "oxtail", "tripe",
        "liver", "foie gras", "pastrami", "pepperoni", "guanciale", "lardo",
    ]

    private static let porkTerms = [
        "pork", "maiale", "cerdo", "porc", "schwein", "bacon", "ham", "jamon",
        "jambon", "prosciutto", "speck", "pancetta", "chorizo", "salami",
        "salame", "lardo", "lard", "strutto", "saindoux", "guanciale",
        "pepperoni", "boar", "cinghiale", "gammon", "hog", "mortadella",
        "coppa", "capocollo", "bratwurst", "chourico", "morcilla",
    ]

    /// Alcohol used in cooking, not just on the drinks list.
    private static let alcoholTerms = [
        "wine", "vino", "vin", "wein", "beer", "birra", "cerveza", "biere",
        "rum", "vodka", "whisky", "whiskey", "brandy", "cognac", "marsala",
        "sherry", "vermouth", "sake", "mirin", "liqueur", "limoncello",
        "grappa", "amaretto", "kirsch", "calvados", "prosecco", "champagne",
        "bourbon", "tequila", "ouzo", "raki", "arak",
    ]

    /// Gelatin is the quiet one — it turns up in desserts and glazes and is
    /// usually pork-derived unless a kitchen says otherwise.
    private static let gelatinTerms = ["gelatin", "gelatine", "gelatina", "aspic", "marshmallow"]

    /// Fish without fins and scales, which are not kosher.
    private static let nonKosherFish = [
        "catfish", "eel", "anguilla", "sturgeon", "monkfish", "rana pescatrice",
        "shark", "swordfish", "pesce spada", "skate", "razza", "huss",
    ]

    private static let shellfishTerms = [
        "shrimp", "gamber", "prawn", "crab", "granchio", "lobster", "aragosta",
        "crayfish", "langoustine", "scampi", "clam", "vongol", "mussel",
        "cozze", "oyster", "ostrica", "scallop", "capesante", "squid",
        "calamar", "octopus", "polpo", "pulpo", "snail", "lumache", "escargot",
        "frutti di mare", "mariscos",
    ]

    // Fish by the names menus actually print. Stems under five characters
    // match whole words only, so "bass" is safe but "sole" is not (it is
    // Italian for sun — "pomodori al sole"), hence sogliola/lenguado instead.
    private static let seafoodTerms = [
        "fish", "salmon", "tuna", "cod", "shrimp", "prawn", "crab", "lobster",
        "clam", "mussel", "oyster", "scallop", "squid", "calamari", "octopus",
        "anchovy", "sardine", "mackerel", "eel", "seafood",
        // sea bass / bream / trout / hake / cod / sole / swordfish / turbot / monkfish / snapper / grouper / herring
        "bass", "branzin", "spigol", "lubina", "loup de mer", "bream", "orata", "dorad", "besugo",
        "trout", "trota", "truite", "trucha", "hake", "merluz", "cabillaud", "bacala", "baccal", "stockfish",
        "sogliol", "lenguado", "swordfish", "pesce spada", "espada", "espadon", "halibut", "turbot", "rombo", "rodaballo",
        "monkfish", "pescatrice", "lotte", "snapper", "grouper", "cernia", "mero", "tilapia", "carp", "carpa", "herring", "aring", "arenque", "hareng",
        // anchovies / cuttlefish / octopus / squid / prawns / lobster / crab / clams / mussels / oysters / scallops
        "acciug", "alici", "boqueron", "anchoa", "anchois", "seppi", "cuttlefish", "sepia", "polpo", "pulpo", "poulpe", "calamar",
        "gamber", "gamba", "langostin", "crevette", "aragosta", "homard", "bogavante", "granchio", "cangrejo", "crabe",
        "vongol", "almeja", "palourde", "cozze", "mejill", "moule", "ostric", "ostra", "huitre", "huître", "capesant", "vieira", "saint-jacques",
        // the generic words
        "salmone", "saumon", "salmón", "tonno", "atún", "atun", "thon", "merluzzo", "pesce", "poisson", "pescado", "marisco", "frutti di mare", "fruits de mer", "sashimi",
    ]

    private static let dairyTerms = allergenTerms["dairy"] ?? []
    private static let eggTerms = allergenTerms["eggs"] ?? []

    // MARK: - Entry points

    /// Full scoring pass. Used by the on-device engine.
    ///
    /// `prior` is the model's own read on how worth-ordering the dish is here,
    /// independent of who is eating. Without it every unremarkable dish of a
    /// cuisine the user likes lands on an identical score and the ranking
    /// stops meaning anything.
    static func score(
        _ dish: Dish,
        prior: Int,
        sourceText: String = "",
        preferences: UserPreferences,
        memory: TasteMemory
    ) -> Dish {
        var dish = dish

        // The goal nudge and the detail screen both want these; estimate
        // whatever the engine left blank so every scored dish carries a value.
        // Purely descriptive — nothing below reads them for safety.
        let evidence = searchText(for: dish) + " " + sourceText.lowercased()
        if dish.heaviness == nil { dish.heaviness = estimatedHeaviness(for: dish, haystack: evidence) }
        if dish.healthScore == nil { dish.healthScore = estimatedHealth(for: dish, haystack: evidence) }

        let warnings = safetyWarnings(for: dish, preferences: preferences, sourceText: sourceText)
        dish.warnings = warnings

        if !warnings.isEmpty {
            dish.matchScore = min(dish.matchScore, 8)
            dish.matchReason = warnings[0]
            return dish
        }

        let (score, reason) = fit(
            dish,
            prior: prior,
            sourceText: sourceText,
            preferences: preferences,
            memory: memory
        )
        dish.matchScore = score
        dish.matchReason = reason
        return dish
    }

    /// Safety-only pass. Used over Claude's output — keeps Claude's score and
    /// reason, but adds any allergy or diet conflict it failed to flag.
    static func applySafetyNet(
        _ dish: Dish,
        sourceText: String = "",
        preferences: UserPreferences
    ) -> Dish {
        var dish = dish
        guard dish.warnings.isEmpty else {
            // Claude already flagged it; just make sure the score reflects that.
            dish.matchScore = min(dish.matchScore, 8)
            return dish
        }

        let missed = safetyWarnings(for: dish, preferences: preferences, sourceText: sourceText)
        guard !missed.isEmpty else { return dish }

        dish.warnings = missed
        dish.matchScore = min(dish.matchScore, 8)
        return dish
    }

    // MARK: - Safety

    /// `sourceText` is the raw OCR for the part of the menu this dish came
    /// from. It matters: when the model omits an ingredient from its output —
    /// as it did with the pistachios in a burrata — the model-derived fields
    /// alone give no allergen to match, and the check silently passes a dish
    /// the user cannot eat. The printed menu still says "pistacchi".
    private static func safetyWarnings(
        for dish: Dish,
        preferences: UserPreferences,
        sourceText: String = ""
    ) -> [String] {
        var warnings: [String] = []
        let haystack = searchText(for: dish) + " " + sourceText.lowercased()

        // Allergies.
        for allergy in preferences.allergies {
            let key = allergy.lowercased()
            let terms = allergenTerms[key] ?? [key]
            if let stem = terms.first(where: { haystackContains($0, haystack) }) {
                let label = allergy.lowercased()
                // Show the word as it is printed on the menu, not the stem we
                // matched on — "pistacchi" is useful to read, "pistac" is not.
                let word = wholeWord(containing: stem, in: haystack)
                warnings.append(
                    word == label
                        ? "Likely contains \(label), which you're allergic to."
                        : "Likely contains \(word) — that's \(label), which you're allergic to."
                )
            }
        }

        // Diet.
        warnings.append(contentsOf: dietWarnings(for: dish, haystack: haystack, diet: preferences.diet))

        // Free-text notes finally do something on this path. "No raw fish",
        // "avoid coriander", "can't eat gelatin" — the field has always been
        // in Settings and until now only the Claude engine ever read it.
        for term in Self.avoidTerms(fromNotes: preferences.notes)
        where haystackContains(term, haystack) {
            warnings.append("Contains \(wholeWord(containing: term, in: haystack)) — you asked us to avoid that.")
        }

        return warnings
    }

    /// Every violation, not just the first. A vegan dish with both meat and
    /// cheese should say so; stopping at the first hit hides half the reason.
    private static func dietWarnings(for dish: Dish, haystack: String, diet: Diet) -> [String] {
        func hit(_ terms: [String]) -> String? {
            guard let stem = terms.first(where: { haystackContains($0, haystack) }) else { return nil }
            return wholeWord(containing: stem, in: haystack)
        }

        var warnings: [String] = []

        switch diet {
        case .omnivore:
            break

        case .vegetarian:
            if let found = hit(meatTerms) { warnings.append("Contains \(found) — you eat vegetarian.") }
            if let found = hit(seafoodTerms) { warnings.append("Contains \(found) — you eat vegetarian.") }

        case .vegan:
            if let found = hit(meatTerms) { warnings.append("Contains \(found) — you eat vegan.") }
            if let found = hit(seafoodTerms) { warnings.append("Contains \(found) — you eat vegan.") }
            if let found = hit(dairyTerms) { warnings.append("Contains \(found) — you eat vegan.") }
            if let found = hit(eggTerms) { warnings.append("Contains \(found) — you eat vegan.") }
            if let found = hit(["honey", "miele", "miel"]) { warnings.append("Contains \(found) — you eat vegan.") }

        case .pescatarian:
            if let found = hit(meatTerms) { warnings.append("Contains \(found) — you eat pescatarian.") }

        case .halal:
            if let found = hit(porkTerms) { warnings.append("Contains \(found) — pork isn't halal.") }
            if let found = hit(alcoholTerms) { warnings.append("Made with \(found) — alcohol isn't halal.") }
            if let found = hit(gelatinTerms) {
                warnings.append("Contains \(found), which is usually pork-derived — ask before ordering.")
            }

        case .kosher:
            if let found = hit(porkTerms) { warnings.append("Contains \(found) — pork isn't kosher.") }
            if let found = hit(shellfishTerms) { warnings.append("Contains \(found) — shellfish isn't kosher.") }
            if let found = hit(nonKosherFish) {
                warnings.append("Contains \(found), which has no fins and scales — not kosher.")
            }
            if let meat = hit(meatTerms), let dairy = hit(dairyTerms) {
                warnings.append("Mixes \(meat) with \(dairy) — meat and dairy together isn't kosher.")
            }
            if let found = hit(gelatinTerms) {
                warnings.append("Contains \(found), which is rarely kosher — ask before ordering.")
            }
        }

        return warnings
    }

    /// Pulls things to avoid out of the free-text notes.
    ///
    /// Only recognises explicit phrasing — "no X", "avoid X", "without X",
    /// "can't eat X". Harvesting every noun would flag half the menu off the
    /// back of a sentence like "I love garlic".
    static func avoidTerms(fromNotes notes: String) -> [String] {
        explicitTerms(
            in: notes,
            markers: ["no ", "avoid ", "without ", "can't eat ", "cannot eat ",
                      "cant eat ", "don't eat ", "dont eat ", "allergic to ",
                      "intolerant to ", "stay away from ", "not eating "]
        )
    }

    /// The goal note's softer phrasing — "less cheese", "low carb", "easy on
    /// the cream" — on top of the hard "no X" forms. These only ever cost a
    /// dish points; they never block it.
    static func softAvoidTerms(fromGoalNote note: String) -> [String] {
        let soft = explicitTerms(
            in: note,
            markers: ["less ", "low ", "lower ", "fewer ", "light on ",
                      "easy on ", "not much ", "cut down on ", "go easy on "]
        )
        var terms = avoidTerms(fromNotes: note)
        for term in soft where !terms.contains(term) { terms.append(term) }
        return terms
    }

    private static func explicitTerms(in notes: String, markers: [String]) -> [String] {
        let text = notes.lowercased()
        guard !text.isEmpty else { return [] }
        let stopWords: Set<String> = ["the", "any", "all", "and", "or", "with",
                                      "please", "thanks", "too", "much", "very",
                                      "really", "sort", "kind", "type", "of",
                                      "at", "in", "on", "for", "more", "some",
                                      "that", "this", "them", "they", "its"]

        var terms: [String] = []
        for marker in markers {
            var searchRange = text.startIndex ..< text.endIndex
            while let found = text.range(of: marker, range: searchRange) {
                let rest = text[found.upperBound...]
                // Take up to three words, stopping at punctuation.
                let clause = rest.prefix { $0 != "." && $0 != "," && $0 != ";" && $0 != "\n" }
                for word in clause.split(whereSeparator: { !$0.isLetter }).prefix(3) {
                    let candidate = String(word)
                    if candidate.count >= 3, !stopWords.contains(candidate), !terms.contains(candidate) {
                        terms.append(candidate)
                    }
                }
                searchRange = found.upperBound ..< text.endIndex
            }
        }
        return terms
    }

    // MARK: - Fit

    private static func fit(
        _ dish: Dish,
        prior: Int,
        sourceText: String,
        preferences: UserPreferences,
        memory: TasteMemory
    ) -> (Int, String) {
        // The model's read on how notable a dish is anchors the score, but
        // only loosely. It was weighted 0.58 and swamped everything else,
        // which meant a celebrated dish this particular person would dislike
        // still floated to the top — backwards for a chooser whose whole job
        // is personalisation. Notability sets the starting point; who is
        // eating decides the outcome.
        var score = 30.0 + 0.40 * Double(min(max(prior, 0), 100))
        let isStandout = prior >= 78
        var positives: [String] = []
        var negatives: [String] = []

        // Same widened haystack the safety check uses. Without the printed
        // line, a dislike that only appears on the menu — "sedano" for someone
        // who avoids celery — is invisible to the score.
        let haystack = searchText(for: dish) + " " + sourceText.lowercased()

        // Dislikes — a strong penalty but not a block. Matched through the
        // same stem table as allergens where one exists, so a menu printing
        // "sedano" still trips a dislike of celery.
        for dislike in preferences.dislikes {
            let label = dislike.lowercased()
            let terms = allergenTerms[label] ?? [label]
            if terms.contains(where: { haystackContains($0, haystack) }) {
                score -= 26
                negatives.append("has \(label) in it")
            }
        }

        // Spice.
        let spiceGap = dish.spiceLevel - preferences.spiceTolerance
        if spiceGap > 0 {
            score -= Double(spiceGap) * 13
            negatives.append("runs hotter than you go for")
        } else if dish.spiceLevel > 0, spiceGap <= 0 {
            score += 10
            positives.append("it has the heat you like")
        } else if preferences.spiceTolerance >= 2, dish.spiceLevel == 0 {
            score -= 5
        }

        // Cuisine the user said they love.
        if preferences.lovedCuisines.contains(where: {
            dish.cuisine.localizedCaseInsensitiveContains($0) || haystackContains($0.lowercased(), haystack)
        }) {
            score += 9
            positives.append(
                dish.cuisine.isEmpty
                    ? "it's your kind of food"
                    : "\(dish.cuisine) is on your list"
            )
        }

        // Learned taste — real evidence, so it outweighs the stated
        // preferences above.
        // Sharing ingredients is evidence. Sharing a cuisine barely is —
        // on a menu that is entirely one cuisine it lifts every dish by the
        // same amount, which is the same as lifting none of them. They are
        // weighted accordingly.
        for loved in memory.loved {
            if ingredientOverlap(dish, loved) >= 2 {
                score += 18
                positives.append("it's close to \(loved.name), which you gave \(loved.rating) stars")
                break
            }
            if !loved.cuisineHint.isEmpty, loved.cuisineHint == dish.cuisine {
                score += 5
                break
            }
        }

        for disliked in memory.disliked {
            if ingredientOverlap(dish, disliked) >= 2 {
                score -= 20
                negatives.append("looks like \(disliked.name), which you gave \(disliked.rating) stars")
                break
            }
            if !disliked.cuisineHint.isEmpty, disliked.cuisineHint == dish.cuisine {
                score -= 6
                break
            }
        }

        // Adventurousness. Graded rather than binary, because a menu of one
        // cuisine otherwise scores identically on every other term and the
        // ranking collapses into a tie.
        let adventure = adventureLevel(dish, haystack: haystack)
        if adventure > 0 {
            score += Double(adventure) * Double(preferences.adventurousness - 1) * 6
            if adventure >= 2, preferences.adventurousness >= 2 {
                positives.append("it's the kind of thing you'd never cook at home")
            }
        } else if preferences.adventurousness <= 1 {
            score += 7
        }


        // Diets deserve a positive signal, not just the absence of a warning.
        // Everything a vegetarian can eat currently scores the same, which
        // buries the dish the kitchen actually built for them under a pile of
        // technically-meatless side salads.
        switch preferences.diet {
        case .vegetarian, .vegan:
            if looksPlantForward(dish, haystack: haystack) {
                score += 14
                positives.append("it's built around the vegetables")
            }

        case .pescatarian:
            if seafoodTerms.contains(where: { haystackContains($0, haystack) }) {
                score += 10
                positives.append("it's the fish you came for")
            }

        case .halal, .kosher:
            // Meat that clears the checks still can't be verified from a
            // printed menu — slaughter and certification simply aren't on it.
            // Say so rather than implying a confidence we don't have.
            if meatTerms.contains(where: { haystackContains($0, haystack) }) {
                score -= 12
                negatives.append("needs a word with the kitchen about the meat")
            } else if !seafoodTerms.contains(where: { haystackContains($0, haystack) }) {
                score += 10
                positives.append("no meat, so nothing to check")
            }

        case .omnivore:
            break
        }

        // What they're going for. A soft nudge on top of everything above —
        // it can lift or lower a dish, never block one, and `.none` adds
        // exactly nothing so a diner without a goal sees the scores they
        // always did.
        let heaviness = dish.heaviness ?? estimatedHeaviness(for: dish, haystack: haystack)
        let health = dish.healthScore ?? estimatedHealth(for: dish, haystack: haystack)
        let goalDelta = goalAdjustment(
            preferences.goal,
            heaviness: heaviness,
            health: health,
            haystack: haystack
        )
        score += Double(goalDelta)

        // Their own words on the goal — "no sugar", "no cheese" — read with
        // the same explicit-phrasing rule as the notes, but as a penalty
        // rather than a warning. The engines already saw the note in full.
        for term in softAvoidTerms(fromGoalNote: preferences.goalNote)
        where haystackContains(term, haystack) {
            score -= 10
        }

        if isStandout {
            positives.insert("it's what this place is known for", at: 0)
        }

        let final = Int(score.rounded().clamped(to: 5 ... 97))
        return (
            final,
            reason(
                positives: positives,
                negatives: negatives,
                score: final,
                seed: dish.originalName + dish.translatedName,
                goalClause: goalClause(preferences.goal, delta: goalDelta)
            )
        )
    }

    /// Builds the one-line explanation.
    ///
    /// The opener is varied by dish so a screen of recommendations doesn't
    /// read as the same sentence three times, and a second positive is folded
    /// in when there is one — the differentiating detail is usually the second
    /// reason, not the first.
    private static func reason(
        positives: [String],
        negatives: [String],
        score: Int,
        seed: String,
        goalClause: (text: String, lifted: Bool)? = nil
    ) -> String {
        let base = baseReason(positives: positives, negatives: negatives, score: score, seed: seed)
        guard let goalClause else { return base }
        let stem = base.hasSuffix(".") ? String(base.dropLast()) : base
        let text = goalClause.text
        // A base that already carries a dash or a joined clause gets the
        // goal as its own short sentence — "Go for it — it's what this place
        // is known for. On the light side for you." — rather than a second
        // dash or a third "and". A plain base folds it in: "Safe bet, and it
        // keeps things light." / "Safe bet — a heavy one."
        if stem.contains(" — ") || stem.contains(", and ") || stem.contains(", though ") {
            let solo = text.hasPrefix("and ") ? String(text.dropFirst(4)) : text
            return base + " " + solo.prefix(1).uppercased() + solo.dropFirst() + "."
        }
        return stem + (goalClause.lifted ? ", " : " — ") + text + "."
    }

    private static func baseReason(
        positives: [String],
        negatives: [String],
        score: Int,
        seed: String
    ) -> String {
        if let negative = negatives.first, score < 50 {
            return "Probably not — it \(negative)."
        }

        if let positive = positives.first {
            let openers = score >= 78
                ? ["Order this", "This is the one", "Go for it"]
                : ["Good call", "Worth it", "Solid choice"]
            var text = "\(openers[stableIndex(seed, count: openers.count)]) — \(positive)"

            if positives.count > 1 {
                text += ", and \(positives[1])"
            }
            if let negative = negatives.first {
                text += ", though it \(negative)"
            }
            return text + "."
        }

        if let negative = negatives.first {
            return "Fine, but it \(negative)."
        }
        return score >= 65
            ? "Safe bet."
            : "Fine. Just not especially you."
    }

    // MARK: - Goal

    /// Dishes that are fried, creamy, cheesy or sweet enough to count as heavy.
    private static let heavyStems = [
        "fried", "fritt", "tempura", "batter", "cream", "crema", "panna",
        "butter", "burro", "cheese", "formaggio", "queso", "fromage", "bacon",
        "pancetta", "lard", "pastry", "pie", "burger", "pizza", "lasagn",
        "carbonara", "gratin", "cheesecake", "chocolate", "cioccol", "caramel",
        "syrup",
    ]

    /// Salads, grills, broths, raw fish — the light end of a menu.
    private static let lightStems = [
        "salad", "insalata", "ensalada", "salade", "grilled", "griglia", "grill",
        "steamed", "vapore", "broth", "brodo", "soup", "zuppa", "sopa",
        "poached", "raw", "crudo", "ceviche", "sashimi", "vegetable", "verdur",
        "greens", "fruit", "frutta",
    ]

    private static let dessertStems = [
        "dolce", "dessert", "cake", "torta", "tiramis", "gelato", "ice cream", "sweet",
    ]

    /// Fish, legumes and vegetables: the things that make a dish wholesome.
    private static let wholesomeStems = [
        "fish", "pesce", "pescado", "poisson", "salmon", "salmone", "tuna", "tonno",
        "cod", "merluzz", "sardine", "sardina", "mackerel", "sgombro", "trout", "trota",
        "branzino", "seabass", "prawn", "shrimp", "gamber",
        "lentil", "lentic", "bean", "fagiol", "chickpea", "ceci", "tofu", "edamame",
        "vegetable", "verdur", "greens", "spinach", "spinaci", "broccoli",
        "aubergine", "eggplant", "melanzane", "courgette", "zucchini", "artichoke",
        "carciof", "pumpkin", "zucca", "asparagus", "asparagi", "kale", "cavolo",
    ]

    private static let proteinStems = [
        "chicken", "pollo", "poulet", "beef", "manzo", "boeuf", "steak", "bistecca",
        "lamb", "agnello", "veal", "vitello", "turkey", "tacchino", "fish", "pesce",
        "salmon", "salmone", "tuna", "tonno", "prawn", "gamber", "shrimp", "crevette",
        "egg", "uova", "huevo", "tofu", "lentil", "lentic", "bean", "fagiol",
        "chickpea", "ceci",
    ]

    /// 1 light, 2 medium, 3 hearty — from what the menu says is on the plate.
    /// Used when the engine gave no read of its own.
    static func estimatedHeaviness(for dish: Dish, haystack: String = "") -> Int {
        let text = searchText(for: dish) + " " + haystack.lowercased()
        if heavyStems.contains(where: { haystackContains($0, text) }) { return 3 }
        if lightStems.contains(where: { haystackContains($0, text) }) { return 1 }
        return 2
    }

    /// 1 indulgent … 10 very healthy, anchored at 5 and moved by what the
    /// dish is built from. Used when the engine gave no read of its own.
    static func estimatedHealth(for dish: Dish, haystack: String = "") -> Int {
        let text = searchText(for: dish) + " " + haystack.lowercased()
        var health = 5
        if lightStems.contains(where: { haystackContains($0, text) }) { health += 2 }
        if wholesomeStems.contains(where: { haystackContains($0, text) }) { health += 1 }
        if heavyStems.contains(where: { haystackContains($0, text) }) { health -= 2 }
        if dessertStems.contains(where: { haystackContains($0, text) }) { health -= 2 }
        return min(max(health, 1), 10)
    }

    /// How far the goal moves a dish. Bounded on both sides so it can colour
    /// a ranking without ever deciding it.
    private static func goalAdjustment(
        _ goal: EatingGoal,
        heaviness: Int,
        health: Int,
        haystack: String
    ) -> Int {
        switch goal {
        case .none:
            return 0
        case .healthy:
            return min(max((health - 5) * 3, -12), 15)
        case .light:
            return [1: 12, 2: 0, 3: -12][heaviness] ?? 0
        case .hearty:
            return [1: -8, 2: 3, 3: 12][heaviness] ?? 0
        case .protein:
            var delta = 0
            if proteinStems.contains(where: { haystackContains($0, haystack) }) { delta += 12 }
            if dessertStems.contains(where: { haystackContains($0, haystack) }) { delta -= 6 }
            return delta
        }
    }

    /// One short clause for the reason line, only when the goal actually
    /// moved the needle.
    private static func goalClause(_ goal: EatingGoal, delta: Int) -> (text: String, lifted: Bool)? {
        guard abs(delta) >= 8 else { return nil }
        let lifted = delta > 0
        let text: String
        switch goal {
        case .none: return nil
        case .healthy: text = lifted ? "and it's the fresh pick here" : "richer than you're after"
        case .light: text = lifted ? "and it keeps things light" : "a heavy one"
        case .hearty: text = lifted ? "and it's a proper plateful" : "on the light side for you"
        case .protein:
            guard lifted else { return nil }
            text = "and it packs protein"
        }
        return (text, lifted)
    }

    // MARK: - Helpers

    /// Substring matching is what lets a stem span languages — "pistac" finds
    /// Italian *pistacchi*. It is also what makes a three-letter stem
    /// dangerous: "egg" is inside **eggplant**, "nut" inside **nutmeg**, "soy"
    /// inside **soybean-free**. Short stems therefore have to match a whole
    /// word (or its plural); longer ones keep the loose match.
    static func haystackContains(_ stem: String, _ haystack: String) -> Bool {
        guard stem.count < 5 else { return haystack.contains(stem) }
        return haystack
            .split(whereSeparator: { !$0.isLetter })
            .contains { word in
                word == stem || (word.count == stem.count + 1 && word.hasPrefix(stem) && word.hasSuffix("s"))
            }
    }

    /// Picks a variant for a dish, stably.
    ///
    /// Not `abs(hashValue)`: Swift seeds string hashing per process, so the
    /// same dish would get a different opener on every launch, and
    /// `abs(Int.min)` traps outright.
    private static func stableIndex(_ seed: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        var total = 0
        for scalar in seed.unicodeScalars {
            total = (total &* 31 &+ Int(scalar.value)) % 1_000_003
        }
        return total % count
    }

    /// The full word from the menu that a stem matched inside, so warnings
    /// quote what the diner can actually point at on the page.
    private static func wholeWord(containing stem: String, in haystack: String) -> String {
        let match = haystack
            .split(whereSeparator: { !$0.isLetter })
            .first { $0.contains(stem) }
        return match.map(String.init) ?? stem
    }

    /// Deliberately excludes `dish.allergens`.
    ///
    /// That field is the model's own guess, and it guesses badly in the
    /// direction that hurts: asked about a diner with a nut allergy it
    /// attached "nuts" to Carbonara — eggs, guanciale and pecorino — which
    /// blocked a perfectly safe dish. Matching only against concrete evidence
    /// (the names, the description, the ingredient list and the printed menu
    /// line) keeps every true catch in testing while dropping that false one.
    /// The model's allergen list is still shown in the UI, clearly labelled as
    /// inferred.
    private static func searchText(for dish: Dish) -> String {
        ([dish.translatedName, dish.originalName, dish.description, dish.cuisine]
            + dish.ingredients + dish.dietaryTags)
            .joined(separator: " ")
            .lowercased()
    }

    /// A dish built around vegetables rather than one that merely lacks meat.
    private static func looksPlantForward(_ dish: Dish, haystack: String) -> Bool {
        let heroes = ["aubergine", "eggplant", "melanzane", "artichoke", "carciof",
                      "mushroom", "funghi", "porcini", "truffle", "tartufo",
                      "pumpkin", "zucca", "courgette", "zucchini", "cauliflower",
                      "cavolfiore", "broccoli", "spinach", "spinaci", "chickpea",
                      "ceci", "lentil", "lentic", "bean", "fagiol", "tofu",
                      "aubergines", "pepper", "peperon", "asparagus", "asparagi",
                      "squash", "beetroot", "barbabietola", "leek", "porri"]
        if heroes.contains(where: { haystackContains($0, haystack) }) { return true }
        return dish.dietaryTags.contains {
            $0.localizedCaseInsensitiveContains("vegan") || $0.localizedCaseInsensitiveContains("vegetarian")
        }
    }

    /// 0 = something you could get anywhere, 2 = a dish a visitor would
    /// remember. Built from what is actually on the plate rather than from how
    /// long the name is.
    private static func adventureLevel(_ dish: Dish, haystack: String) -> Int {
        let bold = ["tripe", "trippa", "offal", "liver", "fegato", "kidney", "brain",
                    "tongue", "lingua", "tail", "coda", "oxtail", "bone marrow",
                    "midollo", "blood", "snail", "lumache", "escargot", "sweetbread",
                    "gizzard", "heart", "tartare", "raw", "crudo", "fermented",
                    "pickled", "salted", "cured", "smoked", "roe", "bottarga",
                    "sea urchin", "ricci", "eel", "anguilla", "octopus", "polpo"]

        var level = 0
        if bold.contains(where: { haystackContains($0, haystack) }) { level += 2 }
        if dish.ingredients.count >= 5 { level += 1 }
        if !dish.pronunciation.isEmpty, dish.pronunciation.count > 4 { level += 1 }
        return min(level, 2)
    }


    private static func ingredientOverlap(_ dish: Dish, _ order: OrderedDish) -> Int {
        let a = Set(dish.ingredients.map { $0.lowercased() })
        let b = Set(order.ingredients.map { $0.lowercased() })
        return a.intersection(b).count
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
