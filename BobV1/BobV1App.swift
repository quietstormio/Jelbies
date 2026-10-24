//
//  BobV1App.swift
//  BobV1
//
//  Created by Dione Marshall on 10/12/26.
//

import SwiftUI

@main
struct BobV1App: App {
    init() { StartFlow.applyLaunchArguments(); PhotoAlbum.register() }          // -ResetForAdoption 1 (simulator) wipes before anything reads a save

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        AssistiveAccess {          // Assistive Access: a simplified care scene (Accessibility/SimpleCareScene.swift)
            SimpleCareScene()
        }
    }
}
