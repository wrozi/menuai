//
//  RootView.swift
//  menuai
//
//  One stack. Home is the root; menus, dishes, You and the companions are
//  pushed onto it. There is no tab bar and no floating button: the camera
//  is the big card on Home, and everything about the person is one screen
//  behind the round button beside the wordmark.
//

import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if store.preferences.hasCompletedOnboarding {
                AppStack().transition(.opacity.combined(with: .scale(scale: 1.02)))
            } else {
                OnboardingView().transition(.opacity)
            }
        }
        .animation(Theme.gentle, value: store.preferences.hasCompletedOnboarding)
        .tint(Theme.ink)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

private struct AppStack: View {
    @Environment(AppStore.self) private var store
    /// The whole app's navigation. Home pushes onto it; every destination is
    /// registered here, once, so a route means the same thing wherever it
    /// is appended from.
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(path: $path)
                .navigationDestination(for: ParsedMenu.self) { MenuResultView(menu: $0) }
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .you: YouView()
                    case .companions: CompanionsView()
                    }
                }
                #if DEBUG
                .navigationDestination(for: DebugDishRoute.self) { DishDetailView(dish: $0.dish, menu: $0.menu) }
                #endif
        }
        // Camera, picker, the page-reading overlay and the failure alert sit
        // over the stack, so a page can be added from the menu screen too.
        .modifier(CaptureFlow())
        .onChange(of: store.activeMenu) { _, menu in
            guard let menu else { return }
            // A finished menu opens only for someone still on Home, where
            // its processing card was. Anyone who moved on — to You, or
            // into another menu — is left where they are; the menu waits
            // at the top of Recent.
            if path.isEmpty {
                path.append(menu)
            }
            store.activeMenu = nil
        }
        .task {
            guard !store.hasAPIKey else { return }
            try? await Task.sleep(for: .milliseconds(400))
            OnDeviceEngine.prewarm()
        }
        #if DEBUG
        .task {
            // The screenshot harness opens straight onto a pushed screen.
            switch SelfTest.requestedSheet {
            case "you":
                path.append(AppRoute.you)
            case "companions":
                path.append(AppRoute.you)
                path.append(AppRoute.companions)
            default:
                break
            }
        }
        #endif
    }
}

// MARK: - Routes

/// The places you can go that aren't a menu or a dish.
enum AppRoute: Hashable {
    case you
    case companions
}

#if DEBUG
/// Value route for the screenshot harness: the dish screen is normally reached
/// through a NavigationLink with an inline destination, which a path can't
/// address. The root registers its destination.
struct DebugDishRoute: Hashable {
    let dish: Dish
    let menu: ParsedMenu
}
#endif
