//
//  BobV1App.swift
//  BobV1
//
//  Created by Dione Marshall on 10/12/26.
//

import SwiftUI

@main
struct BobV1App: App {
    init() {
        #if !DEBUG
        if DevArgs.enabled { NSLog("[jelbies] DEV ARGS ENABLED in a non-Debug build: never ship this to the App Store") }
        #endif
        LaunchTiming.mark("app init"); StartFlow.applyLaunchArguments(); PerfMeter.configure(); PhotoAlbum.register(); FootLog.configure() }          // -ResetForAdoption 1 (simulator) wipes before anything reads a save

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        AssistiveAccess {          // Assistive Access: a simplified care scene (Accessibility/SimpleCareScene.swift)
            SimpleCareScene()
        }
    }
}
