//
//  MenuItemClickable.swift
//  MenuHelperExtension
//
//  Created by Kyle on 2021/10/9.
//

import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: subsystem, category: "menu_click")

protocol MenuItemClickable: Sendable {
    func menuClick(with fileLocations: [URL])
}

extension AppMenuItem: MenuItemClickable {
    func menuClick(with fileLocations: [URL]) {
        Task { @MainActor in
            do {
                let openConfiguration = NSWorkspace.OpenConfiguration()
                openConfiguration.promptsUserIfNeeded = true
                openConfiguration.arguments = arguments + UserDefaults.group.globalApplicationArguments
                openConfiguration.environment = environment.merging(
                    UserDefaults.group.globalApplicationEnvironment,
                    uniquingKeysWith: { existingValue, _ in existingValue }
                )
                let runningApplication = try await NSWorkspace.shared.open(
                    fileLocations,
                    withApplicationAt: url,
                    configuration: openConfiguration
                )
                if let applicationPath = runningApplication.bundleURL?.path,
                   let applicationIdentifier = runningApplication.bundleIdentifier,
                   let launchDate = runningApplication.launchDate {
                    logger.notice("Success: open \(applicationIdentifier, privacy: .public) app at \(applicationPath, privacy: .public) in \(launchDate, privacy: .public)")
                }
            } catch let caughtError {
                guard let cocoaError = caughtError as? CocoaError,
                      let underlyingError = cocoaError.userInfo["NSUnderlyingError"] as? NSError else { return }
                logger.error("Error: \(cocoaError.localizedDescription)")
                if underlyingError.code == -10820 {
                    let alert = NSAlert(error: cocoaError)
                    alert.addButton(withTitle: String(localized: "OK", comment: "OK button"))
                    alert.addButton(withTitle: String(localized: "Remove", comment: "Remove app button"))
                    let alertResponse = alert.runModal()
                    logger.notice("NSAlert response result \(alertResponse.rawValue)")
                    switch alertResponse {
                    case .alertFirstButtonReturn:
                        logger.notice("Dismiss error with OK")
                    case .alertSecondButtonReturn:
                        logger.notice("Dismiss error with Remove app")
                        if let itemIndex = menuStore.appItems.firstIndex(of: self) {
                            menuStore.deleteAppItems(offsets: IndexSet(integer: itemIndex))
                            finderMenuSnapshot.replace(
                                applicationMenuItems: menuStore.appItems,
                                actionMenuItems: menuStore.actionItems
                            )
                        }
                    default:
                        break
                    }
                } else if let firstFileLocation = fileLocations.first {
                    let permissionPanel = NSOpenPanel()
                    permissionPanel.allowsMultipleSelection = true
                    permissionPanel.allowedContentTypes = [.folder]
                    permissionPanel.canChooseDirectories = true
                    permissionPanel.directoryURL = firstFileLocation
                    let panelResponse = await permissionPanel.begin()
                    logger.notice("NSOpenPanel response result \(panelResponse.rawValue)")
                    if panelResponse == .OK {
                        folderStore.appendItems(
                            permissionPanel.urls.map { selectedFolderLocation in
                                BookmarkFolderItem(selectedFolderLocation)
                            }
                        )
                    }
                }
            }
        }
    }
}

extension ActionMenuItem: MenuItemClickable {
    private enum ActionKind: Int {
        case copyPath
        case copyFileName
        case goToParentDirectory
        case createFile
    }

    func menuClick(with fileLocations: [URL]) {
        Task { @MainActor in
            let actionResult = performAction(with: fileLocations)
            if actionResult.success {
                logger.notice("\(actionResult.description, privacy: .public)")
            } else {
                logger.error("\(actionResult.description, privacy: .public)")
            }
        }
    }

    @MainActor
    private func performAction(with fileLocations: [URL]) -> ActionMenuResult {
        guard let actionKind = ActionKind(rawValue: actionIndex) else {
            return ActionMenuResult(
                message: "Unknown action index: \(actionIndex)"
            )
        }

        switch actionKind {
        case .copyPath:
            return copyToPasteboard(fileLocations.map(\.path))
        case .copyFileName:
            return copyToPasteboard(fileLocations.map(\.lastPathComponent))
        case .goToParentDirectory:
            let individualResults = fileLocations.map { fileLocation in
                let selectionSucceeded = NSWorkspace.shared.selectFile(
                    fileLocation.deletingLastPathComponent().path,
                    inFileViewerRootedAtPath: ""
                )
                return ActionMenuResult(success: selectionSucceeded)
            }
            return ActionMenuResult(
                success: individualResults.allSatisfy(\.success),
                individualResults: individualResults
            )
        case .createFile:
            let individualResults = fileLocations.map(createFile)
            return ActionMenuResult(
                success: individualResults.allSatisfy(\.success),
                individualResults: individualResults
            )
        }
    }

    @MainActor
    private func copyToPasteboard(_ pathComponents: [String]) -> ActionMenuResult {
        let copyOption = UserDefaults.group.copyOption
        let pasteboardString = pathComponents
            .map { pathComponent in
                switch copyOption {
                case .origin:
                    return pathComponent
                case .escape:
                    return pathComponent.replacingOccurrences(of: " ", with: #"\ "#)
                case .quoto:
                    return "\"\(pathComponent)\""
                }
            }
            .joined(separator: UserDefaults.group.copySeparator)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let writeSucceeded = pasteboard.setString(pasteboardString, forType: .string)
        return ActionMenuResult(
            success: writeSucceeded,
            message: "Pasteboard setString to \(pasteboardString)"
        )
    }

    @MainActor
    private func createFile(at fileLocation: URL) -> ActionMenuResult {
        let fileName = UserDefaults.group.newFileName
        let fileNameExtension = UserDefaults.group.newFileExtension.rawValue
        let fileManager = FileManager.default
        let targetLocation: URL
        if fileManager.directoryExists(atPath: fileLocation.path) {
            targetLocation = fileLocation
                .appendingPathComponent(fileName)
                .appendingPathExtension(fileNameExtension)
        } else {
            targetLocation = fileLocation
                .deletingLastPathComponent()
                .appendingPathComponent(fileName)
                .appendingPathExtension(fileNameExtension)
        }
        logger.notice("Trying to create empty file at \(targetLocation.path, privacy: .public)")
        let creationSucceeded = fileManager.createFile(
            atPath: targetLocation.path,
            contents: Data(),
            attributes: nil
        )
        return ActionMenuResult(success: creationSucceeded)
    }
}

struct ActionMenuResult: CustomStringConvertible, Sendable {
    var success = false
    var message: String?
    var individualResults: [ActionMenuResult]?

    var description: String {
        var descriptionText = "ActionMenuResult:\n"
        descriptionText.append("success: \(success ? "✅" : "❌") \n")
        if let message {
            descriptionText.append("message: \(message)\n")
        }
        if let individualResults {
            descriptionText.append("individualResults:\n")
            individualResults.forEach { individualResult in
                descriptionText.append(individualResult.description)
            }
            descriptionText.append("\n")
        }
        return descriptionText
    }
}

extension FileManager {
    fileprivate func directoryExists(atPath path: String) -> Bool {
        fileExists(atPath: path, isDirectory: true)
    }

    private func fileExists(atPath path: String, isDirectory: Bool) -> Bool {
        var directoryFlag = ObjCBool(isDirectory)
        let fileExists = fileExists(atPath: path, isDirectory: &directoryFlag)
        return fileExists && (directoryFlag.boolValue == isDirectory)
    }
}
