//
//  FolderItem.swift
//  MenuHelper
//
//  Created by Kyle on 2021/10/20.
//

import Foundation

nonisolated protocol FolderItem: Hashable, Identifiable, Codable, Sendable {
    var path: String { get }
}

extension FolderItem {
    nonisolated var id: String { path }
}
