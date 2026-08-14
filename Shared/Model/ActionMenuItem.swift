//
//  ActionMenuItem.swift
//  ActionMenuItem
//
//  Created by Kyle on 2021/10/9.
//

import AppKit
import Foundation

nonisolated struct ActionMenuItem: MenuItem {
    private static let displayImage = NSImage(named: "icon")!
    private static let contextualMenuImage = AppIconCache.menuThumbnail(from: displayImage)
        ?? displayImage

    static func == (leftItem: ActionMenuItem, rightItem: ActionMenuItem) -> Bool {
        leftItem.name == rightItem.name
    }

    var key: String
    var name: String { String(localized: String.LocalizationValue(key)) }
    var enabled = true
    var actionIndex: Int

    var icon: NSImage { Self.displayImage }
    var menuIcon: NSImage { Self.contextualMenuImage }
}

extension ActionMenuItem {
    static let all: [ActionMenuItem] = [
        .copyPath,
        copyFileName,
        .goParent,
        .newFile,
        .changeSymbolicLinkTarget,
    ]

    static let copyPath = ActionMenuItem(key: "Copy Path", actionIndex: 0)
    static let copyFileName = ActionMenuItem(key: "Copy File Name", actionIndex: 1)
    static let goParent = ActionMenuItem(key: "Go Parent Directory", actionIndex: 2)
    static let newFile = ActionMenuItem(key: "New File", actionIndex: 3)
    static let changeSymbolicLinkTarget = ActionMenuItem(
        key: "Change Symbolic Link Target",
        actionIndex: 4
    )

    // MARK: - Making the compiler to extract Localized key

    #if DEBUG
    // FIXME: - Refactor this when compiler time const is introduced to Swift
    private static let copyPathString = NSLocalizedString("Copy Path", comment: "Copy Path")
    private static let copyFileNameString = NSLocalizedString("Copy File Name", comment: "Copy File Name")
    private static let goParentString = NSLocalizedString("Go Parent Directory", comment: "Go Parent Directory")
    private static let newFileString = NSLocalizedString("New File", comment: "New File")
    private static let changeSymbolicLinkTargetString = NSLocalizedString(
        "Change Symbolic Link Target",
        comment: "Change Symbolic Link Target"
    )
    #endif
}
