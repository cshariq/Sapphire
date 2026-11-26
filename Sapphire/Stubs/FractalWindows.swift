//
//  FractalWindows.swift
//  Sapphire
//
//  Public stand-in for Fractal Windows, an Ultra feature whose engine lives in the private
//  Sapphire/Services/Fractal folder. The app's launch, URL and quit paths call these hooks;
//  in a public build they do nothing and the settings pane shows the feature as unavailable.
//

#if !SAPPHIRE_FULL_BUILD
import Foundation

/// The Fractal settings tab a deep link asks for (the private engine defines the full set).
enum SettingsPane: String, Sendable {
    case general
}

@MainActor enum FractalAppHooks {
    static func didFinishLaunching() {}
    static func bootstrapMainApp(openSettings: @escaping (SettingsPane?) -> Void) {}
    static func stopMainApp() {}
    static func willTerminate() {}
    @discardableResult static func handle(url: URL) -> Bool { false }
    static var isRunning: Bool { false }
}
#endif
