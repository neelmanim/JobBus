import SwiftUI
import AppKit

// MARK: - App Delegate
// SPM-built SwiftUI apps don't get proper foreground activation.
// This delegate ensures the app registers as a regular GUI app
// so text fields can receive keyboard focus and clipboard access.
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register as a regular foreground app (shows in Dock, gets menu bar)
        NSApplication.shared.setActivationPolicy(.regular)
        // Force activate so windows receive keyboard focus
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // Set app icon from bundled resource (SPM apps don't use Assets.xcassets)
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = iconImage
        }
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        // Ensure focus on every reactivation (e.g., switching back from another app)
        if let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct JobBusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appViewModel = AppViewModel()
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appViewModel)
                .frame(minWidth: 1000, minHeight: 700)
                .sheet(isPresented: Binding(
                    get: { !appViewModel.settings.hasCompletedOnboarding },
                    set: { if !$0 { appViewModel.settings.hasCompletedOnboarding = true; appViewModel.settings.save() } }
                )) {
                    OnboardingView()
                        .environmentObject(appViewModel)
                        .interactiveDismissDisabled()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        
        Settings {
            SettingsView()
                .environmentObject(appViewModel)
        }
    }
}
