//
//  FinderCommChannel.swift
//  MenuHelper
//
//  Created by Kyle on 2021/10/20.
//

import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: subsystem, category: "app_comm_channel")

@MainActor
final class FinderCommChannel {
    private var notificationObservers: [any NSObjectProtocol] = []

    func setup() {
        guard notificationObservers.isEmpty else { return }

        let center = DistributedNotificationCenter.default()
        notificationObservers = [
            center.addObserver(
                forName: .init(rawValue: "ChoosePermissionFolder"),
                object: mainApplicationBundleIdentifier,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.choosePermissionFolder()
                }
            },
            center.addObserver(
                forName: .init(rawValue: "RefreshMenuItems"),
                object: mainApplicationBundleIdentifier,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshMenuItems()
                }
            },
            center.addObserver(
                forName: .init(rawValue: "RefreshFolderItems"),
                object: mainApplicationBundleIdentifier,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshFolderItems()
                }
            },
        ]
    }

    func send(name: String, data: [AnyHashable: Any]? = nil) {
        logger.notice("Sending \(name) data: \(data ?? [:])")
        DistributedNotificationCenter.default()
            .postNotificationName(.init(rawValue: name),
                                  object: mainApplicationBundleIdentifier,
                                  userInfo: data,
                                  deliverImmediately: true)
    }

    private func choosePermissionFolder() {
        print(#function)
        let folderSelectionPanel = NSOpenPanel()
        folderSelectionPanel.allowsMultipleSelection = true
        folderSelectionPanel.allowedContentTypes = [.folder]
        folderSelectionPanel.canChooseDirectories = true
        if let passwordDatabaseEntry = getpwuid(getuid()),
           let homeDirectoryPathPointer = passwordDatabaseEntry.pointee.pw_dir {
            let homeDirectoryPath = FileManager.default.string(
                withFileSystemRepresentation: homeDirectoryPathPointer,
                length: strlen(homeDirectoryPathPointer)
            )
            folderSelectionPanel.directoryURL = URL(fileURLWithPath: homeDirectoryPath)
        } else {
            folderSelectionPanel.directoryURL = URL(fileURLWithPath: "/Users")
        }
        if folderSelectionPanel.runModal() == .OK {
            folderStore.appendItems(folderSelectionPanel.urls.map { BookmarkFolderItem($0) })
            send(name: "AppRefreshFolderItems", data: nil)
        }
    }

    private func refreshMenuItems() {
        logger.notice("Refresh menu items")
        menuStore.refresh()
        finderMenuSnapshot.replace(
            applicationMenuItems: menuStore.appItems,
            actionMenuItems: menuStore.actionItems
        )
        AppIconCache.shared.prewarm(applicationLocations: menuStore.appItems.map(\.url))
    }

    private func refreshFolderItems() {
        logger.notice("Refresh folder items")
        folderStore.refresh()
    }

    nonisolated private var mainApplicationBundleIdentifier: String {
        guard var bundleIdentifier = Bundle.main.bundleIdentifier,
              let extensionSeparatorIndex = bundleIdentifier.lastIndex(of: ".")
        else { return "" }
        bundleIdentifier.removeSubrange(extensionSeparatorIndex ..< bundleIdentifier.endIndex)
        return bundleIdentifier
    }
}
