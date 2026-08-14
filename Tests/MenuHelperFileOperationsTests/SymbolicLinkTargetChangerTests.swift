import Foundation
import Testing

@testable import MenuHelperFileOperations

@Suite("Symbolic link target changer")
struct SymbolicLinkTargetChangerTests {
    @Test("Relative destinations resolve against the symbolic link parent for display")
    func relativeDestinationResolvesAgainstSymbolicLinkParentForDisplay() throws {
        let testDirectory = try makeTemporaryTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDirectory) }

        let targetDirectory = testDirectory.appendingPathComponent("Targets", isDirectory: true)
        try FileManager.default.createDirectory(
            at: targetDirectory,
            withIntermediateDirectories: false
        )
        let originalTargetLocation = targetDirectory.appendingPathComponent("Original.txt")
        try Data("original".utf8).write(to: originalTargetLocation)
        let symbolicLinkLocation = testDirectory.appendingPathComponent("Selected Link")
        let relativeDestinationPath = "Targets/Original.txt"
        try FileManager.default.createSymbolicLink(
            atPath: symbolicLinkLocation.path,
            withDestinationPath: relativeDestinationPath
        )

        let targetInformation = try SymbolicLinkTargetChanger.targetInformation(
            for: symbolicLinkLocation
        )

        #expect(targetInformation.storedDestinationPath == relativeDestinationPath)
        #expect(
            targetInformation.displayedDestinationLocation
                == originalTargetLocation.standardizedFileURL
        )
    }

    @Test("Replacing a target keeps the symbolic link path and both target items intact")
    func replacingTargetKeepsSymbolicLinkPathAndTargetItemsIntact() throws {
        let testDirectory = try makeTemporaryTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDirectory) }

        let originalTargetLocation = testDirectory.appendingPathComponent("Original.txt")
        let newTargetLocation = testDirectory.appendingPathComponent("Replacement.txt")
        try Data("original".utf8).write(to: originalTargetLocation)
        try Data("replacement".utf8).write(to: newTargetLocation)
        let symbolicLinkLocation = testDirectory.appendingPathComponent("Selected Link")
        try FileManager.default.createSymbolicLink(
            atPath: symbolicLinkLocation.path,
            withDestinationPath: originalTargetLocation.path
        )

        try SymbolicLinkTargetChanger.replaceTarget(
            of: symbolicLinkLocation,
            with: newTargetLocation
        )

        #expect(SymbolicLinkTargetChanger.isSymbolicLink(at: symbolicLinkLocation))
        #expect(
            try FileManager.default.destinationOfSymbolicLink(atPath: symbolicLinkLocation.path)
                == newTargetLocation.standardizedFileURL.path
        )
        #expect(try Data(contentsOf: originalTargetLocation) == Data("original".utf8))
        #expect(try Data(contentsOf: newTargetLocation) == Data("replacement".utf8))
        let remainingItemNames = try FileManager.default.contentsOfDirectory(
            atPath: testDirectory.path
        )
        #expect(
            !remainingItemNames.contains {
                $0.hasPrefix(SymbolicLinkTargetChanger.temporarySymbolicLinkNamePrefix)
            }
        )
    }

    @Test("A broken symbolic link can be redirected to an existing folder")
    func brokenSymbolicLinkCanBeRedirectedToExistingFolder() throws {
        let testDirectory = try makeTemporaryTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDirectory) }

        let missingTargetLocation = testDirectory.appendingPathComponent("Missing")
        let newTargetLocation = testDirectory.appendingPathComponent(
            "Replacement Folder",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: newTargetLocation,
            withIntermediateDirectories: false
        )
        let symbolicLinkLocation = testDirectory.appendingPathComponent("Broken Link")
        try FileManager.default.createSymbolicLink(
            atPath: symbolicLinkLocation.path,
            withDestinationPath: missingTargetLocation.path
        )
        #expect(!FileManager.default.fileExists(atPath: symbolicLinkLocation.path))

        try SymbolicLinkTargetChanger.replaceTarget(
            of: symbolicLinkLocation,
            with: newTargetLocation
        )

        #expect(SymbolicLinkTargetChanger.isSymbolicLink(at: symbolicLinkLocation))
        #expect(
            try FileManager.default.destinationOfSymbolicLink(atPath: symbolicLinkLocation.path)
                == newTargetLocation.standardizedFileURL.path
        )
    }

    @Test("A regular file is rejected without changing its contents")
    func regularFileIsRejectedWithoutChangingItsContents() throws {
        let testDirectory = try makeTemporaryTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDirectory) }

        let regularFileLocation = testDirectory.appendingPathComponent("Regular.txt")
        let newTargetLocation = testDirectory.appendingPathComponent("Replacement.txt")
        let originalContents = Data("keep me".utf8)
        try originalContents.write(to: regularFileLocation)
        try Data("replacement".utf8).write(to: newTargetLocation)

        #expect(throws: (any Error).self) {
            try SymbolicLinkTargetChanger.replaceTarget(
                of: regularFileLocation,
                with: newTargetLocation
            )
        }
        #expect(try Data(contentsOf: regularFileLocation) == originalContents)
    }

    @Test("A missing new target is rejected while preserving the old symbolic link")
    func missingNewTargetIsRejectedWhilePreservingOldSymbolicLink() throws {
        let testDirectory = try makeTemporaryTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDirectory) }

        let originalTargetLocation = testDirectory.appendingPathComponent("Original.txt")
        try Data("original".utf8).write(to: originalTargetLocation)
        let symbolicLinkLocation = testDirectory.appendingPathComponent("Selected Link")
        try FileManager.default.createSymbolicLink(
            atPath: symbolicLinkLocation.path,
            withDestinationPath: originalTargetLocation.path
        )
        let missingNewTargetLocation = testDirectory.appendingPathComponent("Missing.txt")

        #expect(
            throws: SymbolicLinkTargetChangeError.newTargetDoesNotExist(
                missingNewTargetLocation.standardizedFileURL.path
            )
        ) {
            try SymbolicLinkTargetChanger.replaceTarget(
                of: symbolicLinkLocation,
                with: missingNewTargetLocation
            )
        }
        #expect(
            try FileManager.default.destinationOfSymbolicLink(atPath: symbolicLinkLocation.path)
                == originalTargetLocation.path
        )
    }

    private func makeTemporaryTestDirectory() throws -> URL {
        let testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MenuHelperFileOperationsTests-" + UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: testDirectory,
            withIntermediateDirectories: false
        )
        return testDirectory
    }
}
