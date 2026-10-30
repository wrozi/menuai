//
//  PhotoBrowserView.swift
//  menuai
//
//  In-app Google Images lookup for "what does this actually look like?".
//

import SwiftUI
import WebKit

struct PhotoBrowserView: View {
    let dish: Dish

    @State private var isLoading = true
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    private var query: String { dish.resolvedSearchQuery }

    private var url: URL {
        URL(string: "https://www.google.com/search?tbm=isch&q=\(query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query)")!
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                WebView(url: url, isLoading: $isLoading, failed: $failed)
                    .ignoresSafeArea(edges: .bottom)

                if failed {
                    Theme.bg
                        .ignoresSafeArea(edges: .bottom)
                        .overlay {
                            EmptyBlock(
                                icon: "wifi.slash",
                                title: "Couldn't load photos",
                                message: "Check your connection and try again."
                            )
                            .card()
                            .padding(.horizontal, Theme.Space.m)
                        }
                        .transition(.opacity)
                } else if isLoading {
                    ProgressView()
                        .padding(.top, 8)
                        .transition(.opacity)
                }
            }
            .animation(Theme.gentle, value: failed)
            .animation(Theme.gentle, value: isLoading)
            .navigationTitle(dish.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.font(Theme.headline)
                }
            }
        }
    }
}

/// Thin WKWebView wrapper. A desktop user agent keeps Google from pushing an app-install interstitial over the results.
private struct WebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var failed: Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Nothing here should touch the user's real browsing session.
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
            "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only reload when the target actually changed — otherwise every
        // SwiftUI update would restart the page load. State flows from the
        // delegate callbacks, never from inside this update pass.
        guard context.coordinator.currentURL != url else { return }
        context.coordinator.currentURL = url
        webView.load(URLRequest(url: url))
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, isLoading: $isLoading, failed: $failed)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var currentURL: URL
        private var isLoading: Binding<Bool>
        private var failed: Binding<Bool>

        init(url: URL, isLoading: Binding<Bool>, failed: Binding<Bool>) {
            currentURL = url
            self.isLoading = isLoading
            self.failed = failed
        }

        func webView(_: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
            failed.wrappedValue = false
            isLoading.wrappedValue = true
        }

        func webView(_: WKWebView, didFinish _: WKNavigation!) {
            isLoading.wrappedValue = false
        }

        func webView(_: WKWebView, didFail _: WKNavigation!, withError _: Error) {
            isLoading.wrappedValue = false
        }

        func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
            // A load superseded by a newer one reports as cancelled. That is
            // not a failure, and the newer load owns the state from here.
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            isLoading.wrappedValue = false
            failed.wrappedValue = true
        }
    }
}
