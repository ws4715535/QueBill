//
//  ContentView.swift
//  QueBill
//
//  Created by ws on 2025/10/21.
//

import SwiftUI

struct ContentView: View {
    let dataStore: AccountDataStore

    var body: some View {
        RootView(dataStore: dataStore)
    }
}

#Preview {
    ContentView(dataStore: AccountDataStore())
}
