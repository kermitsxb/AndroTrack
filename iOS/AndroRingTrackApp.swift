//
//  ThermoTrackApp.swift
//  Shared
//
//  Created by Benoit Sida on 2021-07-13.
//

import SwiftUI

@main
struct ThermoTrackApp: App {
    @StateObject private var settingsStore = SettingsStore.shared
    @UIApplicationDelegateAdaptor(ThermoTrackAppDelegate.self) private var appDelegate
    
    var body: some Scene {
        WindowGroup {
            RequirementView()
                .environmentObject(settingsStore)
                .preferredColorScheme(.dark)
        }
    }
}
