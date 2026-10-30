//
//  SymbolTests.swift
//  menuaiTests
//
//  An SF Symbol name that doesn't exist fails silently: `Image(systemName:)`
//  draws nothing, leaving a blank gap where an icon should be. Nobody notices
//  until a screenshot arrives — which is exactly how `star.of.david` shipped
//  with the Kosher row missing its icon in two different places.
//

import Testing
import UIKit
@testable import menuai

@Suite("Icons")
struct SymbolTests {
    /// Every icon that comes from data rather than a literal at the call site.
    /// These are the ones that rot, because nothing points at them from a view.
    @Test("Every diet has an icon that actually renders")
    func dietIconsExist() {
        for diet in Diet.allCases {
            #expect(
                UIImage(systemName: diet.icon) != nil,
                "\(diet.label) uses '\(diet.icon)', which is not an SF Symbol"
            )
        }
    }

    @Test("Every eating goal has an icon that actually renders")
    func goalIconsExist() {
        for goal in EatingGoal.allCases {
            #expect(
                UIImage(systemName: goal.icon) != nil,
                "\(goal.label) uses '\(goal.icon)', which is not an SF Symbol"
            )
        }
    }

    @Test("Every scale option has an icon that actually renders")
    func choiceIconsExist() {
        for (title, _, icon) in Choices.spice + Choices.adventure {
            #expect(UIImage(systemName: icon) != nil, "\(title) uses '\(icon)'")
        }
    }

    @Test("Every engine badge has an icon that actually renders")
    func engineIconsExist() {
        for kind in [MenuEngineKind.claude, .onDevice] {
            #expect(UIImage(systemName: kind.icon) != nil, "\(kind.label) uses '\(kind.icon)'")
        }
    }

    /// The literals dotted through the views. Kept as a list because there is
    /// no way to reach them from code — if one is renamed, add it here.
    @Test("Icons used in the interface all render", arguments: [
        "text.viewfinder", "photo.on.rectangle", "photo.on.rectangle.angled",
        "camera.fill", "gearshape", "chevron.left", "chevron.right",
        "checkmark", "plus", "xmark", "arrow.right", "arrow.up.right",
        "exclamationmark", "exclamationmark.triangle", "exclamationmark.triangle.fill",
        "exclamationmark.circle.fill", "clock.arrow.circlepath", "quote.bubble",
        "hand.raised.fill", "plus.circle", "checkmark.circle.fill",
        "checkmark.seal.fill", "star", "star.fill", "flame.fill",
        "doc.text.image", "fork.knife", "person.fill", "person.2",
        "person.2.fill", "trash", "line.3.horizontal.decrease.circle",
        "plus.viewfinder", "safari", "globe", "leaf", "heart", "map",
        "character.book.closed", "hand.thumbsup", "slider.horizontal.3",
        "lock.fill", "iphone", "sparkles", "target", "scalemass.fill", "star.leadinghalf.filled", "camera.fill", "person.crop.circle", "person.2.fill", "hand.raised.fill",
        "scalemass", "heart.fill", "bolt.fill", "dumbbell.fill",
        "pencil", "chevron.down", "mappin.and.ellipse", "wifi.slash",
        "circle", "arrow.left", "hand.wave", "binoculars.fill",
    ])
    func literalIconsExist(name: String) {
        #expect(UIImage(systemName: name) != nil, "'\(name)' is not an SF Symbol")
    }
}
