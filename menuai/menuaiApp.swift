//
//  menuaiApp.swift
//  menuai
//
//  Created by Alon Rozmarin on 17/08/2026.
//

import SwiftUI

@main
struct menuaiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .task {
                    #if DEBUG
                    await SelfTest.run(store: store)
                    #endif
                }
        }
    }
}

/// Every screen is laid out for portrait — the camera card, the analysing
/// photo, the waiter card — so the phone stays there. The system asks this
/// before it consults Info.plist.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .phone ? .portrait : .all
    }
}
