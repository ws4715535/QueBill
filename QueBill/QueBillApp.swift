//
//  QueBillApp.swift
//  QueBill
//
//  Created by ws on 2025/10/21.
//

import SwiftUI

@main
struct QueBillApp: App {
    @State private var dataStore = AccountDataStore()

    var body: some Scene {
        WindowGroup {
            ContentView(dataStore: dataStore)
        }
    }
}
