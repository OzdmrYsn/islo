import SwiftUI

/// An agent's hook runs this same binary with `--agent-hook`; it answers
/// and exits before any of the app starts.
@main
enum IsloMain {
    static func main() {
        AgentHookCLI.runIfRequested()
        // One islo. at a time: a second copy would stack a second notch on
        // the first and take every volume key twice.
        let identifier = Bundle.main.bundleIdentifier ?? "com.ozdmrysn.islo"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }
        if !others.isEmpty { exit(0) }
        IsloApp.main()
    }
}

struct IsloApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        Settings {
            SettingsView(settings: settings) {
                NotificationCenter.default.post(
                    name: .isloShowOnboarding,
                    object: nil
                )
            }
        }
    }
}

extension Notification.Name {
    static let isloShowOnboarding = Notification.Name(
        "islo.showOnboarding"
    )

    static let isloShowSettings = Notification.Name(
        "islo.showSettings"
    )

    static let isloExpand = Notification.Name(
        "islo.expand"
    )

    static let isloCollapse = Notification.Name(
        "islo.collapse"
    )

    static let isloToggle = Notification.Name(
        "islo.toggle"
    )
}
