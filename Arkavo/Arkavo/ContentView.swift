//
//  ContentView.swift
//  Arkavo
//
//  Created by Paul Flynn on 4/12/24.
//

import AuthenticationServices
import CoreData
import LocalAuthentication
import SwiftUI

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Item.timestamp, ascending: true)],
        animation: .default
    )

    private var items: FetchedResults<Item>

    var body: some View {
        @ObservedObject var amViewModel = AuthenticationManagerViewModel()
        HStack {
            Button(action: amViewModel.authenticationManager.signUp) {
                Text("Sign up")
            }
            Text("|")
            Button(action: amViewModel.authenticationManager.signIn) {
                Text("Sign in")
            }
            Text("|")
            Button(action: removeAllItems) {
                Text("Remove all")
            }
        }
        
        NavigationView {
            List {
                ForEach(items) { item in
                    NavigationLink {
                        Text(cipherFormatter.string(from: item.dataVector))
                    } label: {
                        Text(OpenTDFWrapper().decrypt(item.dataVector))
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .toolbar {
                #if os(iOS)
                    ToolbarItem(placement: .navigationBarTrailing) {
                        EditButton()
                    }
                #endif
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
            Text("Select an item to decrypt")
        }
    }

    private func removeAllItems() {
        deleteItems(offsets: IndexSet(0..<items.count))
    }

    private func addItem() {
        withAnimation {
            let newItem = Item(context: viewContext)
            newItem.dataVector = OpenTDFWrapper().encrypt(randomString(length: 7))

            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            offsets.map { items[$0] }.forEach(viewContext.delete)

            do {
                try viewContext.save()
            } catch {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

struct HexDataFormatter {
    func string(from data: Data?) -> String {
        guard let data = data else { return "" }
        return data.map { String(format: "%02x", $0) }.joined()
    }
}

private let cipherFormatter = HexDataFormatter()

func randomString(length: Int) -> String {
    let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    return String((0..<length).map{ _ in letters.randomElement()! })
}

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
