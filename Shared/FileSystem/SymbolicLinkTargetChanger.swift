//
//  SymbolicLinkTargetChanger.swift
//  MenuHelperExtension
//

import Darwin
import Foundation

nonisolated struct SymbolicLinkTargetInformation: Equatable, Sendable {
    let storedDestinationPath: String
    let displayedDestinationLocation: URL
}

nonisolated enum SymbolicLinkTargetChangeError: Equatable, LocalizedError, Sendable {
    case newTargetDoesNotExist(String)
    case verificationFailed(expectedDestinationPath: String, actualDestinationPath: String)

    var errorDescription: String? {
        switch self {
        case .newTargetDoesNotExist:
            String(
                localized: "The selected new location no longer exists.",
                comment: "Symbolic link target change failure when the selected destination disappeared"
            )
        case .verificationFailed:
            String(
                localized: "The symbolic link target could not be verified.",
                comment: "Symbolic link target change verification failure"
            )
        }
    }

    var failureReason: String? {
        switch self {
        case let .newTargetDoesNotExist(newTargetPath):
            newTargetPath
        case let .verificationFailed(expectedDestinationPath, actualDestinationPath):
            String(
                format: String(
                    localized: "Expected: %@\nActual: %@",
                    comment: "Expected and actual symbolic link destinations after a target change"
                ),
                expectedDestinationPath,
                actualDestinationPath
            )
        }
    }
}

nonisolated enum SymbolicLinkTargetChanger {
    static let temporarySymbolicLinkNamePrefix = ".MenuHelper-SymbolicLink-Target-"

    static func isSymbolicLink(
        at symbolicLinkLocation: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: symbolicLinkLocation.path)) != nil
    }

    static func targetInformation(
        for symbolicLinkLocation: URL,
        fileManager: FileManager = .default
    ) throws -> SymbolicLinkTargetInformation {
        let storedDestinationPath = try fileManager.destinationOfSymbolicLink(
            atPath: symbolicLinkLocation.path
        )
        let displayedDestinationLocation: URL

        if (storedDestinationPath as NSString).isAbsolutePath {
            displayedDestinationLocation = URL(fileURLWithPath: storedDestinationPath)
                .standardizedFileURL
        } else {
            displayedDestinationLocation = symbolicLinkLocation
                .deletingLastPathComponent()
                .appendingPathComponent(storedDestinationPath)
                .standardizedFileURL
        }

        return SymbolicLinkTargetInformation(
            storedDestinationPath: storedDestinationPath,
            displayedDestinationLocation: displayedDestinationLocation
        )
    }

    static func replaceTarget(
        of symbolicLinkLocation: URL,
        with newTargetLocation: URL,
        fileManager: FileManager = .default
    ) throws {
        _ = try targetInformation(for: symbolicLinkLocation, fileManager: fileManager)

        let standardizedNewTargetLocation = newTargetLocation.standardizedFileURL
        guard fileManager.fileExists(atPath: standardizedNewTargetLocation.path) else {
            throw SymbolicLinkTargetChangeError.newTargetDoesNotExist(
                standardizedNewTargetLocation.path
            )
        }

        let temporarySymbolicLinkLocation = symbolicLinkLocation
            .deletingLastPathComponent()
            .appendingPathComponent(
                temporarySymbolicLinkNamePrefix + UUID().uuidString,
                isDirectory: false
            )
        try fileManager.createSymbolicLink(
            atPath: temporarySymbolicLinkLocation.path,
            withDestinationPath: standardizedNewTargetLocation.path
        )

        var shouldRemoveTemporarySymbolicLink = true
        defer {
            if shouldRemoveTemporarySymbolicLink {
                try? fileManager.removeItem(at: temporarySymbolicLinkLocation)
            }
        }

        let replacementResult = temporarySymbolicLinkLocation.path.withCString {
            temporarySymbolicLinkPathPointer in
            symbolicLinkLocation.path.withCString { symbolicLinkPathPointer in
                Darwin.rename(temporarySymbolicLinkPathPointer, symbolicLinkPathPointer)
            }
        }
        guard replacementResult == 0 else {
            let systemErrorNumber = errno
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(systemErrorNumber),
                userInfo: [NSFilePathErrorKey: symbolicLinkLocation.path]
            )
        }
        shouldRemoveTemporarySymbolicLink = false

        let resultingDestinationPath = try fileManager.destinationOfSymbolicLink(
            atPath: symbolicLinkLocation.path
        )
        guard resultingDestinationPath == standardizedNewTargetLocation.path else {
            throw SymbolicLinkTargetChangeError.verificationFailed(
                expectedDestinationPath: standardizedNewTargetLocation.path,
                actualDestinationPath: resultingDestinationPath
            )
        }
    }
}
