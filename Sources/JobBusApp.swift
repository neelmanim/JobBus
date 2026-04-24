import SwiftUI
import SwiftData

@main
struct JobBusApp: App {
    @StateObject private var appViewModel = AppViewModel()
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appViewModel)
                .frame(minWidth: 1000, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        
        Settings {
            SettingsView()
                .environmentObject(appViewModel)
        }
    }
}
