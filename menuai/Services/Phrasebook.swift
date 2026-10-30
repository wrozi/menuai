//
//  Phrasebook.swift
//  menuai
//
//  The sentence you hold up to the waiter, in the language the menu is
//  printed in. Pure tables: no model is involved, so it works offline and
//  can never invent an allergy or drop one.
//
//  The translations were written by hand and have not been checked by a
//  native speaker. Do that before release; an allergy sentence that reads
//  wrong is worse than none.
//

import Foundation
import NaturalLanguage

enum Phrasebook {
    /// One language's worth of sentences.
    struct Table {
        /// "I'd like to order", framing the dish name beneath it.
        let order: String
        /// Contains `{item}` once or twice.
        let singular: String
        /// Contains `{list}`.
        let plural: String
        /// Between every item but the last two.
        let joiner: String
        /// Between the last two items, spaces included where the language
        /// wants them ("א ו" attaches, " and " does not).
        let and: String
        let nouns: [CommonAllergen: String]
        /// No line for `.omnivore`.
        let diets: [Diet: String]

        /// The allergy sentence for these allergens, custom ones verbatim.
        func allergySentence(for allergens: [String]) -> String? {
            let names = allergens.map { noun(for: $0) }
            guard let first = names.first else { return nil }
            if names.count == 1 {
                return singular.replacingOccurrences(of: "{item}", with: first)
            }
            let list = names.dropLast().joined(separator: joiner) + and + names[names.count - 1]
            return plural.replacingOccurrences(of: "{list}", with: list)
        }

        private func noun(for allergen: String) -> String {
            let key = allergen.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let common = CommonAllergen(rawValue: key), let noun = nouns[common] {
                return noun
            }
            return allergen.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: - Which language

    /// A BCP-47 code for the language the menu is printed in. Reads the
    /// engine's detected language first (Claude gives an English name, an
    /// older build a code); when there is none, which is always the case
    /// on-device, it recognises the language from the printed names.
    static func language(for menu: ParsedMenu) -> String {
        let sample = (menu.sections.map(\.originalName) + menu.allDishes.map(\.originalName))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        if let first = menu.detectedLanguages.first?.trimmingCharacters(in: .whitespacesAndNewlines),
           !first.isEmpty {
            if let code = canonical(first, sample: sample) { return code }
            if let code = code(forEnglishName: first, sample: sample) { return code }
        }

        guard let dominant = recognise(sample) else { return "en" }
        return canonical(dominant, sample: sample) ?? dominant
    }

    /// The line above the dish name, in the menu's language. English for a
    /// language the tables don't cover.
    static func orderLine(language: String) -> String {
        (canonical(language, sample: "").flatMap { tables[$0] } ?? tables["en"]!).order
    }

    /// The card's sentence in the menu's language and in English. Nil when
    /// there is nothing to tell the waiter. An unknown language gives the
    /// English sentence in both halves. Each half holds one statement per
    /// line: the allergies, then the diet.
    static func waiterLine(allergens: [String], diet: Diet, language: String) -> (local: String, english: String)? {
        var seen = Set<String>()
        let cleaned = allergens
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }

        let english = tables["en"]!
        let local = canonical(language, sample: "").flatMap { tables[$0] } ?? english

        var localLines: [String] = []
        var englishLines: [String] = []

        if let line = local.allergySentence(for: cleaned), let plain = english.allergySentence(for: cleaned) {
            localLines.append(line)
            englishLines.append(plain)
        }
        if let line = local.diets[diet], let plain = english.diets[diet] {
            localLines.append(line)
            englishLines.append(plain)
        }

        guard !localLines.isEmpty else { return nil }
        return (localLines.joined(separator: "\n"), englishLines.joined(separator: "\n"))
    }

    // MARK: - Code handling

    /// A code as one of ours: case-insensitive, regional variants folded
    /// ("pt-BR" → "pt"), and bare "zh" decided by script when a sample is
    /// available.
    private static func canonical(_ raw: String, sample: String) -> String? {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "_", with: "-")
        guard !code.isEmpty else { return nil }

        switch code {
        case "zh-hans", "zh-cn", "zh-sg", "zh-hans-cn": return "zh-Hans"
        case "zh-hant", "zh-tw", "zh-hk", "zh-mo", "zh-hant-tw", "yue": return "zh-Hant"
        case "zh": return chineseScript(in: sample)
        case "iw": return "he"
        default: break
        }

        let base = String(code.split(separator: "-").first ?? Substring(code))
        return tables.keys.first { $0.lowercased() == base }
    }

    /// "Italian" → "it". The names Claude is asked for, plus a few aliases.
    private static func code(forEnglishName raw: String, sample: String) -> String? {
        let name = raw.lowercased()
        if let exact = names[name] { return exact == "zh" ? chineseScript(in: sample) : exact }
        // "Italian (with English)": the first name mentioned wins.
        let hit = names.keys
            .compactMap { key -> (Int, String)? in
                guard let range = name.range(of: key) else { return nil }
                return (name.distance(from: name.startIndex, to: range.lowerBound), key)
            }
            .min { $0.0 < $1.0 }
        guard let hit, let code = names[hit.1] else { return nil }
        return code == "zh" ? chineseScript(in: sample) : code
    }

    private static let names: [String: String] = [
        "english": "en", "italian": "it", "spanish": "es", "castilian": "es", "french": "fr",
        "german": "de", "portuguese": "pt", "brazilian portuguese": "pt", "dutch": "nl",
        "flemish": "nl", "greek": "el", "turkish": "tr", "hebrew": "he", "arabic": "ar",
        "japanese": "ja", "chinese": "zh", "mandarin": "zh", "simplified chinese": "zh-Hans",
        "chinese (simplified)": "zh-Hans", "traditional chinese": "zh-Hant",
        "chinese (traditional)": "zh-Hant", "cantonese": "zh-Hant", "korean": "ko",
        "thai": "th", "vietnamese": "vi", "polish": "pl", "russian": "ru",
    ]

    private static func chineseScript(in sample: String) -> String {
        recognise(sample) == "zh-Hant" ? "zh-Hant" : "zh-Hans"
    }

    private static func recognise(_ sample: String) -> String? {
        guard !sample.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        return recognizer.dominantLanguage?.rawValue
    }

    // MARK: - Tables
    //
    // Written by hand, not yet verified by native speakers. Every line is
    // phrased so it does not inflect for the speaker: "I have an allergy",
    // "vegetarian diet", never "allergico/a". A card is read across a table
    // by a stranger, and a slash there looks like a form, not a sentence.
    // Where a language inflects the noun for case, the form that fits both
    // slots is used, with a colon before the list where that is what makes
    // it fit. In a script with letter case no template starts with `{item}`,
    // so a sentence never opens with a lowercase noun.

    static let tables: [String: Table] = [
        "en": Table(
            order: "I'd like to order",
            singular: "I'm allergic to {item}. Does this contain {item}?",
            plural: "I'm allergic to {list}. Does this contain any of these?",
            joiner: ", ", and: " and ",
            nouns: [
                .peanuts: "peanuts", .treeNuts: "tree nuts", .dairy: "dairy", .eggs: "eggs",
                .gluten: "gluten", .shellfish: "shellfish", .fish: "fish", .soy: "soy",
                .sesame: "sesame", .mustard: "mustard", .celery: "celery", .sulfites: "sulfites",
            ],
            diets: [
                .vegetarian: "I'm vegetarian — no meat or fish.",
                .vegan: "I'm vegan — no meat, fish, eggs or dairy.",
                .pescatarian: "I don't eat meat, but fish is fine.",
                .halal: "I eat halal — no pork and no alcohol.",
                .kosher: "I eat kosher — no pork or shellfish, and no meat with dairy.",
            ]
        ),
        "it": Table(
            order: "Vorrei ordinare",
            singular: "Ho un'allergia a: {item}. Questo piatto contiene {item}?",
            plural: "Ho delle allergie a: {list}. Questo piatto contiene uno di questi?",
            joiner: ", ", and: " e ",
            nouns: [
                .peanuts: "arachidi", .treeNuts: "frutta a guscio", .dairy: "latticini", .eggs: "uova",
                .gluten: "glutine", .shellfish: "crostacei", .fish: "pesce", .soy: "soia",
                .sesame: "sesamo", .mustard: "senape", .celery: "sedano", .sulfites: "solfiti",
            ],
            diets: [
                .vegetarian: "Dieta vegetariana: niente carne né pesce.",
                .vegan: "Dieta vegana: niente carne, pesce, uova né latticini.",
                .pescatarian: "Non mangio carne, ma il pesce va bene.",
                .halal: "Mangio halal: niente maiale e niente alcol.",
                .kosher: "Mangio kosher: niente maiale né frutti di mare, e niente carne con latticini.",
            ]
        ),
        "es": Table(
            order: "Quisiera pedir",
            singular: "Tengo alergia a: {item}. ¿Este plato contiene {item}?",
            plural: "Tengo alergia a: {list}. ¿Este plato contiene alguno de estos?",
            joiner: ", ", and: " y ",
            nouns: [
                .peanuts: "cacahuetes", .treeNuts: "frutos secos", .dairy: "lácteos", .eggs: "huevos",
                .gluten: "gluten", .shellfish: "mariscos", .fish: "pescado", .soy: "soja",
                .sesame: "sésamo", .mustard: "mostaza", .celery: "apio", .sulfites: "sulfitos",
            ],
            diets: [
                .vegetarian: "Dieta vegetariana: sin carne ni pescado.",
                .vegan: "Dieta vegana: sin carne, pescado, huevos ni lácteos.",
                .pescatarian: "No como carne, pero el pescado está bien.",
                .halal: "Como halal: sin cerdo y sin alcohol.",
                .kosher: "Como kosher: sin cerdo ni mariscos, y sin carne con lácteos.",
            ]
        ),
        "fr": Table(
            order: "Je voudrais commander",
            singular: "J'ai une allergie : {item}. Est-ce que ce plat en contient ?",
            plural: "J'ai des allergies : {list}. Est-ce que ce plat contient l'un de ces ingrédients ?",
            joiner: ", ", and: " et ",
            nouns: [
                .peanuts: "arachides", .treeNuts: "fruits à coque", .dairy: "produits laitiers", .eggs: "œufs",
                .gluten: "gluten", .shellfish: "crustacés", .fish: "poisson", .soy: "soja",
                .sesame: "sésame", .mustard: "moutarde", .celery: "céleri", .sulfites: "sulfites",
            ],
            diets: [
                .vegetarian: "Régime végétarien : pas de viande ni de poisson.",
                .vegan: "Régime végétalien : pas de viande, de poisson, d'œufs ni de produits laitiers.",
                .pescatarian: "Je ne mange pas de viande, mais le poisson, ça va.",
                .halal: "Je mange halal : pas de porc et pas d'alcool.",
                .kosher: "Je mange casher : pas de porc ni de fruits de mer, et pas de viande avec des produits laitiers.",
            ]
        ),
        "de": Table(
            order: "Ich hätte gern",
            singular: "Ich bin allergisch gegen {item}. Enthält dieses Gericht {item}?",
            plural: "Ich bin allergisch gegen {list}. Enthält dieses Gericht etwas davon?",
            joiner: ", ", and: " und ",
            nouns: [
                .peanuts: "Erdnüsse", .treeNuts: "Nüsse", .dairy: "Milchprodukte", .eggs: "Eier",
                .gluten: "Gluten", .shellfish: "Schalentiere", .fish: "Fisch", .soy: "Soja",
                .sesame: "Sesam", .mustard: "Senf", .celery: "Sellerie", .sulfites: "Sulfite",
            ],
            diets: [
                .vegetarian: "Ich esse vegetarisch: kein Fleisch und kein Fisch.",
                .vegan: "Ich esse vegan: kein Fleisch, kein Fisch, keine Eier, keine Milchprodukte.",
                .pescatarian: "Ich esse kein Fleisch, aber Fisch ist in Ordnung.",
                .halal: "Ich esse halal: kein Schweinefleisch und kein Alkohol.",
                .kosher: "Ich esse koscher: kein Schweinefleisch, keine Meeresfrüchte und kein Fleisch zusammen mit Milchprodukten.",
            ]
        ),
        "pt": Table(
            order: "Queria pedir",
            singular: "Tenho alergia a: {item}. Este prato contém {item}?",
            plural: "Tenho alergia a: {list}. Este prato contém algum destes?",
            joiner: ", ", and: " e ",
            nouns: [
                .peanuts: "amendoim", .treeNuts: "frutos secos", .dairy: "laticínios", .eggs: "ovos",
                .gluten: "glúten", .shellfish: "marisco", .fish: "peixe", .soy: "soja",
                .sesame: "sésamo (gergelim)", .mustard: "mostarda", .celery: "aipo", .sulfites: "sulfitos",
            ],
            diets: [
                .vegetarian: "Dieta vegetariana: sem carne nem peixe.",
                .vegan: "Dieta vegana: sem carne, peixe, ovos nem laticínios.",
                .pescatarian: "Não como carne, mas peixe pode.",
                .halal: "Como halal: sem porco e sem álcool.",
                .kosher: "Como kosher: sem porco nem marisco, e sem carne com laticínios.",
            ]
        ),
        "nl": Table(
            order: "Ik wil graag bestellen",
            singular: "Ik ben allergisch voor {item}. Bevat dit gerecht {item}?",
            plural: "Ik ben allergisch voor {list}. Bevat dit gerecht iets daarvan?",
            joiner: ", ", and: " en ",
            nouns: [
                .peanuts: "pinda's", .treeNuts: "noten", .dairy: "zuivel", .eggs: "eieren",
                .gluten: "gluten", .shellfish: "schaaldieren", .fish: "vis", .soy: "soja",
                .sesame: "sesam", .mustard: "mosterd", .celery: "selderij", .sulfites: "sulfieten",
            ],
            diets: [
                .vegetarian: "Ik ben vegetariër: geen vlees en geen vis.",
                .vegan: "Ik ben veganist: geen vlees, vis, eieren of zuivel.",
                .pescatarian: "Ik eet geen vlees, maar vis is prima.",
                .halal: "Ik eet halal: geen varkensvlees en geen alcohol.",
                .kosher: "Ik eet koosjer: geen varkensvlees of schaaldieren, en geen vlees met zuivel.",
            ]
        ),
        "el": Table(
            order: "Θα ήθελα να παραγγείλω",
            singular: "Έχω αλλεργία σε: {item}. Περιέχει αυτό το πιάτο {item};",
            plural: "Έχω αλλεργία σε: {list}. Περιέχει αυτό το πιάτο κάτι από αυτά;",
            joiner: ", ", and: " και ",
            nouns: [
                .peanuts: "φιστίκια", .treeNuts: "ξηροί καρποί", .dairy: "γαλακτοκομικά", .eggs: "αυγά",
                .gluten: "γλουτένη", .shellfish: "οστρακοειδή", .fish: "ψάρι", .soy: "σόγια",
                .sesame: "σουσάμι", .mustard: "μουστάρδα", .celery: "σέλινο", .sulfites: "θειώδη",
            ],
            diets: [
                .vegetarian: "Είμαι χορτοφάγος: χωρίς κρέας και ψάρι.",
                .vegan: "Είμαι βίγκαν: χωρίς κρέας, ψάρι, αυγά ή γαλακτοκομικά.",
                .pescatarian: "Δεν τρώω κρέας, αλλά το ψάρι είναι εντάξει.",
                .halal: "Τρώω χαλάλ: χωρίς χοιρινό και χωρίς αλκοόλ.",
                .kosher: "Τρώω κοσέρ: χωρίς χοιρινό ή θαλασσινά, και χωρίς κρέας μαζί με γαλακτοκομικά.",
            ]
        ),
        "tr": Table(
            order: "Bunu istiyorum",
            singular: "Şuna alerjim var: {item}. Bu yemekte {item} var mı?",
            plural: "Şunlara alerjim var: {list}. Bu yemekte bunlardan biri var mı?",
            joiner: ", ", and: " ve ",
            nouns: [
                .peanuts: "yer fıstığı", .treeNuts: "kuruyemiş", .dairy: "süt ürünleri", .eggs: "yumurta",
                .gluten: "glüten", .shellfish: "kabuklu deniz ürünleri", .fish: "balık", .soy: "soya",
                .sesame: "susam", .mustard: "hardal", .celery: "kereviz", .sulfites: "sülfitler",
            ],
            diets: [
                .vegetarian: "Vejetaryenim: et ve balık yemiyorum.",
                .vegan: "Veganım: et, balık, yumurta ve süt ürünleri yemiyorum.",
                .pescatarian: "Et yemiyorum ama balık olur.",
                .halal: "Helal yiyorum: domuz eti ve alkol yok.",
                .kosher: "Koşer yiyorum: domuz eti ve kabuklu deniz ürünleri yok, et ile süt ürünleri bir arada yok.",
            ]
        ),
        "he": Table(
            order: "אני רוצה להזמין",
            singular: "יש לי אלרגיה ל{item}. האם המנה הזאת מכילה {item}?",
            plural: "יש לי אלרגיה ל: {list}. האם המנה הזאת מכילה משהו מזה?",
            joiner: ", ", and: " ו",
            nouns: [
                .peanuts: "בוטנים", .treeNuts: "אגוזים", .dairy: "מוצרי חלב", .eggs: "ביצים",
                .gluten: "גלוטן", .shellfish: "פירות ים", .fish: "דגים", .soy: "סויה",
                .sesame: "שומשום", .mustard: "חרדל", .celery: "סלרי", .sulfites: "סולפיטים",
            ],
            diets: [
                .vegetarian: "תזונה צמחונית: בלי בשר ובלי דגים.",
                .vegan: "תזונה טבעונית: בלי בשר, דגים, ביצים או מוצרי חלב.",
                .pescatarian: "בלי בשר, אבל דגים זה בסדר.",
                .halal: "חלאל: בלי חזיר ובלי אלכוהול.",
                .kosher: "כשר: בלי חזיר ופירות ים, ובלי בשר עם חלב.",
            ]
        ),
        "ar": Table(
            order: "أريد أن أطلب",
            singular: "لدي حساسية من {item}. هل يحتوي هذا الطبق على {item}؟",
            plural: "لدي حساسية من: {list}. هل يحتوي هذا الطبق على أي منها؟",
            joiner: "، ", and: " و",
            nouns: [
                .peanuts: "الفول السوداني", .treeNuts: "المكسرات", .dairy: "منتجات الألبان", .eggs: "البيض",
                .gluten: "الغلوتين", .shellfish: "المحار", .fish: "السمك", .soy: "الصويا",
                .sesame: "السمسم", .mustard: "الخردل", .celery: "الكرفس", .sulfites: "الكبريتيت",
            ],
            diets: [
                .vegetarian: "نظام نباتي: لا لحم ولا سمك.",
                .vegan: "نظام نباتي صرف: لا لحم ولا سمك ولا بيض ولا منتجات ألبان.",
                .pescatarian: "لا آكل اللحم، لكن السمك مناسب.",
                .halal: "آكل حلال: لا لحم خنزير ولا كحول.",
                .kosher: "آكل كوشر: لا لحم خنزير ولا محار، ولا لحم مع منتجات الألبان.",
            ]
        ),
        "ja": Table(
            order: "これをお願いします",
            singular: "{item}にアレルギーがあります。この料理に{item}は入っていますか？",
            plural: "{list}にアレルギーがあります。この料理にこれらは入っていますか？",
            joiner: "、", and: "と",
            nouns: [
                .peanuts: "ピーナッツ", .treeNuts: "ナッツ類", .dairy: "乳製品", .eggs: "卵",
                .gluten: "グルテン", .shellfish: "甲殻類", .fish: "魚", .soy: "大豆",
                .sesame: "ごま", .mustard: "マスタード", .celery: "セロリ", .sulfites: "亜硫酸塩",
            ],
            diets: [
                .vegetarian: "ベジタリアンです。肉と魚は食べません。",
                .vegan: "ヴィーガンです。肉、魚、卵、乳製品は食べません。",
                .pescatarian: "肉は食べませんが、魚は大丈夫です。",
                .halal: "ハラールです。豚肉とアルコールは食べません。",
                .kosher: "コーシャです。豚肉と甲殻類は食べません。肉と乳製品を一緒に食べません。",
            ]
        ),
        "zh-Hans": Table(
            order: "我想点这个",
            singular: "我对{item}过敏。这道菜含有{item}吗？",
            plural: "我对{list}过敏。这道菜含有其中任何一种吗？",
            joiner: "、", and: "和",
            nouns: [
                .peanuts: "花生", .treeNuts: "坚果", .dairy: "奶制品", .eggs: "鸡蛋",
                .gluten: "麸质", .shellfish: "贝类", .fish: "鱼", .soy: "大豆",
                .sesame: "芝麻", .mustard: "芥末", .celery: "芹菜", .sulfites: "亚硫酸盐",
            ],
            diets: [
                .vegetarian: "我是素食者，不吃肉和鱼。",
                .vegan: "我是纯素食者，不吃肉、鱼、蛋和奶制品。",
                .pescatarian: "我不吃肉，但可以吃鱼。",
                .halal: "我吃清真食品，不吃猪肉，不喝酒。",
                .kosher: "我吃犹太洁食，不吃猪肉和贝类，肉和奶制品不能一起吃。",
            ]
        ),
        "zh-Hant": Table(
            order: "我想點這個",
            singular: "我對{item}過敏。這道菜含有{item}嗎？",
            plural: "我對{list}過敏。這道菜含有其中任何一種嗎？",
            joiner: "、", and: "和",
            nouns: [
                .peanuts: "花生", .treeNuts: "堅果", .dairy: "乳製品", .eggs: "雞蛋",
                .gluten: "麩質", .shellfish: "貝類", .fish: "魚", .soy: "大豆",
                .sesame: "芝麻", .mustard: "芥末", .celery: "芹菜", .sulfites: "亞硫酸鹽",
            ],
            diets: [
                .vegetarian: "我是素食者，不吃肉和魚。",
                .vegan: "我是純素食者，不吃肉、魚、蛋和乳製品。",
                .pescatarian: "我不吃肉，但可以吃魚。",
                .halal: "我吃清真食品，不吃豬肉，不喝酒。",
                .kosher: "我吃猶太潔食，不吃豬肉和貝類，肉和乳製品不能一起吃。",
            ]
        ),
        "ko": Table(
            order: "이것으로 주문할게요",
            singular: "저는 {item}에 알레르기가 있습니다. 이 음식에 {item}이(가) 들어 있나요?",
            plural: "저는 {list}에 알레르기가 있습니다. 이 음식에 이 중 하나라도 들어 있나요?",
            joiner: ", ", and: " 및 ",
            nouns: [
                .peanuts: "땅콩", .treeNuts: "견과류", .dairy: "유제품", .eggs: "달걀",
                .gluten: "글루텐", .shellfish: "갑각류", .fish: "생선", .soy: "콩",
                .sesame: "참깨", .mustard: "겨자", .celery: "셀러리", .sulfites: "아황산염",
            ],
            diets: [
                .vegetarian: "저는 채식주의자입니다. 고기와 생선을 먹지 않습니다.",
                .vegan: "저는 비건입니다. 고기, 생선, 달걀, 유제품을 먹지 않습니다.",
                .pescatarian: "고기는 안 먹지만 생선은 괜찮습니다.",
                .halal: "저는 할랄 음식만 먹습니다. 돼지고기와 술은 안 됩니다.",
                .kosher: "저는 코셔 음식만 먹습니다. 돼지고기와 갑각류는 안 되고, 고기와 유제품을 함께 먹지 않습니다.",
            ]
        ),
        "th": Table(
            order: "ขอสั่งอันนี้",
            singular: "ฉันแพ้{item} อาหารจานนี้มี{item}ไหม",
            plural: "ฉันแพ้{list} อาหารจานนี้มีส่วนผสมเหล่านี้ไหม",
            joiner: " ", and: " และ",
            nouns: [
                .peanuts: "ถั่วลิสง", .treeNuts: "ถั่วเปลือกแข็ง", .dairy: "ผลิตภัณฑ์นม", .eggs: "ไข่",
                .gluten: "กลูเตน", .shellfish: "กุ้งหอยปู", .fish: "ปลา", .soy: "ถั่วเหลือง",
                .sesame: "งา", .mustard: "มัสตาร์ด", .celery: "ขึ้นฉ่าย", .sulfites: "ซัลไฟต์",
            ],
            diets: [
                .vegetarian: "ฉันกินมังสวิรัติ ไม่กินเนื้อสัตว์และปลา",
                .vegan: "ฉันกินวีแกน ไม่กินเนื้อสัตว์ ปลา ไข่ และผลิตภัณฑ์นม",
                .pescatarian: "ฉันไม่กินเนื้อสัตว์ แต่กินปลาได้",
                .halal: "ฉันกินฮาลาล ไม่กินหมูและไม่ดื่มแอลกอฮอล์",
                .kosher: "ฉันกินโคเชอร์ ไม่กินหมูและกุ้งหอยปู และไม่กินเนื้อสัตว์กับนมด้วยกัน",
            ]
        ),
        "vi": Table(
            order: "Tôi muốn gọi món này",
            singular: "Tôi bị dị ứng với {item}. Món này có {item} không?",
            plural: "Tôi bị dị ứng với {list}. Món này có chứa thứ nào trong số đó không?",
            joiner: ", ", and: " và ",
            nouns: [
                .peanuts: "đậu phộng", .treeNuts: "các loại hạt", .dairy: "sữa và sản phẩm từ sữa", .eggs: "trứng",
                .gluten: "gluten", .shellfish: "động vật có vỏ", .fish: "cá", .soy: "đậu nành",
                .sesame: "mè", .mustard: "mù tạt", .celery: "cần tây", .sulfites: "sulfite",
            ],
            diets: [
                .vegetarian: "Tôi ăn chay: không thịt, không cá.",
                .vegan: "Tôi ăn thuần chay: không thịt, cá, trứng hay sữa.",
                .pescatarian: "Tôi không ăn thịt, nhưng cá thì được.",
                .halal: "Tôi ăn halal: không thịt heo và không rượu bia.",
                .kosher: "Tôi ăn kosher: không thịt heo, không hải sản có vỏ, và không ăn thịt cùng với sữa.",
            ]
        ),
        "pl": Table(
            order: "Poproszę",
            singular: "Mam alergię na {item}. Czy to danie zawiera {item}?",
            plural: "Mam alergię na: {list}. Czy to danie zawiera coś z tego?",
            joiner: ", ", and: " i ",
            nouns: [
                .peanuts: "orzeszki ziemne", .treeNuts: "orzechy", .dairy: "nabiał", .eggs: "jaja",
                .gluten: "gluten", .shellfish: "skorupiaki", .fish: "ryby", .soy: "soję",
                .sesame: "sezam", .mustard: "gorczycę", .celery: "seler", .sulfites: "siarczyny",
            ],
            diets: [
                .vegetarian: "Dieta wegetariańska: bez mięsa i ryb.",
                .vegan: "Dieta wegańska: bez mięsa, ryb, jaj i nabiału.",
                .pescatarian: "Nie jem mięsa, ale ryby mogą być.",
                .halal: "Jem halal: bez wieprzowiny i bez alkoholu.",
                .kosher: "Jem koszernie: bez wieprzowiny i owoców morza, i bez mięsa z nabiałem.",
            ]
        ),
        "ru": Table(
            order: "Мне, пожалуйста",
            singular: "У меня аллергия на: {item}. В этом блюде есть {item}?",
            plural: "У меня аллергия на: {list}. В этом блюде есть что-то из этого?",
            joiner: ", ", and: " и ",
            nouns: [
                .peanuts: "арахис", .treeNuts: "орехи", .dairy: "молочные продукты", .eggs: "яйца",
                .gluten: "глютен", .shellfish: "моллюски", .fish: "рыба", .soy: "соя",
                .sesame: "кунжут", .mustard: "горчица", .celery: "сельдерей", .sulfites: "сульфиты",
            ],
            diets: [
                .vegetarian: "Вегетарианская диета: без мяса и рыбы.",
                .vegan: "Веганская диета: без мяса, рыбы, яиц и молочных продуктов.",
                .pescatarian: "Я не ем мясо, но рыба подходит.",
                .halal: "Я ем халяль: без свинины и без алкоголя.",
                .kosher: "Я ем кошерное: без свинины и морепродуктов, и без мяса с молочным.",
            ]
        ),
    ]
}
