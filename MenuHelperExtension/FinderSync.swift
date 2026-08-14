//
//  FinderSync.swift
//  MenuHelperExtension
//
//  Created by Kyle on 2021/6/27.
//

import Cocoa
import Darwin
import FinderSync
import os.log

@MainActor let menuStore = MenuItemStore()
@MainActor let folderStore = FolderItemStore()
@MainActor let channel = FinderCommChannel()
let finderMenuSnapshot = FinderMenuSnapshot()
private let logger = Logger(subsystem: subsystem, category: "menu")

final class FinderMenuSnapshot: @unchecked Sendable {
    private let accessLock = NSLock()
    private var applicationMenuItems: [AppMenuItem] = []
    private var actionMenuItems: [ActionMenuItem] = []

    func replace(
        applicationMenuItems: [AppMenuItem],
        actionMenuItems: [ActionMenuItem]
    ) {
        accessLock.lock()
        defer { accessLock.unlock() }
        self.applicationMenuItems = applicationMenuItems
        self.actionMenuItems = actionMenuItems
    }

    func currentItems() -> (
        applicationMenuItems: [AppMenuItem],
        actionMenuItems: [ActionMenuItem]
    ) {
        accessLock.lock()
        defer { accessLock.unlock() }
        return (applicationMenuItems, actionMenuItems)
    }

    func applicationMenuItem(named menuTitle: String) -> AppMenuItem? {
        accessLock.lock()
        defer { accessLock.unlock() }
        return applicationMenuItems.first { menuTitle.contains($0.name) }
    }

    func actionMenuItem(named menuTitle: String) -> ActionMenuItem? {
        accessLock.lock()
        defer { accessLock.unlock() }
        return actionMenuItems.first { $0.name == menuTitle }
    }
}

class FinderSync: FIFinderSync {
    override init() {
        super.init()
        Task { @MainActor in
            channel.setup()
            logger.notice("FinderSync() launched from \(Bundle.main.bundlePath, privacy: .public)")
            FIFinderSyncController.default().directoryURLs = Set(folderStore.syncItems.map { URL(fileURLWithPath: $0.path) })
            logger.notice("Init sync directory is \(folderStore.syncItems.map(\.path).joined(separator: "\n"), privacy: .public)")

            finderMenuSnapshot.replace(
                applicationMenuItems: menuStore.appItems,
                actionMenuItems: menuStore.actionItems
            )
            AppIconCache.shared.prewarm(applicationLocations: menuStore.appItems.map(\.url))

            // Monitor volumes
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { notification in
                if let volumeLocation = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL {
                    Task { @MainActor in
                        folderStore.appendItem(SyncFolderItem(volumeLocation))
                    }
                }
            }
        }
    }

    // MARK: - Menu and toolbar item support

    override var toolbarItemName: String { UserDefaults.group.showToolbarItemMenu ? String(localized: "MenuHelper") : "" }

    override var toolbarItemToolTip: String { UserDefaults.group.showToolbarItemMenu ? String(localized: "MenuHelper Menu") : "" }

    override var toolbarItemImage: NSImage {
        func defaultImage() -> NSImage {
            logger.info("showToolbarItemMenu: \(UserDefaults.group.showToolbarItemMenu, privacy: .public)")
            return NSImage()
        }
        if UserDefaults.group.showToolbarItemMenu {
            return NSImage(systemSymbolName: "terminal", accessibilityDescription: "MenuHelper Menu") ?? defaultImage()
        } else {
            return defaultImage()
        }
    }

    // This should not be marked as MainActor otherwise it will trigger a crash
    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        switch menuKind {
        case .contextualMenuForItems:
            if !UserDefaults.group.showContextualMenuForItem { return NSMenu() }
        case .contextualMenuForContainer:
            if !UserDefaults.group.showContextualMenuForContainer { return NSMenu() }
        case .contextualMenuForSidebar:
            if !UserDefaults.group.showContextualMenuForSidebar { return NSMenu() }
        case .toolbarItemMenu:
            if !UserDefaults.group.showToolbarItemMenu { return NSMenu() }
        @unknown default:
            break
        }

        logger.notice("Create menu for \(menuKind.rawValue)")
        let currentItems = finderMenuSnapshot.currentItems()
        let finderSyncController = FIFinderSyncController.default()
        let selectedItemLocations = finderSyncController.selectedItemURLs() ?? []
        let currentFileLocations: [URL]
        if selectedItemLocations.isEmpty,
           let targetLocation = finderSyncController.targetedURL() {
            currentFileLocations = [targetLocation]
        } else {
            currentFileLocations = selectedItemLocations
        }
        return buildMenu(
            for: menuKind,
            applicationMenuItems: currentItems.applicationMenuItems,
            actionMenuItems: currentItems.actionMenuItems,
            currentFileLocations: currentFileLocations
        )
    }

    private func buildMenu(
        for menuKind: FIMenuKind,
        applicationMenuItems: [AppMenuItem],
        actionMenuItems: [ActionMenuItem],
        currentFileLocations: [URL]
    ) -> NSMenu {
        let menu = NSMenu(title: "MenuHelper")
        menu.showsStateColumn = true

        let applicationMenu: NSMenu
        if UserDefaults.group.showSubMenuForApplication {
            applicationMenu = NSMenu()
            let applicationSubMenuItem = NSMenuItem(title: String(localized: "Application Menus"), action: nil, keyEquivalent: "")
            menu.addItem(applicationSubMenuItem)
            menu.setSubmenu(applicationMenu, for: applicationSubMenuItem)
        } else {
            applicationMenu = menu
        }
        for item in applicationMenuItems.filter(\.enabled) {
            let menuItem = NSMenuItem()
            menuItem.target = self
            menuItem.title = String(format: String(localized: "Open in %@", comment: "Open in the given application"), item.name)
            menuItem.action = #selector(menuAction(_:))
            menuItem.toolTip = "\(item.name)"
            menuItem.tag = 0
            if menuKind == .toolbarItemMenu || UserDefaults.group.showIconForApplication {
                menuItem.image = item.menuIcon
            }
            applicationMenu.addItem(menuItem)
        }

        let actionMenu: NSMenu
        if UserDefaults.group.showSubMenuForAction {
            actionMenu = NSMenu()
            let actionSubMenuItem = NSMenuItem(title: String(localized: "Action Menus"), action: nil, keyEquivalent: "")
            menu.addItem(actionSubMenuItem)
            menu.setSubmenu(actionMenu, for: actionSubMenuItem)
        } else {
            actionMenu = menu
        }
        for actionMenuItem in actionMenuItems.filter(\.enabled) {
            guard shouldInclude(
                actionMenuItem,
                for: currentFileLocations
            ) else { continue }

            let menuItem = NSMenuItem()
            menuItem.target = self
            menuItem.title = actionMenuItem.name
            menuItem.action = #selector(menuAction(_:))
            menuItem.toolTip = "\(actionMenuItem.name)"
            menuItem.tag = 1
            if menuKind == .toolbarItemMenu || UserDefaults.group.showIconForAction {
                menuItem.image = actionMenuItem.menuIcon
            }
            actionMenu.addItem(menuItem)
        }
        return menu
    }

    private func shouldInclude(
        _ actionMenuItem: ActionMenuItem,
        for currentFileLocations: [URL]
    ) -> Bool {
        guard actionMenuItem.actionIndex == ActionMenuItem.changeSymbolicLinkTarget.actionIndex else {
            return true
        }
        guard currentFileLocations.count == 1,
              let symbolicLinkLocation = currentFileLocations.first
        else { return false }
        return SymbolicLinkTargetChanger.isSymbolicLink(at: symbolicLinkLocation)
    }

    @objc
    func menuAction(_ menuItem: NSMenuItem) {
        guard let targetLocation = FIFinderSyncController.default().targetedURL(),
              let selectedItemLocations = FIFinderSyncController.default().selectedItemURLs() else { return }
        logger.notice("Click menu \"\(menuItem.title, privacy: .public)\", index = \(menuItem.tag, privacy: .public), target = \(targetLocation, privacy: .public), items = \(selectedItemLocations, privacy: .public)]")

        let fileLocations = selectedItemLocations.isEmpty ? [targetLocation] : selectedItemLocations
        switch menuItem.tag {
        case 0:
            let item = finderMenuSnapshot.applicationMenuItem(named: menuItem.title)
            item?.menuClick(with: fileLocations)
        case 1:
            let item = finderMenuSnapshot.actionMenuItem(named: menuItem.title)
            item?.menuClick(with: fileLocations)
        default:
            break
        }
    }
}
