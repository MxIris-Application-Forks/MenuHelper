//
//  MenuHelperApp.swift
//  MenuHelper
//
//  Created by Kyle on 2021/6/27.
//

import SwiftUI

final class AppDelegate: NSResponder, NSApplicationDelegate {
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct MenuHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
                .toolbar(removing: .title)
        }
        .windowToolbarLabelStyle(fixed: .iconOnly)
        .defaultSize(width: 600, height: 400)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Window("Acknowledgements", id: "acknowledgements") {
            AcknowledgementsWindow()
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: "acknowledgements"))
        .commands {
            CommandGroup(after: .appSettings) {
                Button {
                    openWindow(id: "acknowledgements")
                } label: {
                    Text("Acknowledgements") + Text(verbatim: "...")
                }
            }
        }
        .defaultSize(width: 400, height: 300)
        .restorationBehavior(.disabled)

        Window("Support", id: "support") {
            SupportWindow()
                .frame(width: 600, height: 400)
                .toolbar(removing: .title)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .containerBackground(.thickMaterial, for: .window)
                .windowMinimizeBehavior(.disabled)
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .handlesExternalEvents(matching: Set(arrayLiteral: "support"))
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Support Author...") {
                    openWindow(id: "support")
                }
            }
        }

        Settings {
            SettingView()
        }
        .defaultAppStorage(.group)
    }
}

@MainActor let channel = AppCommChannel()
