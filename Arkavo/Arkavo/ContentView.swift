//
//  ContentView.swift
//  Arkavo
//
//  Created by Paul Flynn on 7/2/24.
//

import SwiftUI
import SwiftData
import CryptoKit
import OpenTDFKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    let webSocket = KASWebSocket();

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(items) { item in
                    NavigationLink {
                        Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
                    } label: {
                        Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                    }
                }
                .onDelete(perform: deleteItems)
            }
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
#endif
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
        } detail: {
            Text("Select an item")
        }
    }

    private func addItem() {
            let plaintext = "Keep this message secret".data(using: .utf8)!
            webSocket.setRewrapCallback { identifier, symmetricKey in
                defer {
                    print("END setRewrapCallback")
                }
                print("BEGIN setRewrapCallback")
                print("Received Rewrapped Symmetric key: \(String(describing: symmetricKey))")
            }
            webSocket.setKASPublicKeyCallback { publicKey in
                let kasRL = ResourceLocator(protocolEnum: .http, body: "localhost:8080")
                let kasMetadata = KasMetadata(resourceLocator: kasRL!, publicKey: publicKey, curve: .secp256r1)
                let remotePolicy = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: "localhost/123")
                var policy = Policy(type: .remote, body: nil, remote: remotePolicy, binding: nil)

                do {
                    // create
                    let nanoTDF = try createNanoTDF(kas: kasMetadata, policy: &policy, plaintext: plaintext)
                    print("Encryption successful")
                    webSocket.sendRewrapMessage(header: nanoTDF.header)
                } catch {
                    print("Error creating nanoTDF: \(error)")
                }
            }
            webSocket.connect()
            webSocket.sendPublicKey()
            webSocket.sendKASKeyMessage()
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
