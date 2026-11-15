//
//  AppDelegate.swift
//  SpacedownDrop
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Release-1 hooks (docs/contract-r1.md): each feature lives in its own file.
        SettingsWindow.install()
        Onboarding.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

}
