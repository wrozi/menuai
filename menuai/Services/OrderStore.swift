//
//  OrderStore.swift
//  menuai
//

import Foundation

enum OrderStore {
    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("orders.json")
    }

    static func load() -> [OrderedDish] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let orders = (try? decoder.decode([OrderedDish].self, from: data)) ?? []
        return orders.sorted { $0.orderedAt > $1.orderedAt }
    }

    static func save(_ orders: [OrderedDish]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(orders) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
