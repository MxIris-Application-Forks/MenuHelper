//
//  AppMenuItemView.swift
//  MenuHelper
//
//  Created by KyleYe on 2022/3/22.
//

import SwiftUI

struct AppMenuItemView: View {
    @Environment(MenuItemStore.self) private var store
    @State private var editingItem = false
    @Binding var item: AppMenuItem

    var body: some View {
        HStack {
            Image(nsImage: item.icon)
            Toggle(isOn: $item.enabled) {
                Text(item.name)
            }
            .toggleStyle(.button)
        }
        .contextMenu {
            Button {
                editingItem = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                if let index = store.appItems.firstIndex(where: { $0.id == item.id }) {
                    store.deleteAppItems(offsets: IndexSet(integer: index))
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $editingItem, onDismiss: nil) {
            AppMenuItemEditor(item: $item)
                .environment(store)
        }
    }
}

#Preview {
    @Previewable @State var store = MenuItemStore()
    return AppMenuItemView(item: .constant(.xcode!))
        .environment(store)
        .padding()
}
