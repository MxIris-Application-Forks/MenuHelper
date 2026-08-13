import AppKit
import XCTest

@testable import MenuHelperIconCache

final class AppIconCacheTests: XCTestCase {
    func testMenuThumbnailContainsOnlyTheMenuSizedBitmapRepresentation() throws {
        let sourceImage = try makeLargeSourceImage(redComponent: 0.2)
        let thumbnailImage = try XCTUnwrap(AppIconCache.menuThumbnail(from: sourceImage))
        let thumbnailRepresentation = try XCTUnwrap(
            thumbnailImage.representations.first as? NSBitmapImageRep
        )

        XCTAssertEqual(thumbnailImage.size, AppIconCache.menuIconPointSize)
        XCTAssertEqual(thumbnailImage.representations.count, 1)
        XCTAssertEqual(
            thumbnailRepresentation.pixelsWide,
            AppIconCache.menuIconPixelDimension
        )
        XCTAssertEqual(
            thumbnailRepresentation.pixelsHigh,
            AppIconCache.menuIconPixelDimension
        )
    }

    func testPersistedCacheReloadsWithoutTheLargeSourceRepresentation() throws {
        let testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let cacheDirectory = testDirectory.appendingPathComponent(
            "MenuIconCacheV2",
            isDirectory: true
        )
        let applicationLocation = testDirectory.appendingPathComponent(
            "SyntheticApplication.app",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: applicationLocation,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: testDirectory) }

        let sourceImage = try makeLargeSourceImage(redComponent: 0.4)
        let writingCache = AppIconCache(
            cacheDirectory: cacheDirectory,
            applicationIconProvider: { _ in sourceImage }
        )
        writingCache.loadImmediately(for: applicationLocation)
        let expectedCachedImage = writingCache.menuIcon(for: applicationLocation)
        let expectedCachedRepresentation = try XCTUnwrap(
            expectedCachedImage.representations.first as? NSBitmapImageRep
        )
        let expectedCenterColor = try XCTUnwrap(
            expectedCachedRepresentation.colorAt(
                x: AppIconCache.menuIconPixelDimension / 2,
                y: AppIconCache.menuIconPixelDimension / 2
            )?.usingColorSpace(.sRGB)
        )

        let cacheFiles = try FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        )
        let cacheFile = try XCTUnwrap(cacheFiles.first)
        let cacheFileSize = try XCTUnwrap(
            try cacheFile.resourceValues(forKeys: [.fileSizeKey]).fileSize
        )
        XCTAssertEqual(cacheFiles.count, 1)
        XCTAssertLessThan(cacheFileSize, 256 * 1024)

        let replacementSourceImage = try makeLargeSourceImage(redComponent: 0.9)
        let readingCache = AppIconCache(
            cacheDirectory: cacheDirectory,
            applicationIconProvider: { _ in replacementSourceImage }
        )
        readingCache.loadImmediately(for: applicationLocation)
        let reloadedImage = readingCache.menuIcon(for: applicationLocation)
        let reloadedRepresentation = try XCTUnwrap(
            reloadedImage.representations.first as? NSBitmapImageRep
        )

        XCTAssertEqual(reloadedImage.representations.count, 1)
        XCTAssertEqual(
            reloadedRepresentation.pixelsWide,
            AppIconCache.menuIconPixelDimension
        )
        XCTAssertEqual(
            reloadedRepresentation.pixelsHigh,
            AppIconCache.menuIconPixelDimension
        )
        let reloadedCenterColor = try XCTUnwrap(
            reloadedRepresentation.colorAt(
                x: AppIconCache.menuIconPixelDimension / 2,
                y: AppIconCache.menuIconPixelDimension / 2
            )?.usingColorSpace(.sRGB)
        )
        XCTAssertEqual(
            reloadedCenterColor.redComponent,
            expectedCenterColor.redComponent,
            accuracy: 0.01
        )
    }

    func testMenuArchiveRemainsBelowOneMegabyteForFifteenDistinctIcons() throws {
        let menu = NSMenu(title: "Menu payload regression test")

        for applicationIndex in 0 ..< 15 {
            let sourceImage = try makeLargeSourceImage(
                redComponent: CGFloat(applicationIndex + 1) / 16
            )
            let thumbnailImage = try XCTUnwrap(AppIconCache.menuThumbnail(from: sourceImage))
            let menuItem = NSMenuItem(
                title: "Application \(applicationIndex + 1)",
                action: nil,
                keyEquivalent: ""
            )
            menuItem.image = thumbnailImage
            menu.addItem(menuItem)
        }

        let archivedMenuData = try NSKeyedArchiver.archivedData(
            withRootObject: menu,
            requiringSecureCoding: false
        )
        XCTAssertLessThan(archivedMenuData.count, 1_048_576)
    }

    private func makeLargeSourceImage(redComponent: CGFloat) throws -> NSImage {
        let sourcePixelDimension = 1024
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let graphicsContext = try XCTUnwrap(
            CGContext(
                data: nil,
                width: sourcePixelDimension,
                height: sourcePixelDimension,
                bitsPerComponent: 8,
                bytesPerRow: sourcePixelDimension * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        graphicsContext.setFillColor(
            NSColor(
                calibratedRed: redComponent,
                green: 0.5,
                blue: 0.8,
                alpha: 1
            ).cgColor
        )
        graphicsContext.fill(
            CGRect(
                x: 0,
                y: 0,
                width: sourcePixelDimension,
                height: sourcePixelDimension
            )
        )

        let sourceGraphicsImage = try XCTUnwrap(graphicsContext.makeImage())
        let sourceRepresentation = NSBitmapImageRep(cgImage: sourceGraphicsImage)
        sourceRepresentation.size = NSSize(width: 32, height: 32)

        let sourceImage = NSImage(size: sourceRepresentation.size)
        sourceImage.addRepresentation(sourceRepresentation)
        return sourceImage
    }
}
