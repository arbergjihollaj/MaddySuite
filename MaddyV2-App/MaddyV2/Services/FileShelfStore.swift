import Foundation
import SwiftUI
import Combine
import UniformTypeIdentifiers
import AppKit

// =====================================================
// MARK: - File Shelf Constants
// [TAG: FILE_SHELF_WINDOW_ID]
// =====================================================

enum FileShelfWindowID {
    static let panel = "maddy.fileShelf"
}

// =====================================================
// MARK: - FileShelfStore
// [TAG: FILE_SHELF_STORE]
// =====================================================

@MainActor
final class FileShelfStore: ObservableObject {
    struct ShelfItem: Identifiable, Codable, Equatable {
        var id: UUID
        var bookmarkData: Data
        var displayName: String
        var originalPath: String
        var dateAdded: Date
    }

    @Published private(set) var items: [ShelfItem] {
        didSet {
            persist()
        }
    }

    private let fm = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let storageURL: URL

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let directory = JSONStorageService.baseDirectory
        if FileManager.default.fileExists(atPath: directory.path) == false {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        storageURL = directory.appendingPathComponent("file_shelf.json")

        if let data = try? Data(contentsOf: storageURL),
           let decoded = try? decoder.decode([ShelfItem].self, from: data) {
            items = decoded
        } else {
            items = []
        }
    }

    var hasItems: Bool {
        items.isEmpty == false
    }

    func addFileURLs(_ urls: [URL]) {
        guard urls.isEmpty == false else { return }

        var existingPaths = Set(
            items.compactMap { resolvedURL(for: $0)?.standardizedFileURL.path ?? URL(fileURLWithPath: $0.originalPath).standardizedFileURL.path }
        )

        var appended: [ShelfItem] = []
        for sourceURL in urls {
            let fileURL = sourceURL.standardizedFileURL
            guard fileURL.isFileURL else { continue }

            let path = fileURL.path
            guard fm.fileExists(atPath: path) else { continue }
            guard existingPaths.contains(path) == false else { continue }

            let bookmark = bookmarkData(for: fileURL)
            let displayName = fm.displayName(atPath: path)

            appended.append(
                ShelfItem(
                    id: UUID(),
                    bookmarkData: bookmark,
                    displayName: displayName,
                    originalPath: path,
                    dateAdded: Date()
                )
            )
            existingPaths.insert(path)
        }

        guard appended.isEmpty == false else { return }
        items.insert(contentsOf: appended, at: 0)
    }

    func addItemProviders(_ providers: [NSItemProvider]) {
        let supported = providers.filter {
            $0.canLoadObject(ofClass: URL.self) || $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard supported.isEmpty == false else { return }

        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in supported {
            if provider.canLoadObject(ofClass: URL.self) {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { object, _ in
                    defer { group.leave() }
                    guard let url = object, url.isFileURL else { return }
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                continue
            }

            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                guard let url = Self.extractURL(from: item), url.isFileURL else { return }
                lock.lock()
                urls.append(url)
                lock.unlock()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.addFileURLs(urls)
        }
    }

    func remove(itemID: UUID) {
        items.removeAll { $0.id == itemID }
    }

    func clearAll() {
        items.removeAll()
    }

    func resolvedURL(for item: ShelfItem) -> URL? {
        var stale = false

        if let url = try? URL(
            resolvingBookmarkData: item.bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) {
            return url
        }

        if let url = try? URL(
            resolvingBookmarkData: item.bookmarkData,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) {
            return url
        }

        let fallback = URL(fileURLWithPath: item.originalPath)
        return fallback.isFileURL ? fallback : nil
    }

    func isAvailable(_ item: ShelfItem) -> Bool {
        guard let url = resolvedURL(for: item) else { return false }
        return fm.fileExists(atPath: url.path)
    }

    func icon(for item: ShelfItem) -> NSImage {
        guard let url = resolvedURL(for: item), fm.fileExists(atPath: url.path) else {
            return NSWorkspace.shared.icon(for: .data)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func persist() {
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    private func bookmarkData(for url: URL) -> Data {
        if let scoped = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            return scoped
        }

        if let regular = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            return regular
        }

        return Data()
    }

    nonisolated private static func extractURL(from rawItem: NSSecureCoding?) -> URL? {
        if let url = rawItem as? URL {
            return url
        }

        if let data = rawItem as? Data,
           let string = String(data: data, encoding: .utf8),
           let url = URL(string: string) {
            return url
        }

        if let string = rawItem as? NSString,
           let url = URL(string: string as String) {
            return url
        }

        return nil
    }
}
