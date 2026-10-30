//
//  SelfTest.swift
//  menuai
//
//  Debug-only harness for exercising the scan pipeline without tapping
//  through the UI. Point MENUAI_SELFTEST_IMAGE at a file inside the app's
//  Documents directory and launch; the parsed menu is written to
//  Documents/selftest-report.txt and echoed to the console.
//
//      xcrun simctl launch --console-pty \
//        --setenv MENUAI_SELFTEST_IMAGE=menu.jpg <device> rozi.menuai
//
//  MENUAI_SELFTEST_MOTION=slow stretches the onboarding choreography to
//  three times its length for captures.
//

#if DEBUG

import Foundation
import UIKit

enum SelfTest {
    /// File name, relative to the app's Documents directory.
    static var requestedImage: String? {
        ProcessInfo.processInfo.environment["MENUAI_SELFTEST_IMAGE"]
    }

    /// Opens straight onto a pushed screen: "you" pushes the You screen,
    /// "companions" pushes You and then the companions screen on top of it.
    static var requestedSheet: String? {
        ProcessInfo.processInfo.environment["MENUAI_SELFTEST_SHEET"]
    }

    /// Pushes the most recent saved menu on launch, so the results screen can
    /// be inspected without tapping.
    static var opensFirstMenu: Bool {
        ProcessInfo.processInfo.environment["MENUAI_SELFTEST_OPEN_MENU"] == "1"
    }

    /// After the first menu is pushed, pushes its first dish too, so the dish
    /// screen can be inspected without tapping.
    static var opensFirstDish: Bool {
        ProcessInfo.processInfo.environment["MENUAI_SELFTEST_OPEN_DISH"] == "1"
    }

    /// Opens onboarding at a given step, to inspect it without tapping.
    static var requestedStep: Int? {
        ProcessInfo.processInfo.environment["MENUAI_SELFTEST_STEP"].flatMap(Int.init)
    }

    /// Multiplies every bespoke onboarding duration and delay, so the
    /// choreography can be captured frame by frame. MENUAI_SELFTEST_MOTION=slow
    /// runs it at three times its length; anything else leaves it at 1. Read
    /// once — the views bake it into their animations on first use.
    static let motionScale: Double = {
        ProcessInfo.processInfo.environment["MENUAI_SELFTEST_MOTION"] == "slow" ? 3 : 1
    }()

    /// A second page to merge into the menu, to exercise multi-page scanning.
    static var requestedSecondPage: String? {
        ProcessInfo.processInfo.environment["MENUAI_SELFTEST_PAGE2"]
    }

    /// With OPEN_DISH, presents the "Show the waiter" card over the dish.
    static var presentsOrderCard: Bool {
        ProcessInfo.processInfo.environment["MENUAI_SELFTEST_CARD"] == "1"
    }

    /// Scrolls the You screen to a section on launch: "eaten" or "advanced".
    static var requestedScroll: String? {
        ProcessInfo.processInfo.environment["MENUAI_SELFTEST_SCROLL"]
    }

    /// Shows Home mid-read: the first saved menu's photo in a processing
    /// card at a fixed percentage, without starting a real read.
    static var showsReading: Bool {
        ProcessInfo.processInfo.environment["MENUAI_SELFTEST_READING"] == "1"
    }

    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func run(store: AppStore) async {
        guard let name = requestedImage else { return }
        var report: [String] = []

        func note(_ line: String) {
            print("[selftest] \(line)")
            report.append(line)
        }

        note("engine readiness: \(OnDeviceEngine.readiness)")
        note("api key present: \(store.hasAPIKey)")

        let url = documents.appendingPathComponent(name)
        guard let image = UIImage(contentsOfFile: url.path) else {
            note("FAILED: could not load image at \(url.path)")
            write(report)
            return
        }
        note("loaded image \(Int(image.size.width))x\(Int(image.size.height))")

        let started = Date()
        await store.analyze(image: image)

        let elapsed = Date().timeIntervalSince(started)

        if case let .failed(message) = store.scanState {
            note("FAILED after \(String(format: "%.1f", elapsed))s: \(message)")
            write(report)
            return
        }

        guard let menu = store.savedMenus.first else {
            note("FAILED: no menu produced")
            write(report)
            return
        }

        note("OK in \(String(format: "%.1f", elapsed))s via \(menu.engine.label)")
        note("restaurant: \(menu.restaurantName.isEmpty ? "(none)" : menu.restaurantName)")
        note("summary: \(menu.summary)")
        note("dishes: \(menu.allDishes.count), blocked: \(menu.blockedCount)")
        note("")

        for dish in menu.allDishes.sorted(by: { $0.matchScore > $1.matchScore }) {
            note("\(String(format: "%3d", dish.matchScore))  \(dish.displayName)")
            if let original = dish.subtitleName { note("      original: \(original)") }
            if !dish.price.isEmpty { note("      price: \(dish.price)") }
            if !dish.cuisine.isEmpty { note("      cuisine: \(dish.cuisine)") }
            if !dish.description.isEmpty { note("      what: \(dish.description)") }
            if !dish.ingredients.isEmpty { note("      ingredients: \(dish.ingredients.joined(separator: ", "))") }
            if !dish.allergens.isEmpty { note("      allergens: \(dish.allergens.joined(separator: ", "))") }
            if !dish.matchReason.isEmpty { note("      why: \(dish.matchReason)") }
            for warning in dish.warnings { note("      ⚠︎ \(warning)") }
            note("")
        }

        // Multi-page: merge a second photo into the same menu and confirm the
        // dishes are ranked together rather than as two separate menus.
        if let second = requestedSecondPage,
           let pageImage = UIImage(contentsOfFile: documents.appendingPathComponent(second).path) {
            let before = menu.allDishes.count
            await store.addPage(image: pageImage, to: menu)

            if case let .failed(message) = store.scanState {
                note("PAGE 2 FAILED: \(message)")
            } else if let merged = store.savedMenus.first(where: { $0.id == menu.id }) {
                note("PAGE 2 merged: \(before) dishes -> \(merged.allDishes.count), sections: \(merged.sections.count)")
                note("top picks across both pages:")
                for dish in merged.topPicks {
                    note("\(String(format: "%3d", dish.matchScore))  \(dish.displayName) — \(dish.price)")
                }
                note("")
            }
        }

        // Companion re-scoring: same parsed dishes, different profile, no
        // extra model call.
        for diner in store.diners {
            let theirs = store.menu(menu, scoredFor: diner)
            note("--- for \(diner.name) (\(diner.summary)) ---")
            for dish in theirs.topPicks {
                note("\(String(format: "%3d", dish.matchScore))  \(dish.displayName) — \(dish.matchReason)")
            }
            let blocked = theirs.allDishes.filter(\.isBlocked)
            note("blocked for them: \(blocked.count)")
            for dish in blocked {
                note("      x \(dish.displayName): \(dish.warnings.first ?? "")")
            }
            note("")
        }

        write(report)
    }

    private static func write(_ lines: [String]) {
        let text = lines.joined(separator: "\n")
        try? text.write(
            to: documents.appendingPathComponent("selftest-report.txt"),
            atomically: true,
            encoding: .utf8
        )
        print("[selftest] report written")
    }
}

#endif
