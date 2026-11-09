//
//  MemoryPressure.swift
//  One observer for the system's memory warning. Owners register a handler that drops what they can rebuild (or saves what must not be
//  lost); the observer runs them all on the main queue, drops the prebuilt-body stash and logs how much memory is left.
//

import Foundation
import UIKit
import os

enum MemoryPressure {
    private static var handlers: [(name: String, run: () -> Bool)] = []
    private static var observer: NSObjectProtocol?
    /// Memory warnings seen since launch (diagnostics / tests).
    private(set) static var warnings = 0

    /// Registers (or replaces, by `name`) a handler. It returns false when its owner is gone, which removes it. Starts the observer on first use.
    static func register(_ name: String, _ run: @escaping () -> Bool) {
        handlers.removeAll { $0.name == name }
        handlers.append((name, run))
        install()
    }

    static func install() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { handleWarning() }
        }
    }

    /// Runs every handler (also the test / diagnostics entry point).
    static func handleWarning() {
        warnings += 1
        let before = os_proc_available_memory()
        ActorPrebuild.drop()
        handlers = handlers.filter { $0.run() }
        NSLog("[melon] memory warning #%d: %d handlers, available %.0f MB before", warnings, handlers.count, Double(before) / 1_048_576)
    }
}
