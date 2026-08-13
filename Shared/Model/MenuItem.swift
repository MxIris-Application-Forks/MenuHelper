//
//  MenuItem.swift
//  MenuItem
//
//  Created by Kyle on 2021/10/9.
//

import AppKit

nonisolated protocol MenuItem: Hashable, Identifiable, Codable, Sendable {
    var name: String { get }
    var enabled: Bool { get set }
    var icon: NSImage { get }
}

extension MenuItem {
    nonisolated var id: String { name }
}
