//
//  OnDeviceEngine.swift
//  menuai
//
//  The no-API-key path. Vision reads the menu, Apple's on-device model
//  explains and translates it, and DishScorer does the ranking.
//
//  The division of labour is deliberate. The on-device model is small, so it
//  is asked only to do the thing small models are good at — turning a line of
//  menu text into a structured dish with a plain description — and never to
//  weigh a dish against a taste profile or catch an allergen. Its context
//  window is a few thousand tokens, so the menu is fed through in chunks with
//  a fresh session each time; reusing one session would accumulate transcript
//  until it overflowed halfway down a long menu.
//

import FoundationModels
import UIKit
import Vision

// MARK: - Generated shapes

@Generable
struct GeneratedDish {
    @Guide(description: "The dish name copied exactly as printed, in the menu's own language and script. Never translate this field.")
    var originalName: String

    @Guide(description: "The dish name translated into the target language, phrased naturally rather than word-for-word.")
    var translatedName: String

    @Guide(description: "One plain sentence saying what the dish actually is and how it is cooked.")
    var summary: String

    @Guide(description: "The price exactly as printed including any currency symbol. Empty string if no price is shown.")
    var price: String

    @Guide(description: "The cuisine this dish belongs to, such as Thai, Neapolitan, Georgian. One or two words.")
    var cuisine: String

    @Guide(description: "The main ingredients, including ones not printed on the menu but standard in this dish.", .count(1 ... 6))
    var ingredients: [String]

    @Guide(description: "Allergens this dish likely contains. Only real allergens: dairy, eggs, gluten, peanuts, tree nuts, shellfish, fish, soy, sesame, mustard, celery, sulfites. Never list 'meat', 'pork', or a cuisine.", .maximumCount(5))
    var allergens: [String]

    @Guide(description: "How spicy the dish is: 0 not spicy, 1 mild, 2 medium, 3 very hot.", .range(0 ... 3))
    var spiceLevel: Int

    @Guide(description: "How strongly a first-time visitor should order this dish here, 0-100. Reserve 85+ for the regional signature this kind of restaurant is famous for, 55-70 for solid but common dishes, and 20-40 for filler that appears on every menu. Spread these out — do not give everything a similar number.", .range(0 ... 100))
    var notability: Int

    @Guide(description: "How healthy the dish is, 1 indulgent to 10 very healthy", .range(1 ... 10))
    var healthScore: Int

    @Guide(description: "1 light, 2 medium, 3 heavy and filling", .range(1 ... 3))
    var heaviness: Int
}

@Generable
struct GeneratedDishBatch {
    @Guide(description: "Every dish found in this portion of the menu, including desserts and drinks. Skip headings, addresses, opening hours, and anything that is not a dish.", .maximumCount(14))
    var dishes: [GeneratedDish]
}

@Generable
struct GeneratedMenuInfo {
    @Guide(description: "The restaurant's name if it appears, otherwise an empty string.")
    var restaurantName: String

    @Guide(description: "One sentence describing what kind of place this is, based on the dishes.")
    var summary: String

    @Guide(description: "The main cuisine of the menu, one or two words.")
    var cuisine: String
}

// MARK: - Engine

/// A dish as it came out of one chunk, kept alongside the raw menu text that
/// produced it so the allergen check can fall back to what was actually
/// printed.
struct ParsedDish {
    var dish: Dish
    var notability: Int
    var sourceText: String
}

struct OnDeviceEngine: MenuEngine {
    let kind: MenuEngineKind = .onDevice

    /// Roughly one printed menu column. Small enough that the schema, the
    /// instructions and ten generated dishes all fit the context window.
    private static let chunkBudget = 560

    // MARK: Availability

    enum Readiness: Equatable {
        case ready
        case notReady(String)

        var isReady: Bool { self == .ready }
    }

    static var readiness: Readiness {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
        case let .unavailable(reason):
            switch reason {
            case .deviceNotEligible:
                return .notReady("This iPhone doesn't support Apple Intelligence, which reads the menus.")
            case .appleIntelligenceNotEnabled:
                return .notReady("Turn on Apple Intelligence in Settings, then try again.")
            case .modelNotReady:
                return .notReady("Apple Intelligence is still setting up. Try again in a few minutes.")
            @unknown default:
                return .notReady("Apple Intelligence isn't available right now.")
            }
        @unknown default:
            return .notReady("Apple Intelligence isn't available right now.")
        }
    }

    /// Deliberately the default configuration.
    ///
    /// `permissiveContentTransformations` was tried, and it depends on a
    /// separate safety-model asset that is not always present — when it is
    /// missing every request fails with a nested
    /// `SensitiveContentAnalysisML` / `ModelManagerError 1026`, i.e. the whole
    /// app stops working. It was only ever needed for a comparison prompt that
    /// no longer exists; extraction has never tripped the default guardrail.
    static let model = SystemLanguageModel.default

    /// Warms the model so the first chunk isn't paying for cold start while
    /// the user watches a spinner.
    static func prewarm() {
        guard readiness.isReady else { return }
        LanguageModelSession(model: model).prewarm()
    }

    // MARK: Analyze

    func analyze(
        image: UIImage,
        preferences: UserPreferences,
        memory: TasteMemory,
        onProgress: @escaping ProgressHandler
    ) async throws -> ParsedMenu {
        if case let .notReady(message) = Self.readiness {
            throw EngineError.engineUnavailable(message)
        }

        onProgress(0.08, "Reading the menu…")
        let transcript = try await recognizeText(in: image)

        let chunks = Self.chunk(transcript)
        guard !chunks.isEmpty else { throw EngineError.noMenuFound }

        onProgress(0.2, "Finding the dishes…")

        // Metadata first, from the top of the menu where the name usually is.
        let info = try? await menuInfo(from: chunks[0], preferences: preferences)

        var dishes: [ParsedDish] = []
        for (index, chunk) in chunks.enumerated() {
            let fraction = 0.2 + 0.7 * (Double(index) / Double(chunks.count))
            onProgress(fraction, chunks.count > 1
                ? "Reading part \(index + 1) of \(chunks.count)…"
                : "Finding the dishes…")

            let batch = try await parse(chunk: chunk, preferences: preferences)
            #if DEBUG
            print("[engine] chunk \(index + 1)/\(chunks.count) (\(chunk.count) chars) -> \(batch.count) dishes")
            #endif
            dishes.append(contentsOf: batch)
        }

        let currency = Self.detectCurrency(in: transcript)
        let unique = Self.normalisePrices(Self.deduplicate(dishes), fallback: currency)
        #if DEBUG
        print("[engine] \(dishes.count) raw -> \(unique.count) after dedupe")
        #endif
        guard !unique.isEmpty else { throw EngineError.noMenuFound }

        onProgress(0.94, "Picking for you…")

        // Fall back to the menu-wide cuisine for any dish the model left blank,
        // so the history statistics stay useful.
        let fallbackCuisine = info?.cuisine ?? ""
        let scored = unique.map { parsed -> Dish in
            var dish = parsed.dish
            if dish.cuisine.isEmpty { dish.cuisine = fallbackCuisine }
            return DishScorer.score(
                dish,
                prior: parsed.notability,
                sourceText: parsed.sourceText,
                preferences: preferences,
                memory: memory
            )
        }

        return ParsedMenu(
            detectedLanguages: [],
            restaurantName: info?.restaurantName ?? "",
            currency: currency,
            summary: info?.summary ?? "",
            sections: [MenuSection(name: "Menu", originalName: "", dishes: scored)],
            engine: .onDevice
        )
    }

    // MARK: - OCR

    private func recognizeText(in image: UIImage) async throws -> String {
        guard let cgImage = ImageProcessing.resized(image, maxDimension: 2400).cgImage else {
            throw EngineError.imageEncodingFailed
        }

        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.automaticallyDetectLanguage = true
        request.textRecognitionOptions.useLanguageCorrection = true

        let observations = try await request.perform(on: cgImage)
        let text = observations
            .map(\.document.text.transcript)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard text.count > 12 else { throw EngineError.noMenuFound }
        #if DEBUG
        try? text.write(
            to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ocr.txt"),
            atomically: true,
            encoding: .utf8
        )
        #endif
        return text
    }

    /// Splits the transcript on line boundaries, with the last two lines of
    /// each chunk repeated at the head of the next.
    ///
    /// Without the overlap a dish whose name, description and price straddle a
    /// boundary gets torn in half: one chunk yields a dish called "Veal", the
    /// next yields one called "€ 22". With it, the dish appears intact in at
    /// least one chunk and `deduplicate` drops the fragments.
    static func chunk(_ transcript: String) -> [String] {
        let lines = transcript
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var chunks: [String] = []
        var current: [String] = []
        var size = 0

        for line in lines {
            if size + line.count > chunkBudget, !current.isEmpty {
                chunks.append(current.joined(separator: "\n"))
                current = Array(current.suffix(2))
                size = current.reduce(0) { $0 + $1.count + 1 }
            }
            current.append(line)
            size += line.count + 1
        }
        if !current.isEmpty { chunks.append(current.joined(separator: "\n")) }
        return chunks
    }

    /// The currency the menu is printed in, read straight off the OCR text.
    static func detectCurrency(in transcript: String) -> String {
        let symbols: [Character] = ["€", "£", "$", "¥", "₩", "₽", "₺", "₪", "₹", "₫", "₾", "฿", "₴", "zł"].compactMap(\.first)
        var counts: [Character: Int] = [:]
        for character in transcript where symbols.contains(character) {
            counts[character, default: 0] += 1
        }
        guard let best = counts.max(by: { $0.value < $1.value })?.key else { return "" }
        return String(best)
    }

    /// Puts the currency symbol back on prices that lost it.
    ///
    /// The model returns "€ 16" for some dishes on a menu and a bare "16" for
    /// others, which looks broken in a list. Whatever symbol it did capture
    /// most often is the menu's currency, so it is applied to the bare ones.
    static func normalisePrices(_ parsed: [ParsedDish], fallback: String = "") -> [ParsedDish] {
        var counts: [String: Int] = [:]
        for item in parsed {
            let symbol = item.dish.price.filter { !$0.isNumber && !$0.isWhitespace && $0 != "." && $0 != "," }
            if !symbol.isEmpty { counts[symbol, default: 0] += 1 }
        }
        // Some runs drop the symbol from every price, so there is nothing to
        // copy between dishes. The printed menu still has it.
        let currency = counts.max(by: { $0.value < $1.value })?.key ?? fallback
        guard !currency.isEmpty else { return parsed }

        return parsed.map { item in
            var item = item
            let price = item.dish.price.trimmingCharacters(in: .whitespaces)
            guard !price.isEmpty,
                  price.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," })
            else { return item }
            item.dish.price = "\(currency)\(price)"
            return item
        }
    }

    /// The one or two menu lines this dish came from.
    ///
    /// Handing the scorer the whole chunk is wrong and dangerous: a single
    /// "Gamberi in Padella" in the chunk would flag a shellfish allergy on
    /// every other dish beside it. Attribution has to be per dish, so this
    /// finds the printed line that best matches the dish's own name and
    /// returns just that line plus the description line beneath it. When no
    /// line matches confidently it returns nothing, and the check falls back
    /// to the model's fields — under-matching is recoverable, over-matching
    /// blocks the entire menu.
    static func sourceSnippet(for dish: Dish, in chunk: String) -> String {
        let lines = chunk.components(separatedBy: .newlines)
        let wanted = tokens(dish.originalName.isEmpty ? dish.translatedName : dish.originalName)
        guard !wanted.isEmpty else { return "" }

        var bestIndex: Int?
        var bestScore = 0

        for (index, line) in lines.enumerated() {
            let overlap = tokens(line).intersection(wanted).count
            if overlap > bestScore {
                bestScore = overlap
                bestIndex = index
            }
        }

        // Require a real match: one shared short word is coincidence.
        guard let index = bestIndex, bestScore >= min(2, wanted.count) else { return "" }
        return lines[index ... min(index + 1, lines.count - 1)].joined(separator: " ")
    }

    private static func tokens(_ text: String) -> Set<String> {
        Set(
            text.lowercased()
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                .split(whereSeparator: { !$0.isLetter })
                .map(String.init)
                .filter { $0.count >= 3 }
        )
    }

    /// Removes fragments and repeats left over from the overlapping chunks.
    /// Keeps whichever copy of a dish carries the most detail, since a torn
    /// half is always the sparser one.
    static func deduplicate(_ parsed: [ParsedDish]) -> [ParsedDish] {
        var best: [String: ParsedDish] = [:]
        var order: [String] = []

        for item in parsed where isPlausibleDish(item.dish) {
            // Key on the printed name first. The model translates the same
            // dish differently in different chunks — "Tiramisu" in one,
            // "Classic Italian Dessert" in the next — so keying on the
            // translation lets duplicates through.
            let key = normalise(
                item.dish.originalName.isEmpty ? item.dish.displayName : item.dish.originalName
            )
            guard !key.isEmpty else { continue }

            guard let existing = best[key] else {
                best[key] = item
                order.append(key)
                continue
            }

            // Keep the richer copy, but never discard evidence. One chunk may
            // have caught the ingredient line that names an allergen while the
            // other did not, so the source snippets and the allergen and
            // ingredient lists are merged across every copy rather than taken
            // from the winner alone. Dropping a duplicate must never drop a
            // reason to warn someone.
            var winner = detail(item.dish) > detail(existing.dish) ? item : existing
            let loser = detail(item.dish) > detail(existing.dish) ? existing : item

            winner.sourceText = mergeText(winner.sourceText, loser.sourceText)
            winner.dish.allergens = mergeUnique(winner.dish.allergens, loser.dish.allergens)
            winner.dish.ingredients = mergeUnique(winner.dish.ingredients, loser.dish.ingredients)
            if winner.dish.price.isEmpty { winner.dish.price = loser.dish.price }
            if winner.dish.originalName.isEmpty { winner.dish.originalName = loser.dish.originalName }
            best[key] = winner
        }
        return order.compactMap { best[$0] }
    }

    private static func mergeText(_ a: String, _ b: String) -> String {
        guard !b.isEmpty else { return a }
        guard !a.isEmpty else { return b }
        return a.localizedCaseInsensitiveContains(b) ? a : a + " " + b
    }

    private static func mergeUnique(_ a: [String], _ b: [String]) -> [String] {
        var seen = Set(a.map { $0.lowercased() })
        var result = a
        for value in b where !seen.contains(value.lowercased()) {
            seen.insert(value.lowercased())
            result.append(value)
        }
        return result
    }

    /// Rejects price lines, section headings, and one-word scraps that the
    /// model sometimes emits when a chunk boundary cuts a dish in half.
    private static func isPlausibleDish(_ dish: Dish) -> Bool {
        let name = dish.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count >= 3 else { return false }

        // Nothing but digits, currency and punctuation is a price, not a dish.
        let meaningful = name.unicodeScalars.filter {
            CharacterSet.letters.contains($0)
        }
        guard meaningful.count >= 3 else { return false }

        // A bare heading like "ANTIPASTI" carries no other detail.
        if name == name.uppercased(), dish.description.isEmpty, dish.ingredients.isEmpty {
            return false
        }
        return true
    }

    private static func detail(_ dish: Dish) -> Int {
        dish.description.count
            + dish.ingredients.count * 12
            + dish.allergens.count * 6
            + (dish.price.isEmpty ? 0 : 8)
            + (dish.originalName.isEmpty ? 0 : 6)
    }

    static func normalise(_ name: String) -> String {
        name.lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isWhitespace }
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Generation

    private func parse(
        chunk: String,
        preferences: UserPreferences,
        attempt: Int = 0
    ) async throws -> [ParsedDish] {
        // A fresh session per chunk: the transcript from the previous chunk is
        // dead weight that would eventually overflow the context window.
        let session = LanguageModelSession(
            model: Self.model,
            instructions: Self.instructions(for: preferences)
        )

        do {
            let response = try await session.respond(
                to: """
                Here is part of a restaurant menu. List every dish in it.

                \(chunk)
                """,
                generating: GeneratedDishBatch.self,
                options: GenerationOptions(temperature: 0.3)
            )
            return response.content.dishes.map { generated in
                let dish = generated.toDish()
                return ParsedDish(
                    dish: dish,
                    notability: min(max(generated.notability, 0), 100),
                    sourceText: Self.sourceSnippet(for: dish, in: chunk)
                )
            }
        } catch {
            #if DEBUG
            Self.debugLog("chunk attempt \(attempt + 1) failed: \(error)")
            #endif

            // Two retries with a widening gap. The model is genuinely busy
            // just after launch — assets finishing loading, another session
            // still winding down — and those failures clear in under a second.
            // Losing a whole menu to one is not acceptable when the retry is
            // this cheap.
            if attempt < Self.maxRetries, Self.isWorthRetrying(error) {
                try? await Task.sleep(for: .milliseconds(500 * (attempt + 1)))
                return try await parse(chunk: chunk, preferences: preferences, attempt: attempt + 1)
            }

            // Catch-all rather than a typed catch: anything that escapes here
            // reaches the user as an alert, and "GenerationError error -1" is
            // not something anybody can act on.
            if Self.isAssetFailure(error) {
                throw EngineError.engineUnavailable(
                    "Apple Intelligence is still setting up. Your photo's fine — try again in a few minutes."
                )
            }
            if let generation = error as? LanguageModelSession.GenerationError {
                throw Self.translate(generation)
            }
            throw EngineError.engineUnavailable(
                "Couldn't finish reading that. Try again, or one section at a time."
            )
        }
    }

    private static let maxRetries = 2

    /// Apple Intelligence assets missing or still downloading.
    ///
    /// `SystemLanguageModel.availability` reports `.available` in this state,
    /// because it only checks the language model — the *safety* model is a
    /// separate asset, and when it is absent every request fails with a
    /// nested `SensitiveContentAnalysisML` / `ModelManagerError 1026` that
    /// surfaces as an untyped `GenerationError -1`. Worth naming, because
    /// "try again in a few minutes" is true and actionable, whereas
    /// "couldn't read that menu" sends people off to retake a fine photo.
    static func isAssetFailure(_ error: Error) -> Bool {
        let text = String(describing: error)
        return text.contains("ModelManagerError")
            || text.contains("SensitiveContentAnalysis")
            || text.contains("assetsUnavailable")
    }

    #if DEBUG
    /// Appends to Documents so failures can be read back without a console.
    static func debugLog(_ message: String) {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("engine-log.txt")
        let line = message + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    #endif

    /// Transient conditions, plus anything we don't recognise — an unknown
    /// error is more likely a hiccup than a permanent refusal, and a retry
    /// costs a second.
    private static func isWorthRetrying(_ error: Error) -> Bool {
        guard let generation = error as? LanguageModelSession.GenerationError else { return true }
        switch generation {
        case .exceededContextWindowSize, .unsupportedLanguageOrLocale,
             .guardrailViolation, .refusal:
            return false
        default:
            return true
        }
    }

    private func menuInfo(
        from chunk: String,
        preferences: UserPreferences
    ) async throws -> GeneratedMenuInfo {
        let session = LanguageModelSession(
            model: Self.model,
            instructions: Self.instructions(for: preferences)
        )
        let response = try await session.respond(
            to: """
            Here is the top of a restaurant menu. Identify the restaurant and \
            what kind of place it is.

            \(chunk)
            """,
            generating: GeneratedMenuInfo.self,
            options: GenerationOptions(temperature: 0.2)
        )
        return response.content
    }

    private static func instructions(for preferences: UserPreferences) -> String {
        """
        You read restaurant menus that have been scanned by OCR, and explain \
        them to a diner who cannot read the original language.

        Translate every dish name and description into \
        \(preferences.displayLanguageName). Keep `originalName` in the menu's \
        own language and script, exactly as printed.

        The OCR text may contain mistakes, broken words, and stray characters. \
        Use what you know about the cuisine to recognise dishes through the \
        noise. Never invent a dish that is not in the text. Skip headings, \
        addresses, phone numbers, and opening hours.

        Fill in ingredients and allergens from how the dish is standardly made, \
        even when the menu does not spell them out.
        \(allergyInstruction(for: preferences))
        """
    }

    /// Naming the diner's allergens in the prompt makes the model look for
    /// them specifically, which catches cases the stem list misses and vice
    /// versa. Neither is trusted on its own.
    private static func allergyInstruction(for preferences: UserPreferences) -> String {
        guard !preferences.allergies.isEmpty else { return "" }
        let list = preferences.allergies.joined(separator: ", ")
        return """


        This diner is allergic to: \(list). Read every ingredient line \
        carefully and list one of these in `allergens` when the dish really \
        does contain it, including when the menu names the ingredient in its \
        own language. Do not list an allergen that is not actually in the \
        dish — a false alarm on a safe dish is as harmful as a missed one.
        """
    }

    private static func translate(_ error: LanguageModelSession.GenerationError) -> EngineError {
        switch error {
        case .exceededContextWindowSize:
            .engineUnavailable("Too much text at once. Try one column at a time.")
        case .assetsUnavailable:
            .engineUnavailable("Apple Intelligence is still setting up. Try again in a few minutes.")
        case .unsupportedLanguageOrLocale:
            .engineUnavailable("This language isn't supported yet.")
        case .guardrailViolation, .refusal:
            .engineUnavailable("That photo couldn't be read.")
        case .rateLimited, .concurrentRequests:
            .engineUnavailable("Busy right now. Try again in a moment.")
        case .decodingFailure:
            .engineUnavailable("That didn't come through cleanly. Try again, or one section at a time.")
        default:
            // Never surface a raw framework error to someone standing in a
            // restaurant. Anything unmapped still gets a sentence they can act
            // on; the detail goes to the console instead.
            .engineUnavailable("Couldn't finish reading that. Try again, or one section at a time.")
        }
    }

}

// MARK: - Mapping

extension GeneratedDish {
    /// The model occasionally answers "meat" or "pork" here, which are diet
    /// concerns rather than allergens and would clutter the allergen chips.
    static func isRealAllergen(_ value: String) -> Bool {
        let known = ["dairy", "milk", "egg", "gluten", "wheat", "peanut", "nut",
                     "shellfish", "fish", "soy", "sesame", "mustard", "celery",
                     "sulfite", "sulphite", "lupin", "mollusc", "crustacean"]
        let lowered = value.lowercased()
        return known.contains { lowered.contains($0) }
    }

    func toDish() -> Dish {
        Dish(
            originalName: originalName.trimmingCharacters(in: .whitespacesAndNewlines),
            translatedName: translatedName.trimmingCharacters(in: .whitespacesAndNewlines),
            pronunciation: "",
            description: summary,
            price: price,
            cuisine: cuisine,
            ingredients: ingredients,
            allergens: allergens.filter { GeneratedDish.isRealAllergen($0) },
            dietaryTags: [],
            spiceLevel: min(max(spiceLevel, 0), 3),
            matchScore: 50,
            matchReason: "",
            warnings: [],
            imageSearchQuery: [translatedName, cuisine, "dish"]
                .filter { !$0.isEmpty }
                .joined(separator: " "),
            healthScore: min(max(healthScore, 1), 10),
            heaviness: min(max(heaviness, 1), 3)
        )
    }
}
