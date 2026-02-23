//
//  AppIconCache.swift
//  MenuHelper
//
//  Created by Kyle on 2026/2/19.
//

import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

final class AppIconCache {
    static let shared = AppIconCache()

    private var memoryCache: [URL: NSImage] = [:]
    private let cacheDirectory: URL?
    private let placeholder: NSImage

    private init() {
        let groupID: String
        #if DEBUG
        groupID = "\(UserDefaults.teamIDPrefix)com.JH.MenuHelperDebug"
        #else
        groupID = "\(UserDefaults.teamIDPrefix)com.JH.MenuHelper"
        #endif

        let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        )
        cacheDirectory = containerURL?.appendingPathComponent("IconCache", isDirectory: true)

        if let dir = cacheDirectory {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        placeholder = NSWorkspace.shared.icon(for: .applicationBundle)
    }

    /// Sync: memory -> disk -> placeholder (+ async background load)
    func icon(for url: URL) -> NSImage {
        // L1: Memory
        if let cached = memoryCache[url] {
            return cached
        }

        // L2: Disk
        if let diskImage = loadFromDisk(for: url) {
            memoryCache[url] = diskImage
            return diskImage
        }

        // Miss: return placeholder, load in background
        Task {
            let image = NSWorkspace.shared.icon(forFile: url.path)
            memoryCache[url] = image
            saveToDisk(image: image, for: url, modificationDate: modificationDate(for: url))
        }

        return placeholder
    }

    /// Prewarm icon cache for all given URLs
    func prewarm(urls: [URL]) {
        for url in urls {
            if memoryCache[url] != nil { continue }
            if let diskImage = loadFromDisk(for: url) {
                memoryCache[url] = diskImage
                continue
            }
            Task {
                let image = NSWorkspace.shared.icon(forFile: url.path)
                memoryCache[url] = image
                saveToDisk(image: image, for: url, modificationDate: modificationDate(for: url))
            }
        }
    }

    // MARK: - Disk Cache

    private struct CacheEntry: Codable {
        let modificationDate: TimeInterval
        let imageData: Data
        let imageWidth: Double
        let imageHeight: Double
    }

    private func cacheFileURL(for url: URL) -> URL? {
        guard let dir = cacheDirectory else { return nil }
        let hash = SHA256.hash(data: Data(url.path.utf8))
        let fileName = hash.compactMap { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(fileName + ".cache")
    }

    private func modificationDate(for url: URL) -> TimeInterval {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate?.timeIntervalSince1970 ?? 0
    }

    private func loadFromDisk(for url: URL) -> NSImage? {
        guard let fileURL = cacheFileURL(for: url),
              let data = try? Data(contentsOf: fileURL),
              let entry = try? JSONDecoder().decode(CacheEntry.self, from: data) else {
            return nil
        }

        // Validate: modification date must match current app bundle
        let currentModDate = modificationDate(for: url)
        guard currentModDate > 0, entry.modificationDate == currentModDate else {
            return nil
        }

        guard let image = NSImage(data: entry.imageData) else { return nil }
        image.size = NSSize(width: entry.imageWidth, height: entry.imageHeight)
        return image
    }

    private func saveToDisk(image: NSImage, for url: URL, modificationDate: TimeInterval) {
        guard let fileURL = cacheFileURL(for: url),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return
        }

        let entry = CacheEntry(
            modificationDate: modificationDate,
            imageData: pngData,
            imageWidth: image.size.width,
            imageHeight: image.size.height
        )
        guard let jsonData = try? JSONEncoder().encode(entry) else { return }
        try? jsonData.write(to: fileURL, options: .atomic)
    }
}
