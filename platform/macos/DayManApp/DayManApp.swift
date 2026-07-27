import AppKit
import SwiftUI

@main
struct DayManApp: App {
    var body: some Scene {
        WindowGroup {
            WebContainerView()
                .frame(minWidth: 760, minHeight: 720)
                .onOpenURL { url in
                    guard url.scheme == "dayman" else { return }
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1120, height: 860)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
