//
//  AppStore.swift
//  menuai
//

import Foundation
import Observation
import PhotosUI
import SwiftUI

@Observable
@MainActor
final class AppStore {
    enum ScanState: Equatable {
        case idle
        case analyzing(progress: Double, message: String)
        case failed(String)

        var isAnalyzing: Bool {
            if case .analyzing = self { return true }
            return false
        }
    }

    private static let preferencesKey = "menuai.preferences.v1"

    var preferences: UserPreferences {
        didSet { persistPreferences() }
    }

    var apiKey: String {
        didSet { Keychain.writeAPIKey(apiKey) }
    }

    var scanState: ScanState = .idle
    /// True while a page is being added to an open menu rather than a new
    /// menu being read; the failure alert is titled accordingly.
    var isAddingPage = false
    /// A new menu being read. Home shows it inline as a processing card; a
    /// page added from the menu screen takes the full-screen view instead.
    var isReadingNewMenu: Bool { scanState.isAnalyzing && !isAddingPage }
    var savedMenus: [ParsedMenu] = []
    var orders: [OrderedDish] = []
    var diners: [Diner] = [] {
        didSet { DinerStore.save(diners) }
    }

    /// Set when a read finishes. RootView pushes it when the user is still
    /// on Home; otherwise it waits in Recent and RootView just clears this.
    var activeMenu: ParsedMenu?

    /// The photo being analysed, shown behind the progress UI.
    var pendingImage: UIImage?

    /// Set when a page has been merged into the menu currently on screen.
    var mergedMenu: ParsedMenu?

    /// Set by Home's camera card and "Choose a photo", and again by "Try again"
    /// after a failure; CaptureFlow picks it up and opens the camera or the
    /// photo picker.
    var captureRequest: CaptureSource?

    /// Set when a capture is refused because Apple Intelligence isn't ready;
    /// the failure alert is titled accordingly.
    var notReady = false

    var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// What the app has learned from what the user actually ordered.
    var memory: TasteMemory { TasteMemory(orders: orders) }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.preferencesKey),
           let decoded = try? JSONDecoder().decode(UserPreferences.self, from: data) {
            preferences = decoded
        } else {
            preferences = UserPreferences()
        }
        apiKey = Keychain.readAPIKey() ?? ""
        savedMenus = ScanStore.load()
        orders = OrderStore.load()
        diners = DinerStore.load()
        // Stored before the chip label went sentence case; without this an old
        // value renders as a custom chip beside the common one.
        preferences.allergies = preferences.allergies.map { $0 == "Tree Nuts" ? "Tree nuts" : $0 }
        diners = diners.map { diner in
            var diner = diner
            diner.allergies = diner.allergies.map { $0 == "Tree Nuts" ? "Tree nuts" : $0 }
            return diner
        }
    }

    // MARK: - Scanning

    func analyze(image: UIImage) async {
        let hold = BackgroundHold(name: "Reading a menu")
        defer { hold.end() }

        isAddingPage = false
        pendingImage = image
        // The engine's own first status is "Reading the menu…"; opening
        // with a different verb keeps the card's two lines from doubling.
        scanState = .analyzing(progress: 0.03, message: "Opening the photo…")

        let engine: MenuEngine
        do {
            engine = try EngineRouter.select(apiKey: apiKey)
        } catch {
            pendingImage = nil
            Haptic.warning()
            scanState = .failed(error.localizedDescription)
            return
        }

        // Shrink the capture once, off the main thread, so the engines and the
        // thumbnail never redraw 12 MP under the analysing screen's animation.
        let prepared = await Task.detached(priority: .userInitiated) {
            ImageProcessing.resized(image, maxDimension: ImageProcessing.maxDimension)
        }.value
        pendingImage = prepared

        // The thumbnail needs only the photo, so it is written while the
        // engine reads it.
        async let thumbnail = Task.detached(priority: .utility) {
            ScanStore.saveThumbnail(prepared)
        }.value

        do {
            var menu = try await engine.analyze(
                image: prepared,
                preferences: preferences,
                memory: memory,
                onProgress: { [weak self] progress, message in
                    self?.scanState = .analyzing(progress: progress, message: message)
                }
            )
            menu.scannedAt = .now
            menu.imageFileName = await thumbnail

            savedMenus.insert(menu, at: 0)
            // Keep the on-disk history bounded; parsed menus are large.
            if savedMenus.count > 25 {
                for dropped in savedMenus.suffix(from: 25) {
                    if let name = dropped.imageFileName { ScanStore.deleteThumbnail(named: name) }
                }
                savedMenus = Array(savedMenus.prefix(25))
            }
            persistMenus()

            if case let .analyzing(_, message) = scanState {
                scanState = .analyzing(progress: 1, message: message)
            }
            try? await Task.sleep(for: .milliseconds(400))
            Haptic.success()
            activeMenu = menu
            pendingImage = nil
            scanState = .idle
        } catch {
            // Nothing references the thumbnail now.
            if let name = await thumbnail { ScanStore.deleteThumbnail(named: name) }
            Haptic.warning()
            pendingImage = nil
            scanState = .failed(error.localizedDescription)
        }
    }

    /// A library pick, decoded before it is read; a page when `menu` is given.
    func analyze(_ item: PhotosPickerItem, addingTo menu: ParsedMenu? = nil) async {
        isAddingPage = menu != nil
        scanState = .analyzing(progress: 0.02, message: "Opening the photo…")
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            Haptic.warning()
            scanState = .failed(EngineError.imageEncodingFailed.localizedDescription)
            return
        }
        if let menu {
            await addPage(image: image, to: menu)
        } else {
            await analyze(image: image)
        }
    }

    func clearError() {
        if case .failed = scanState { scanState = .idle }
        isAddingPage = false
        notReady = false
    }

    func delete(_ menu: ParsedMenu) {
        ThumbnailCache.forget(menu.imageFileName)
        if let name = menu.imageFileName { ScanStore.deleteThumbnail(named: name) }
        savedMenus.removeAll { $0.id == menu.id }
        persistMenus()
    }

    @ObservationIgnored private var menuSave: Task<Void, Never>?

    /// Writes the menu index off the main thread. The newest snapshot always
    /// wins: a write still queued is cancelled, and one already running is
    /// waited for before ours lands.
    private func persistMenus() {
        menuSave?.cancel()
        let previous = menuSave
        let snapshot = savedMenus
        menuSave = Task.detached(priority: .utility) {
            await previous?.value
            guard !Task.isCancelled else { return }
            ScanStore.save(snapshot)
        }
    }

    // MARK: - Orders

    func hasOrdered(_ dish: Dish) -> Bool {
        order(for: dish) != nil
    }

    func order(for dish: Dish) -> OrderedDish? {
        orders.first {
            $0.name == dish.displayName && $0.originalName == dish.originalName
        }
    }

    /// Marks a dish as ordered, or removes it if it already was.
    func toggleOrdered(_ dish: Dish, from menu: ParsedMenu) {
        if let existing = order(for: dish) {
            orders.removeAll { $0.id == existing.id }
            Haptic.tap()
        } else {
            var order = OrderedDish(
                from: dish,
                restaurant: menu.title,
                imageFileName: menu.imageFileName
            )
            if order.cuisineHint.isEmpty { order.cuisineHint = menu.dominantCuisine }
            orders.insert(order, at: 0)
            Haptic.success()
        }
        OrderStore.save(orders)
    }

    func rate(_ order: OrderedDish, stars: Int) {
        guard let index = orders.firstIndex(where: { $0.id == order.id }) else { return }
        orders[index].rating = stars
        OrderStore.save(orders)
    }

    func setNote(_ note: String, for order: OrderedDish) {
        guard let index = orders.firstIndex(where: { $0.id == order.id }) else { return }
        orders[index].note = note
        OrderStore.save(orders)
    }

    func delete(_ order: OrderedDish) {
        orders.removeAll { $0.id == order.id }
        OrderStore.save(orders)
    }

    /// Adds a second (or third) photo to a menu already on screen.
    ///
    /// Restaurants routinely split starters, mains and desserts across pages.
    /// Scanning each one as a separate menu gives separate rankings, so the
    /// best dish on page two never competes with the best on page one — which
    /// is the whole point of the app. Pages are merged into one menu and
    /// ranked together.
    func addPage(image: UIImage, to menu: ParsedMenu) async {
        let hold = BackgroundHold(name: "Reading a menu page")
        defer { hold.end() }

        isAddingPage = true
        pendingImage = image
        scanState = .analyzing(progress: 0.03, message: "Reading the next page…")

        let engine: MenuEngine
        do {
            engine = try EngineRouter.select(apiKey: apiKey)
        } catch {
            pendingImage = nil
            Haptic.warning()
            scanState = .failed(error.localizedDescription)
            return
        }

        let prepared = await Task.detached(priority: .userInitiated) {
            ImageProcessing.resized(image, maxDimension: ImageProcessing.maxDimension)
        }.value
        pendingImage = prepared

        do {
            let page = try await engine.analyze(
                image: prepared,
                preferences: preferences,
                memory: memory,
                onProgress: { [weak self] progress, message in
                    self?.scanState = .analyzing(progress: progress, message: message)
                }
            )

            guard var merged = savedMenus.first(where: { $0.id == menu.id }) ?? activeMenu else {
                pendingImage = nil
                Haptic.warning()
                scanState = .failed("That menu is no longer open.")
                return
            }

            // Skip anything already on a previous page, so an overlapping
            // photo doesn't produce the same dish twice.
            let existing = Set(merged.allDishes.map { Self.matchKey($0.originalName.isEmpty ? $0.displayName : $0.originalName) })
            let freshSections = page.sections.compactMap { section -> MenuSection? in
                let dishes = section.dishes.filter {
                    !existing.contains(Self.matchKey($0.originalName.isEmpty ? $0.displayName : $0.originalName))
                }
                return dishes.isEmpty ? nil : MenuSection(name: section.name, originalName: section.originalName, dishes: dishes)
            }

            guard !freshSections.isEmpty else {
                pendingImage = nil
                Haptic.warning()
                scanState = .failed("Nothing new on that page — those dishes are already here.")
                return
            }

            merged.sections.append(contentsOf: freshSections)
            if merged.restaurantName.isEmpty { merged.restaurantName = page.restaurantName }
            if merged.summary.isEmpty { merged.summary = page.summary }
            if merged.currency.isEmpty { merged.currency = page.currency }

            if let index = savedMenus.firstIndex(where: { $0.id == menu.id }) {
                savedMenus[index] = merged
            } else {
                savedMenus.insert(merged, at: 0)
            }
            persistMenus()

            if case let .analyzing(_, message) = scanState {
                scanState = .analyzing(progress: 1, message: message)
            }
            try? await Task.sleep(for: .milliseconds(400))
            Haptic.success()
            mergedMenu = merged
            pendingImage = nil
            scanState = .idle
            isAddingPage = false
        } catch {
            Haptic.warning()
            pendingImage = nil
            scanState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Memory

    /// A dish you've eaten before, matched loosely enough to survive the
    /// engine naming it slightly differently on a second scan.
    func previousOrder(of dish: Dish, excluding current: UUID? = nil) -> OrderedDish? {
        let key = Self.matchKey(dish.originalName.isEmpty ? dish.displayName : dish.originalName)
        guard !key.isEmpty else { return nil }
        return orders.first {
            $0.id != current && Self.matchKey($0.originalName.isEmpty ? $0.name : $0.originalName) == key
        }
    }

    private static func matchKey(_ name: String) -> String {
        name.lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .filter { $0.isLetter }
    }

    // MARK: - Companions

    /// Re-ranks a menu for someone else at the table. No model call: the
    /// dishes are already parsed, and scoring is deterministic.
    func menu(_ menu: ParsedMenu, scoredFor diner: Diner) -> ParsedMenu {
        var copy = menu
        let prefs = diner.preferences(inheriting: preferences)
        // A companion has no rating history of their own, so they get the
        // profile-only ranking rather than inheriting the owner's taste.
        let noMemory = TasteMemory(orders: [])

        copy.sections = menu.sections.map { section in
            var section = section
            section.dishes = section.dishes.map { dish in
                var scored = DishScorer.score(
                    dish,
                    prior: dish.matchScore,
                    preferences: prefs,
                    memory: noMemory
                )
                scored.id = dish.id
                return scored
            }
            return section
        }
        return copy
    }

    /// The menu as the account holder eats now, not as they were when it was
    /// read: an allergy or diet added since flags the dish in place, so the
    /// list and the waiter card can never disagree. No model call.
    ///
    /// Safety only. The taste score is left as the scan set it — re-fitting
    /// an already-fitted score compresses it (`fit` starts from 30 + 0.4 ×
    /// prior), and a menu that opens with different numbers from the ones
    /// Home shows reads as broken. Stored dishes carry no printed line
    /// (`sourceText`), so this pass sees only the name, description and
    /// ingredients — enough to catch "parmigiano" or "arachidi" in the
    /// printed name. A warning found at scan time is kept: this pass adds
    /// caution and never removes it. Clearing one takes a fresh photo.
    func menu(rescored menu: ParsedMenu) -> ParsedMenu {
        var copy = menu
        copy.sections = menu.sections.map { section in
            var section = section
            section.dishes = section.dishes.map { dish in
                guard dish.warnings.isEmpty else { return dish }
                var checked = DishScorer.applySafetyNet(dish, preferences: preferences)
                if let first = checked.warnings.first { checked.matchReason = first }
                return checked
            }
            return section
        }
        return copy
    }

    func addDiner(_ diner: Diner) {
        diners.append(diner)
        Haptic.success()
    }

    func updateDiner(_ diner: Diner) {
        guard let index = diners.firstIndex(where: { $0.id == diner.id }) else { return }
        diners[index] = diner
    }

    func removeDiner(_ diner: Diner) {
        diners.removeAll { $0.id == diner.id }
    }

    // MARK: - Preferences

    func completeOnboarding() {
        preferences.hasCompletedOnboarding = true
        Haptic.success()
    }

    private func persistPreferences() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: Self.preferencesKey)
    }
}

// MARK: - Background hold

/// Keeps a read alive while the app is briefly in the background — a glance
/// at Messages mid-read must not throw the photo away. Held for the length
/// of `analyze(image:)` / `addPage(image:to:)`; iOS grants a few seconds and
/// the expiry handler ends it cleanly if the read runs longer than that.
@MainActor
private final class BackgroundHold {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
