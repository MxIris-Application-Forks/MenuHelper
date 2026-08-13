//
//  AppIconCache.swift
//  MenuHelper
//
//  Created by Kyle on 2026/2/19.
//

import AppKit
import CryptoKit
import Foundation

nonisolated final class AppIconCache: @unchecked Sendable {
    static let menuIconPointSize = NSSize(width: 16, height: 16)
    static let menuIconPixelDimension = 32

    static let shared: AppIconCache = {
        let cacheLocations = defaultCacheLocations()
        return AppIconCache(
            cacheDirectory: cacheLocations.currentCacheDirectory,
            legacyCacheDirectory: cacheLocations.legacyCacheDirectory,
            applicationIconProvider: { applicationLocation in
                NSWorkspace.shared.icon(forFile: applicationLocation.path)
            }
        )
    }()

    private static let cacheFormatVersion = 2

    private struct CacheState {
        var displayImages: [URL: NSImage] = [:]
        var menuImages: [URL: NSImage] = [:]
        var pendingMenuImageLocations: Set<URL> = []
    }

    private struct CacheEntry: Codable {
        let formatVersion: Int
        let modificationDate: TimeInterval
        let portableNetworkGraphicsData: Data
        let imagePointWidth: Double
        let imagePointHeight: Double
        let imagePixelWidth: Int
        let imagePixelHeight: Int
    }

    private let applicationIconProvider: (URL) -> NSImage
    private let cacheDirectory: URL?
    private let generationQueue = DispatchQueue(
        label: "com.JH.MenuHelper.MenuIconGeneration",
        qos: .utility
    )
    private let stateLock = NSLock()
    private var cacheState = CacheState()
    private let menuPlaceholder: NSImage

    init(
        cacheDirectory: URL?,
        legacyCacheDirectory: URL? = nil,
        applicationIconProvider: @escaping (URL) -> NSImage
    ) {
        self.applicationIconProvider = applicationIconProvider
        self.cacheDirectory = cacheDirectory

        let placeholderSourceImage = NSWorkspace.shared.icon(for: .applicationBundle)
        menuPlaceholder = Self.menuThumbnail(from: placeholderSourceImage)
            ?? NSImage(size: Self.menuIconPointSize)

        if let cacheDirectory {
            try? FileManager.default.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true
            )
        }

        if let legacyCacheDirectory,
           legacyCacheDirectory != cacheDirectory {
            DispatchQueue.global(qos: .background).async {
                try? FileManager.default.removeItem(at: legacyCacheDirectory)
            }
        }
    }

    func displayIcon(for applicationLocation: URL) -> NSImage {
        if let cachedImage = withLockedState({ cacheState in
            cacheState.displayImages[applicationLocation]
        }) {
            return cachedImage
        }

        let sourceImage = applicationIconProvider(applicationLocation)
        return withLockedState { cacheState in
            if let cachedImage = cacheState.displayImages[applicationLocation] {
                return cachedImage
            }
            cacheState.displayImages[applicationLocation] = sourceImage
            return sourceImage
        }
    }

    /// Returns a memory-cached menu thumbnail immediately. Cache misses use a
    /// small placeholder while disk loading and thumbnail generation continue
    /// away from Finder's synchronous menu request.
    func menuIcon(for applicationLocation: URL) -> NSImage {
        if let cachedImage = withLockedState({ cacheState in
            cacheState.menuImages[applicationLocation]
        }) {
            return cachedImage
        }

        requestMenuIcon(for: applicationLocation)
        return menuPlaceholder
    }

    /// Synchronously prepares both the settings image and the menu thumbnail.
    /// This is used by the settings UI when the user adds an application.
    func loadImmediately(for applicationLocation: URL) {
        let sourceImage = displayIcon(for: applicationLocation)

        if withLockedState({ cacheState in
            cacheState.menuImages[applicationLocation] != nil
        }) {
            return
        }

        if let diskImage = loadFromDisk(for: applicationLocation) {
            storeMenuImage(diskImage, for: applicationLocation)
            return
        }

        guard let menuImage = Self.menuThumbnail(from: sourceImage) else { return }
        storeMenuImage(menuImage, for: applicationLocation)
        saveToDisk(image: menuImage, for: applicationLocation)
    }

    /// Starts nonblocking cache loading for every configured application.
    func prewarm(applicationLocations: [URL]) {
        for applicationLocation in applicationLocations {
            requestMenuIcon(for: applicationLocation)
        }
    }

    static func menuThumbnail(from sourceImage: NSImage) -> NSImage? {
        var proposedRectangle = NSRect(origin: .zero, size: menuIconPointSize)
        guard let sourceGraphicsImage = sourceImage.cgImage(
            forProposedRect: &proposedRectangle,
            context: nil,
            hints: nil
        ),
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let graphicsContext = CGContext(
            data: nil,
            width: menuIconPixelDimension,
            height: menuIconPixelDimension,
            bitsPerComponent: 8,
            bytesPerRow: menuIconPixelDimension * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        graphicsContext.interpolationQuality = .high
        graphicsContext.draw(
            sourceGraphicsImage,
            in: CGRect(
                x: 0,
                y: 0,
                width: menuIconPixelDimension,
                height: menuIconPixelDimension
            )
        )

        guard let thumbnailGraphicsImage = graphicsContext.makeImage() else { return nil }
        let thumbnailRepresentation = NSBitmapImageRep(cgImage: thumbnailGraphicsImage)
        thumbnailRepresentation.size = menuIconPointSize

        let thumbnailImage = NSImage(size: menuIconPointSize)
        thumbnailImage.addRepresentation(thumbnailRepresentation)
        thumbnailImage.isTemplate = sourceImage.isTemplate
        return thumbnailImage
    }

    private func requestMenuIcon(for applicationLocation: URL) {
        let shouldStartRequest = withLockedState { cacheState in
            guard cacheState.menuImages[applicationLocation] == nil,
                  !cacheState.pendingMenuImageLocations.contains(applicationLocation) else {
                return false
            }
            cacheState.pendingMenuImageLocations.insert(applicationLocation)
            return true
        }
        guard shouldStartRequest else { return }

        generationQueue.async { [self] in
            let menuImage: NSImage?
            if let diskImage = loadFromDisk(for: applicationLocation) {
                menuImage = diskImage
            } else {
                let sourceImage = applicationIconProvider(applicationLocation)
                menuImage = Self.menuThumbnail(from: sourceImage)
                if let menuImage {
                    saveToDisk(image: menuImage, for: applicationLocation)
                }
            }

            withLockedState { cacheState in
                if let menuImage {
                    cacheState.menuImages[applicationLocation] = menuImage
                }
                cacheState.pendingMenuImageLocations.remove(applicationLocation)
            }
        }
    }

    private func storeMenuImage(_ menuImage: NSImage, for applicationLocation: URL) {
        withLockedState { cacheState in
            cacheState.menuImages[applicationLocation] = menuImage
            cacheState.pendingMenuImageLocations.remove(applicationLocation)
        }
    }

    private func withLockedState<OperationResult>(
        _ operation: (inout CacheState) -> OperationResult
    ) -> OperationResult {
        stateLock.lock()
        defer { stateLock.unlock() }
        return operation(&cacheState)
    }

    // MARK: - Disk Cache

    private static func defaultCacheLocations() -> (
        currentCacheDirectory: URL?,
        legacyCacheDirectory: URL?
    ) {
        let teamIdentifierPrefix = (Bundle.main.infoDictionary?["TEAM_ID_PREFIX"] as? String)
            ?? "VB7MJ8R223"
        let groupIdentifier: String
        #if DEBUG
        groupIdentifier = "\(teamIdentifierPrefix)com.JH.MenuHelperDebug"
        #else
        groupIdentifier = "\(teamIdentifierPrefix)com.JH.MenuHelper"
        #endif

        let containerLocation = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        )
        return (
            currentCacheDirectory: containerLocation?.appendingPathComponent(
                "MenuIconCacheV2",
                isDirectory: true
            ),
            legacyCacheDirectory: containerLocation?.appendingPathComponent(
                "IconCache",
                isDirectory: true
            )
        )
    }

    private func cacheFileLocation(for applicationLocation: URL) -> URL? {
        guard let cacheDirectory else { return nil }
        let pathDigest = SHA256.hash(data: Data(applicationLocation.path.utf8))
        let cacheFileName = pathDigest
            .map { String(format: "%02x", $0) }
            .joined()
        return cacheDirectory.appendingPathComponent(cacheFileName + ".cache")
    }

    private func modificationDate(for applicationLocation: URL) -> TimeInterval {
        let resourceValues = try? applicationLocation.resourceValues(
            forKeys: [.contentModificationDateKey]
        )
        return resourceValues?.contentModificationDate?.timeIntervalSince1970 ?? 0
    }

    private func loadFromDisk(for applicationLocation: URL) -> NSImage? {
        guard let cacheFileLocation = cacheFileLocation(for: applicationLocation),
              let encodedCacheEntry = try? Data(contentsOf: cacheFileLocation),
              let cacheEntry = try? JSONDecoder().decode(
                  CacheEntry.self,
                  from: encodedCacheEntry
              ) else {
            return nil
        }

        let currentModificationDate = modificationDate(for: applicationLocation)
        guard cacheEntry.formatVersion == Self.cacheFormatVersion,
              currentModificationDate > 0,
              cacheEntry.modificationDate == currentModificationDate,
              cacheEntry.imagePointWidth == Self.menuIconPointSize.width,
              cacheEntry.imagePointHeight == Self.menuIconPointSize.height,
              cacheEntry.imagePixelWidth == Self.menuIconPixelDimension,
              cacheEntry.imagePixelHeight == Self.menuIconPixelDimension,
              let thumbnailRepresentation = NSBitmapImageRep(
                  data: cacheEntry.portableNetworkGraphicsData
              ),
              thumbnailRepresentation.pixelsWide == Self.menuIconPixelDimension,
              thumbnailRepresentation.pixelsHigh == Self.menuIconPixelDimension else {
            try? FileManager.default.removeItem(at: cacheFileLocation)
            return nil
        }

        thumbnailRepresentation.size = Self.menuIconPointSize
        let thumbnailImage = NSImage(size: Self.menuIconPointSize)
        thumbnailImage.addRepresentation(thumbnailRepresentation)
        return thumbnailImage
    }

    private func saveToDisk(image: NSImage, for applicationLocation: URL) {
        guard let cacheFileLocation = cacheFileLocation(for: applicationLocation),
              let thumbnailRepresentation = image.representations
                  .compactMap({ $0 as? NSBitmapImageRep })
                  .first,
              thumbnailRepresentation.pixelsWide == Self.menuIconPixelDimension,
              thumbnailRepresentation.pixelsHigh == Self.menuIconPixelDimension,
              let portableNetworkGraphicsData = thumbnailRepresentation.representation(
                  using: .png,
                  properties: [:]
              ) else {
            return
        }

        let currentModificationDate = modificationDate(for: applicationLocation)
        guard currentModificationDate > 0 else { return }

        let cacheEntry = CacheEntry(
            formatVersion: Self.cacheFormatVersion,
            modificationDate: currentModificationDate,
            portableNetworkGraphicsData: portableNetworkGraphicsData,
            imagePointWidth: image.size.width,
            imagePointHeight: image.size.height,
            imagePixelWidth: thumbnailRepresentation.pixelsWide,
            imagePixelHeight: thumbnailRepresentation.pixelsHigh
        )
        guard let encodedCacheEntry = try? JSONEncoder().encode(cacheEntry) else { return }
        try? encodedCacheEntry.write(to: cacheFileLocation, options: .atomic)
    }
}
