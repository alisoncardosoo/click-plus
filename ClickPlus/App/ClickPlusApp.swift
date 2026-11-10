import SwiftUI

@main struct ClickPlusApp: App {
    @StateObject private var state = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow
    var body: some Scene {
        WindowGroup("Click +", id: "main") {
            ContentView().background(WindowDockBridge()).environmentObject(state).tint(Color.clickAccent).onAppear { delegate.state = state }
        }.defaultSize(width: 980, height: 790)
        MenuBarExtra("Click +", systemImage: "computermouse") {
            MenuPanel {
                NSApp.setActivationPolicy(.regular)
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }.environmentObject(state)
        }.menuBarExtraStyle(.window)

    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var state: AppState?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let state else { return .terminateNow }
        state.shutdown { success in
            if !success { state.message = "Não foi possível restaurar o DPI. Reconecte o mouse e tente sair novamente." }
            sender.reply(toApplicationShouldTerminate: success)
        }
        return .terminateLater
    }
}
