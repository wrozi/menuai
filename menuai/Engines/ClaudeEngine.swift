//
//  ClaudeEngine.swift
//  menuai
//
//  The high-quality path, used when the user has supplied an API key.
//
//  There is no official Anthropic SDK for Swift, so this hand-rolls
//  POST https://api.anthropic.com/v1/messages. One call does OCR,
//  translation, allergen inference and personalised scoring together —
//  they all need the same image in context, and splitting them would mean
//  paying for the image twice.
//

import Foundation
import UIKit

struct ClaudeEngine: MenuEngine {
    let kind: MenuEngineKind = .claude

    /// Menu photos are often skewed, dim, or handwritten, so accuracy matters
    /// more here than the per-request cost.
    static let model = "claude-opus-5"
    static let apiVersion = "2023-06-01"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    private let apiKey: String
    private let session: URLSession

    init(apiKey: String) {
        self.apiKey = apiKey
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 240
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
    }

    // MARK: - Analyze

    func analyze(
        image: UIImage,
        preferences: UserPreferences,
        memory: TasteMemory,
        onProgress: @escaping ProgressHandler
    ) async throws -> ParsedMenu {
        onProgress(0.1, "Reading the menu…")

        guard let jpeg = ImageProcessing.prepareForVision(image) else {
            throw EngineError.imageEncodingFailed
        }

        onProgress(0.28, "Reading every dish…")

        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 24_000,
            "output_config": [
                // Bounded extraction plus scoring — not open-ended reasoning.
                "effort": "medium",
                "format": ["type": "json_schema", "schema": Self.menuSchema],
            ],
            "system": Self.systemPrompt,
            "messages": [[
                "role": "user",
                "content": [
                    // Image first: the model attends to it better when the
                    // instructions follow rather than precede it.
                    ["type": "image", "source": [
                        "type": "base64",
                        "media_type": "image/jpeg",
                        "data": jpeg.base64EncodedString(),
                    ]],
                    ["type": "text", "text": Self.userPrompt(preferences: preferences, memory: memory)],
                ],
            ]],
        ]

        let json = try await send(body: body)

        onProgress(0.9, "Picking for you…")

        var menu = try Self.decodeMenu(from: json)

        // Claude scored the dishes; this re-checks each one against the stated
        // allergies and diet and adds anything it missed. A missed allergen is
        // the one failure mode worth spending a second pass on.
        menu.sections = menu.sections.map { section in
            var section = section
            section.dishes = section.dishes.map {
                DishScorer.applySafetyNet($0, preferences: preferences)
            }
            return section
        }
        menu.engine = .claude
        return menu
    }

    // MARK: - Transport

    private func send(body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw EngineError.badResponse("no HTTP response")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw EngineError.http(status: http.statusCode, message: Self.errorMessage(from: data))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EngineError.badResponse("response was not a JSON object")
        }
        return json
    }

    private static func errorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String
        else {
            return String(data: data, encoding: .utf8) ?? "unknown error"
        }
        return message
    }

    // MARK: - Response handling

    private static func decodeMenu(from json: [String: Any]) throws -> ParsedMenu {
        // Safety classifiers can decline outright, which returns HTTP 200 with
        // empty content — so check the stop reason before reading content.
        let stopReason = json["stop_reason"] as? String
        if stopReason == "refusal" {
            let details = json["stop_details"] as? [String: Any]
            var message = "Claude declined to process this image"
            if let category = details?["category"] as? String { message += " (\(category))" }
            throw EngineError.refused(message + ".")
        }
        if stopReason == "max_tokens" { throw EngineError.truncated }

        guard let content = json["content"] as? [[String: Any]] else {
            throw EngineError.badResponse("missing content array")
        }
        // Thinking blocks come first and carry no text; the JSON is in the
        // first text block.
        guard let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let payload = text.data(using: .utf8)
        else {
            throw EngineError.badResponse("no text block in response")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            var menu = try decoder.decode(ParsedMenu.self, from: payload)
            menu.sections = menu.sections.filter { !$0.dishes.isEmpty }
            guard !menu.allDishes.isEmpty else { throw EngineError.noMenuFound }
            return menu
        } catch let error as EngineError {
            throw error
        } catch {
            throw EngineError.badResponse(error.localizedDescription)
        }
    }

    // MARK: - Prompt

    private static let systemPrompt = """
    You read photographs of restaurant menus in any language and script, and \
    explain them to a traveller who cannot read the original.

    Your job, in one pass:

    1. TRANSCRIBE. Read every dish exactly as printed, preserving the original \
    script and spelling. Work through skew, glare, handwriting, and partial \
    occlusion. If part of the menu is genuinely unreadable, omit those dishes \
    rather than inventing them.
    2. TRANSLATE. Give each dish a natural name in the target language — not a \
    literal gloss. "Bún chả" is "grilled pork with rice noodles", not "noodle \
    grilled". Add a short phonetic hint so the diner can say it out loud, \
    unless the original is already in their script (then leave it empty).
    3. EXPLAIN. One or two plain sentences per dish: what it is, how it's \
    cooked, and what a first-timer would want to know (served cold, shareable, \
    very rich, bone-in). Use your knowledge of the cuisine to fill in what the \
    menu leaves unsaid — a menu that just says "Khachapuri" still gets a real \
    description.
    4. FLAG. List likely ingredients and allergens even when the menu doesn't \
    state them, based on how the dish is standardly made.
    5. SCORE. Rate every dish 0–100 for how well it fits the specific diner \
    described in the user message, and say why in one short sentence addressed \
    to them ("Smoky and properly hot, which is what you're after").

    Rules that matter:

    - Allergies are safety-critical. If a dish plausibly contains one of the \
    diner's allergens, put a clear warning in `warnings` and cap its \
    match_score at 10, naming the ingredient. Include dishes where the \
    allergen is likely-but-unconfirmed and word the warning to reflect that — \
    do not silently drop them.
    - Diet conflicts (meat for a vegetarian, pork for halal) also go in \
    `warnings` with a capped score. Everything else leaves `warnings` empty.
    - Their dining history, when present, is real evidence and outweighs their \
    stated preferences. Reference it directly in `match_reason` when it \
    applies — "you gave the pork belly 5 stars" beats "matches your taste".
    - Never invent a dish, price, or section that is not in the photo. \
    Inference is for how a named dish is made, never for what is on offer.
    - Copy prices exactly as printed. Empty string when a dish has no price.
    - Spread the scores out. If everything lands between 70 and 80 the ranking \
    is useless — the diner needs a clear best choice.
    - `image_search_query` must be in English and specific enough to return the \
    real dish: romanised name plus cuisine, e.g. "bun cha hanoi vietnamese \
    grilled pork noodles". Never just "noodles".
    - Preserve the menu's own section structure and order. If it has no \
    sections, return a single section named for what the items are.
    """

    private static func userPrompt(preferences: UserPreferences, memory: TasteMemory) -> String {
        var prompt = """
        Here is a photo of the menu in front of me. Read it and tell me what I \
        should order.

        About me:
        \(preferences.promptDescription)
        """

        let history = memory.promptDescription
        if !history.isEmpty {
            prompt += "\n\n" + history
        }

        prompt += """


        Translate every dish name, section heading, and description into \
        \(preferences.displayLanguageName). Leave `original_name` in the menu's \
        own script.
        """
        return prompt
    }

    // MARK: - Schema
    //
    // Structured outputs require `additionalProperties: false` and every
    // property listed in `required` on each object.

    private static let dishSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": [
            "original_name", "translated_name", "pronunciation", "description",
            "price", "cuisine", "ingredients", "allergens", "dietary_tags",
            "spice_level", "match_score", "match_reason", "warnings",
            "image_search_query", "health_score", "heaviness",
        ],
        "properties": [
            "original_name": ["type": "string", "description": "The dish name exactly as printed, in the menu's own script."],
            "translated_name": ["type": "string", "description": "Natural-sounding name in the diner's language."],
            "pronunciation": ["type": "string", "description": "Rough phonetic hint. Empty if the original is already in the diner's script."],
            "description": ["type": "string", "description": "One or two sentences on what the dish actually is."],
            "price": ["type": "string", "description": "Price exactly as printed including currency symbol, or empty string."],
            "cuisine": ["type": "string", "description": "Cuisine this dish belongs to, one or two words, e.g. Thai, Neapolitan."],
            "ingredients": ["type": "array", "items": ["type": "string"], "description": "Main ingredients, stated or inferred from how the dish is standardly made."],
            "allergens": ["type": "array", "items": ["type": "string"], "description": "Allergens likely present, e.g. peanuts, dairy, gluten, shellfish."],
            "dietary_tags": ["type": "array", "items": ["type": "string"], "description": "Tags such as vegetarian, vegan, contains-pork, raw, gluten-free."],
            "spice_level": ["type": "integer", "description": "0 not spicy, 1 mild, 2 medium, 3 very hot."],
            "match_score": ["type": "integer", "description": "0-100 fit for this diner. Capped at 10 when warnings is non-empty."],
            "match_reason": ["type": "string", "description": "One short sentence addressed to the diner explaining the score."],
            "warnings": ["type": "array", "items": ["type": "string"], "description": "Allergy or diet conflicts. Empty when the dish is safe for them."],
            "image_search_query": ["type": "string", "description": "English photo-search query specific to this dish and cuisine."],
            "health_score": ["type": "integer", "description": "How healthy the dish is, 1 indulgent to 10 very healthy."],
            "heaviness": ["type": "integer", "description": "1 light, 2 medium, 3 heavy and filling."],
        ],
    ]

    private static var menuSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["detected_languages", "restaurant_name", "currency", "summary", "sections"],
            "properties": [
                "detected_languages": ["type": "array", "items": ["type": "string"], "description": "Languages found on the menu, as English names."],
                "restaurant_name": ["type": "string", "description": "Restaurant name if visible, otherwise empty string."],
                "currency": ["type": "string", "description": "Currency the prices are in. Empty string if undeterminable."],
                "summary": ["type": "string", "description": "One or two sentences on what kind of place this is."],
                "sections": [
                    "type": "array",
                    "description": "Menu sections in the order they appear.",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["name", "original_name", "dishes"],
                        "properties": [
                            "name": ["type": "string", "description": "Section heading translated into the diner's language."],
                            "original_name": ["type": "string", "description": "Section heading exactly as printed."],
                            "dishes": ["type": "array", "items": dishSchema],
                        ],
                    ],
                ],
            ],
        ]
    }
}
