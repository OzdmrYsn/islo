import Combine
import Sparkle

/// Owns Sparkle's updater for the lifetime of the application and exposes only
/// the user-facing controls islo needs.
@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    @Published private(set) var canCheckForUpdates = false
    /// Looks for new versions by itself and says when there is one.
    @Published private(set) var automaticChecksEnabled = true
    /// Also downloads and installs them without asking.
    @Published private(set) var automaticUpdatesEnabled = false
    /// A version found by a scheduled check that hasn't been looked at yet.
    @Published private(set) var availableVersion: String?

    private let updaterController: SPUStandardUpdaterController
    private let reminder = GentleReminder()

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: reminder
        )
        reminder.onFound = { [weak self] version in self?.availableVersion = version }
        reminder.onSeen = { [weak self] in self?.availableVersion = nil }

        let updater = updaterController.updater

        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)

        updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticChecksEnabled)

        updater.publisher(for: \.automaticallyChecksForUpdates)
            .combineLatest(
                updater.publisher(for: \.automaticallyDownloadsUpdates)
            )
            .map { checks, downloads in checks && downloads }
            .assign(to: &$automaticUpdatesEnabled)
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        updaterController.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        let updater = updaterController.updater
        updater.automaticallyChecksForUpdates = enabled
        if !enabled { updater.automaticallyDownloadsUpdates = false }
    }

    /// Installing by itself needs the checks, so turning it on turns those
    /// on too; turning it off leaves "tell me" in place.
    func setAutomaticUpdates(_ enabled: Bool) {
        let updater = updaterController.updater
        if enabled { updater.automaticallyChecksForUpdates = true }
        updater.automaticallyDownloadsUpdates = enabled
    }
}

/// islo. has no Dock icon, so Sparkle's window for a scheduled check could
/// open behind everything and never be seen. The notch says it instead;
/// Sparkle's window comes up when the user asks for it.
private final class GentleReminder: NSObject, SPUStandardUserDriverDelegate {
    var onFound: ((String) -> Void)?
    var onSeen: (() -> Void)?

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Right after launch the window is welcome; later it would interrupt.
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else { return }
        let version = update.displayVersionString
        DispatchQueue.main.async { [weak self] in self?.onFound?(version) }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        DispatchQueue.main.async { [weak self] in self?.onSeen?() }
    }

    func standardUserDriverWillFinishUpdateSession() {
        DispatchQueue.main.async { [weak self] in self?.onSeen?() }
    }
}
