//
//  AndroRingTrackApp.swift
//  Shared
//
//  Created by Benoit Sida on 2021-07-13.
//

import SwiftUI

@main
struct AndroRingTrackApp: App {
    @StateObject private var settingsStore = SettingsStore.shared
    @UIApplicationDelegateAdaptor(AndroRingTrackAppDelegate.self) private var appDelegate
    
    var body: some Scene {
        WindowGroup {
            RequirementView()
                .environmentObject(settingsStore)
                .preferredColorScheme(.dark)
        }
    }
}
