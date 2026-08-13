//
//  AppCommChannel.swift
//  MenuHelper
//
//  Created by Kyle on 2021/10/20.
//

import Foundation
import os.log

nonisolated private let logger = Logger(subsystem: subsystem, category: "app_comm_channel")

@MainActor
final class AppCommChannel {
    weak var folderItemStore: FolderItemStore?
    private var notificationObservers: [any NSObjectProtocol] = []

    func setup(store: FolderItemStore) {
        folderItemStore = store
        guard notificationObservers.isEmpty else { return }

        let center = DistributedNotificationCenter.default()
        let observer = center.addObserver(
            forName: .init(rawValue: "RefreshFolderItems"),
            object: bundleIdentifier,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshFolderItems()
            }
        }
        notificationObservers.append(observer)
    }

    nonisolated func send(name: String, data: [AnyHashable: Any]? = nil) {
        logger.notice("Sending \(name) data: \(data ?? [:])")
        DistributedNotificationCenter.default()
            .postNotificationName(.init(rawValue: name),
                                  object: bundleIdentifier,
                                  userInfo: data,
                                  deliverImmediately: true)
    }

    private func refreshFolderItems() {
        logger.notice("Refresh folder items")
        folderItemStore?.refresh()
    }
}
