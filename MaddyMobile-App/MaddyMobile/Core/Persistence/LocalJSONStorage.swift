import Foundation

// =====================================================
// MARK: - LocalJSONStorage
// [TAG: MOBILE_PERSISTENCE]
// =====================================================

final class LocalJSONStorage {
    static let shared = LocalJSONStorage()

    private let fm = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let baseURL: URL

    private init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        baseURL = support.appendingPathComponent("MaddyMobile", isDirectory: true)

        if fm.fileExists(atPath: baseURL.path) == false {
            try? fm.createDirectory(at: baseURL, withIntermediateDirectories: true)
        }
    }

    func load<T: Codable>(_ type: T.Type, from fileName: String, fallback: T) -> T {
        let url = baseURL.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return fallback }
        return (try? decoder.decode(T.self, from: data)) ?? fallback
    }

    func loadIfPresent<T: Codable>(_ type: T.Type, from fileName: String) -> T? {
        let url = baseURL.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    func save<T: Codable>(_ value: T, to fileName: String) {
        let url = baseURL.appendingPathComponent(fileName)
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}
