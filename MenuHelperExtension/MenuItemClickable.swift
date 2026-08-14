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
        case changeSymbolicLinkTarget
    }

    func menuClick(with fileLocations: [URL]) {
        Task { @MainActor in
            let actionResult = await performAction(with: fileLocations)
            if actionResult.success {
                logger.notice("\(actionResult.description, privacy: .public)")
            } else {
                logger.error("\(actionResult.description, privacy: .public)")
            }
        }
    }

    @MainActor
    private func performAction(with fileLocations: [URL]) async -> ActionMenuResult {
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
        case .changeSymbolicLinkTarget:
            return await changeSymbolicLinkTarget(for: fileLocations)
        }
    }

    @MainActor
    private func changeSymbolicLinkTarget(for fileLocations: [URL]) async -> ActionMenuResult {
        guard fileLocations.count == 1,
              let symbolicLinkLocation = fileLocations.first
        else {
            let failureDescription = String(
                localized: "Select exactly one symbolic link in Finder.",
                comment: "Failure shown when the symbolic link target action receives an invalid selection"
            )
            showSymbolicLinkTargetChangeResult(
                success: false,
                informativeText: failureDescription
            )
            return ActionMenuResult(message: failureDescription)
        }

        guard SymbolicLinkTargetChanger.isSymbolicLink(at: symbolicLinkLocation) else {
            let failureDescription = String(
                localized: "The selected Finder item is no longer a symbolic link.",
                comment: "Failure shown when a selected symbolic link changed before the action ran"
            )
            showSymbolicLinkTargetChangeResult(
                success: false,
                informativeText: failureDescription
            )
            return ActionMenuResult(message: failureDescription)
        }

        do {
            let oldTargetInformation = try SymbolicLinkTargetChanger.targetInformation(
                for: symbolicLinkLocation
            )
            let newTargetSelectionPanel = NSOpenPanel()
            newTargetSelectionPanel.allowsMultipleSelection = false
            newTargetSelectionPanel.canChooseFiles = true
            newTargetSelectionPanel.canChooseDirectories = true
            newTargetSelectionPanel.canCreateDirectories = false
            newTargetSelectionPanel.title = String(
                localized: "Select New Symbolic Link Target",
                comment: "Title for choosing a new symbolic link target"
            )
            newTargetSelectionPanel.message = String(
                localized: "Choose the file or folder that the symbolic link should point to.",
                comment: "Instructions for choosing a new symbolic link target"
            )
            newTargetSelectionPanel.prompt = String(
                localized: "Select",
                comment: "Button for selecting a new symbolic link target"
            )

            let fileManager = FileManager.default
            if fileManager.directoryExists(
                atPath: oldTargetInformation.displayedDestinationLocation.path
            ) {
                newTargetSelectionPanel.directoryURL = oldTargetInformation
                    .displayedDestinationLocation
            } else if fileManager.fileExists(
                atPath: oldTargetInformation.displayedDestinationLocation.path
            ) {
                newTargetSelectionPanel.directoryURL = oldTargetInformation
                    .displayedDestinationLocation
                    .deletingLastPathComponent()
            } else {
                newTargetSelectionPanel.directoryURL = symbolicLinkLocation
                    .deletingLastPathComponent()
            }

            let panelResponse = await newTargetSelectionPanel.begin()
            logger.notice("Symbolic link target NSOpenPanel response \(panelResponse.rawValue)")
            guard panelResponse == .OK,
                  let selectedNewTargetLocation = newTargetSelectionPanel.urls.first
            else {
                return ActionMenuResult(
                    success: true,
                    message: "Symbolic link target selection cancelled"
                )
            }
            defer { selectedNewTargetLocation.stopAccessingSecurityScopedResource() }

            let standardizedNewTargetLocation = selectedNewTargetLocation.standardizedFileURL
            let confirmationAlert = NSAlert()
            confirmationAlert.alertStyle = .warning
            confirmationAlert.messageText = String(
                localized: "Change Symbolic Link Target?",
                comment: "Confirmation title before changing a symbolic link target"
            )
            confirmationAlert.informativeText = String(
                format: String(
                    localized: "Old Location:\n%@\n\nNew Location:\n%@",
                    comment: "Old and new symbolic link target locations in the confirmation alert"
                ),
                oldTargetInformation.displayedDestinationLocation.path,
                standardizedNewTargetLocation.path
            )
            confirmationAlert.addButton(
                withTitle: String(
                    localized: "Change",
                    comment: "Button that confirms changing a symbolic link target"
                )
            )
            confirmationAlert.addButton(
                withTitle: String(
                    localized: "Cancel",
                    comment: "Button that cancels changing a symbolic link target"
                )
            )
            guard confirmationAlert.runModal() == .alertFirstButtonReturn else {
                return ActionMenuResult(
                    success: true,
                    message: "Symbolic link target change cancelled"
                )
            }

            try SymbolicLinkTargetChanger.replaceTarget(
                of: symbolicLinkLocation,
                with: standardizedNewTargetLocation
            )
            let successDescription = String(
                format: String(
                    localized: "The symbolic link now points to:\n%@",
                    comment: "Successful symbolic link target change details"
                ),
                standardizedNewTargetLocation.path
            )
            showSymbolicLinkTargetChangeResult(
                success: true,
                informativeText: successDescription
            )
            return ActionMenuResult(
                success: true,
                message: "Changed symbolic link target"
            )
        } catch {
            let caughtError = error as NSError
            let failureDescription = [
                caughtError.localizedDescription,
                caughtError.localizedFailureReason,
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            showSymbolicLinkTargetChangeResult(
                success: false,
                informativeText: failureDescription
            )
            return ActionMenuResult(message: failureDescription)
        }
    }

    @MainActor
    private func showSymbolicLinkTargetChangeResult(
        success: Bool,
        informativeText: String
    ) {
        let resultAlert = NSAlert()
        resultAlert.alertStyle = success ? .informational : .critical
        resultAlert.messageText = success
            ? String(
                localized: "Change Succeeded",
                comment: "Title for a successful symbolic link target change"
            )
            : String(
                localized: "Change Failed",
                comment: "Title for a failed symbolic link target change"
            )
        resultAlert.informativeText = informativeText
        resultAlert.addButton(withTitle: String(localized: "OK", comment: "OK button"))
        resultAlert.runModal()
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
