//
//  ArkavoApp.swift
//  Arkavo
//
//  Created by Paul Flynn on 4/12/24.
//

import SwiftUI

@main
struct ArkavoApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
