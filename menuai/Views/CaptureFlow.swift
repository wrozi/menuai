//
//  CaptureFlow.swift
//  menuai
//
//  Camera, photo picker, the page-reading overlay and the failure alert —
//  all the plumbing behind reading a menu. Lives at the root, not on Home,
//  because the overlay and the alert also serve adding a page from the
//  menu screen. A new menu reads inline on Home as a processing card; only
//  a page added from the menu screen takes the full-screen view.
//

import AVFoundation
import PhotosUI
import SwiftUI

enum CaptureSource: Identifiable {
    case camera, library
    var id: Self { self }
}

struct CaptureFlow: ViewModifier {
    @Environment(AppStore.self) private var store
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var showCameraDenied = false
    @State private var lastSource: CaptureSource?
    @State private var pickerItem: PhotosPickerItem?

    func body(content: Content) -> some View {
        @Bindable var store = store

        content
            .onChange(of: store.captureRequest) { _, request in
                guard let request else { return }
                lastSource = request
                store.captureRequest = nil
                if let reason = EngineRouter.notReadyReason(apiKey: store.apiKey) {
                    store.notReady = true
                    store.scanState = .failed(reason)
                    return
                }
                switch request {
                case .camera:
                    let access = AVCaptureDevice.authorizationStatus(for: .video)
                    if access == .denied || access == .restricted {
                        showCameraDenied = true
                    } else {
                        showCamera = true
                    }
                case .library: showLibrary = true
                }
            }
            .alert("No camera access", isPresented: $showCameraDenied) {
                Button("Open Settings") {
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Allow it in Settings.")
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    Task { await store.analyze(image: image) }
                }
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showLibrary, selection: $pickerItem, matching: .images)
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    await store.analyze(item)
                    pickerItem = nil
                }
            }
            .overlay {
                // Only a page being added to an open menu covers the screen.
                // A new menu shows as a processing card in Home's Recent,
                // so the user can keep moving while it is read.
                if store.isAddingPage, case let .analyzing(progress, message) = store.scanState {
                    AnalyzingView(image: store.pendingImage, progress: progress, message: message)
                        .transition(.opacity)
                }
            }
            .animation(Theme.gentle, value: store.isAddingPage && store.scanState.isAnalyzing)
            .alert(
                store.notReady ? "Not ready yet" : (store.isAddingPage ? "Couldn't add that page" : "Couldn't read that menu"),
                isPresented: Binding(
                    get: { if case .failed = store.scanState { true } else { false } },
                    set: { if !$0 { store.clearError() } }
                )
            ) {
                if let lastSource, !store.notReady, !store.isAddingPage {
                    Button("Try again") {
                        store.clearError()
                        store.captureRequest = lastSource
                    }
                    Button("Cancel", role: .cancel) { store.clearError() }
                } else {
                    Button("OK", role: .cancel) { store.clearError() }
                }
            } message: {
                if case let .failed(message) = store.scanState { Text(message) }
            }
    }
}
