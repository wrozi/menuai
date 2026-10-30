//
//  ScanStore.swift
//  menuai
//
//  Persists parsed menus and their thumbnails to the Documents directory so
//  a scan survives relaunch — useful when you photograph a menu, get seated,
//  and come back to it.
//

import Foundation
import UIKit

nonisolated struct ScanStore {
    private static let fileManager = FileManager.default

    private static var directory: URL {
        let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Scans", isDirectory: true)
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static var indexURL: URL {
        directory.appendingPathComponent("index.json")
    }

    static func load() -> [ParsedMenu] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let menus = (try? decoder.decode([ParsedMenu].self, from: data)) ?? []
        return menus.sorted { $0.scannedAt > $1.scannedAt }
    }

    static func save(_ menus: [ParsedMenu]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(menus) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    /// Writes the thumbnail and returns the file name to store on the menu.
    static func saveThumbnail(_ image: UIImage) -> String? {
        guard let data = ImageProcessing.thumbnailData(image) else { return nil }
        let name = "\(UUID().uuidString).jpg"
        do {
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func thumbnailURL(named name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    static func deleteThumbnail(named name: String) {
        try? fileManager.removeItem(at: directory.appendingPathComponent(name))
    }
}
