//
//  BobV1App.swift
//  BobV1
//
//  Created by Dione Marshall on 10/12/26.
//

import SwiftUI
import UIKit

@main
struct BobV1App: App {
    init() {
        #if !DEBUG
        if DevArgs.enabled { NSLog("[jelbies] DEV ARGS ENABLED in a non-Debug build: never ship this to the App Store") }
        #endif
        LaunchTiming.mark("app init"); StartFlow.applyLaunchArguments(); PerfMeter.configure(); PhotoAlbum.register(); FootLog.configure() }          // -ResetForAdoption 1 (simulator) wipes before anything reads a save

    /// iPad only (sizeRestrictions is nil on iPhone): a resizable window never goes below about 600 x 500 pt.
    @MainActor private static func applyPadMinimumWindow() {
        guard HUDLayout.isPad else { return }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.sizeRestrictions?.minimumSize = CGSize(width: 600, height: 500)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear { Self.applyPadMinimumWindow() }
        }
        AssistiveAccess {          // Assistive Access: a simplified care scene (Accessibility/SimpleCareScene.swift)
            SimpleCareScene()
        }
    }
}
