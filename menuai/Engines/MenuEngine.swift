//
//  MenuEngine.swift
//  menuai
//
//  Two brains behind one interface, plus the rule for choosing between them.
//

import UIKit

/// Reports how far along a scan is, and what it is doing.
///
/// Main-actor isolated, and the engines are driven from the main actor too, so
/// views can bind straight to whatever it writes without a hop.
typealias ProgressHandler = @MainActor @Sendable (Double, String) -> Void

enum EngineError: LocalizedError {
    /// Neither engine can run — the reason explains what the user can do.
    case noEngineAvailable(String)
    /// The chosen engine can't run right now.
    case engineUnavailable(String)
    case imageEncodingFailed
    case noMenuFound
    case http(status: Int, message: String)
    case refused(String)
    case truncated
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case let .noEngineAvailable(message), let .engineUnavailable(message):
            message
        case .imageEncodingFailed:
            "Couldn't read that photo. Try another."
        case .noMenuFound:
            "No dishes found. Get the text in frame and try again."
        case let .http(status, _):
            switch status {
            case 401: "Your Anthropic API key was rejected. Check it under Advanced on You."
            case 429: "Too many requests. Try again in a moment."
            default: "Try again in a moment."
            }
        case let .refused(detail):
            detail
        case .truncated:
            "Too much to read at once. Try one page at a time."
        case .badResponse:
            "Try again in a moment."
        }
    }
}

protocol MenuEngine {
    var kind: MenuEngineKind { get }

    func analyze(
        image: UIImage,
        preferences: UserPreferences,
        memory: TasteMemory,
        onProgress: @escaping ProgressHandler
    ) async throws -> ParsedMenu
}

// MARK: - Routing

enum EngineRouter {
    /// Claude when there's a key, Apple's on-device model otherwise.
    ///
    /// Claude wins when available: it reads the photo directly rather than
    /// through OCR, which matters for handwriting and non-Latin scripts, and
    /// it knows what a dish is in a way a 3B model does not. The on-device
    /// path exists so the app works out of the box, offline, at no cost.
    static func select(apiKey: String) throws -> MenuEngine {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            return ClaudeEngine(apiKey: key)
        }

        switch OnDeviceEngine.readiness {
        case .ready:
            return OnDeviceEngine()
        case let .notReady(message):
            throw EngineError.noEngineAvailable(message)
        }
    }

    /// Why a photo can't be read right now, or nil when it can.
    static func notReadyReason(apiKey: String) -> String? {
        guard apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if case let .notReady(message) = OnDeviceEngine.readiness { return message }
        return nil
    }
}
