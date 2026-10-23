//
//  BobV1App.swift
//  BobV1
//
//  Created by Dione Marshall on 10/12/26.
//

import SwiftUI

@main
struct BobV1App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        AssistiveAccess {          // Assistive Access: a simplified care scene (Accessibility/SimpleCareScene.swift)
            SimpleCareScene()
        }
    }
}
