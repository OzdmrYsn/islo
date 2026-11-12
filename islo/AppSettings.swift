import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

enum PermissionState: Equatable {
    case granted
    case missing
    case notAsked
    /// Automation can only be checked while the target app runs.
    case appClosed
    case appNotInstalled
}

/// Folders macOS guards (Desktop, Documents, Downloads) that islo. watches.
enum ProtectedFolder: String, CaseIterable, Identifiable {
    /// Where screenshots are saved; Desktop unless the user changed it.
    case screenshots
    case downloads

    var id: String { rawValue }

    /// The privacy service macOS files access to this folder under, or nil
    /// when the folder isn't one macOS guards.
    static func privacyService(for url: URL) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        for (folder, service) in [
            ("Desktop", "SystemPolicyDesktopFolder"),
            ("Documents", "SystemPolicyDocumentsFolder"),
            ("Downloads", "SystemPolicyDownloadsFolder"),
        ] {
            let guarded = home + "/" + folder
            if path == guarded || path.hasPrefix(guarded + "/") { return service }
        }
        return nil
    }
}

/// Apps islo. controls through Apple Events.
enum AutomationTarget: String, CaseIterable, Identifiable {
    case music = "com.apple.Music"
    case spotify = "com.spotify.client"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .music: "Music"
        case .spotify: "Spotify"
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case turkish
    case english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .turkish: "Türkçe"
        case .english: "English"
        }
    }

    func value(turkish: String, english: String) -> String {
        switch self {
        case .turkish: turkish
        case .english: english
        }
    }
}

enum NotchIdleMode: String, CaseIterable, Identifiable {
    case visibleIsland
    case hiddenMini

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .visibleIsland:
            language.value(
                turkish: "Görünür Ada",
                english: "Visible Island"
            )
        case .hiddenMini:
            language.value(
                turkish: "Gizli Mini",
                english: "Hidden Mini"
            )
        }
    }

    func subtitle(language: AppLanguage) -> String {
        switch self {
        case .visibleIsland:
            language.value(
                turkish: "Müzik çalarken kapak ve dalga çentiğin yanında belirir; çalmadığında standart çentiğe döner.",
                english: "Artwork and the wave appear beside the notch while music plays; otherwise it returns to the standard notch."
            )
        case .hiddenMini:
            language.value(
                turkish: "Boştayken kamera çentiğinin içinde tamamen kaybolur.",
                english: "Disappears completely into the camera notch while idle."
            )
        }
    }

    var symbolName: String {
        switch self {
        case .visibleIsland: "rectangle.expand.vertical"
        case .hiddenMini: "eye.slash.fill"
        }
    }
}

enum NotchActivationMode: String, CaseIterable, Identifiable {
    case hover
    case click
    case activationZone

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .hover:
            language.value(
                turkish: "Üzerine gelince",
                english: "On hover"
            )
        case .click:
            language.value(
                turkish: "Yalnızca tıklayınca",
                english: "Only on click"
            )
        case .activationZone:
            language.value(
                turkish: "Orta etkin alana gelince",
                english: "On center activation zone"
            )
        }
    }

    func subtitle(language: AppLanguage) -> String {
        switch self {
        case .hover:
            language.value(
                turkish: "İşaretçi islo.'nun herhangi bir yerine geldiğinde açılır.",
                english: "Opens when the pointer reaches any part of islo.."
            )
        case .click:
            language.value(
                turkish: "Kendiliğinden açılmaz; kompakt görünüme tıklamanız gerekir.",
                english: "Never opens automatically; click the compact island to open it."
            )
        case .activationZone:
            language.value(
                turkish: "Yalnızca çentiğin üst-orta bölümüne geldiğinizde açılır.",
                english: "Opens only when the pointer reaches the top-center notch area."
            )
        }
    }
}

/// The theme colour used across the notch and islo.'s windows.
enum AccentTheme: String, CaseIterable, Identifiable {
    case blue
    case purple
    case pink
    case red
    case orange
    case yellow
    case green
    case mint
    case teal
    case graphite

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: Color(red: 0.27, green: 0.55, blue: 1.0)
        case .purple: Color(red: 0.68, green: 0.42, blue: 1.0)
        case .pink: Color(red: 1.0, green: 0.38, blue: 0.62)
        case .red: Color(red: 1.0, green: 0.33, blue: 0.31)
        case .orange: Color(red: 1.0, green: 0.58, blue: 0.2)
        case .yellow: Color(red: 1.0, green: 0.8, blue: 0.2)
        case .green: Color(red: 0.25, green: 0.82, blue: 0.42)
        case .mint: Color(red: 0.3, green: 0.88, blue: 0.75)
        case .teal: Color(red: 0.2, green: 0.74, blue: 0.86)
        case .graphite: Color(white: 0.66)
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .blue: language.value(turkish: "Mavi", english: "Blue")
        case .purple: language.value(turkish: "Mor", english: "Purple")
        case .pink: language.value(turkish: "Pembe", english: "Pink")
        case .red: language.value(turkish: "Kırmızı", english: "Red")
        case .orange: language.value(turkish: "Turuncu", english: "Orange")
        case .yellow: language.value(turkish: "Sarı", english: "Yellow")
        case .green: language.value(turkish: "Yeşil", english: "Green")
        case .mint: language.value(turkish: "Nane", english: "Mint")
        case .teal: language.value(turkish: "Turkuaz", english: "Teal")
        case .graphite: language.value(turkish: "Grafit", english: "Graphite")
        }
    }
}

/// What the notch shows when a notification arrives.
enum NotificationPreviewStyle: String, CaseIterable, Identifiable {
    case content
    case countOnly

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .content:
            language.value(turkish: "İçeriği göster", english: "Show content")
        case .countOnly:
            language.value(turkish: "Yalnızca \u{201C}1 yeni bildirim\u{201D}", english: "Only \u{201C}1 new notification\u{201D}")
        }
    }
}

/// How long notifications and shelf items stay before islo. clears them.
enum AutoClearInterval: String, CaseIterable, Identifiable {
    case never
    case hour
    case day
    case week

    var id: String { rawValue }

    var seconds: TimeInterval? {
        switch self {
        case .never: nil
        case .hour: 3_600
        case .day: 86_400
        case .week: 604_800
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .never: language.value(turkish: "Kapalı", english: "Off")
        case .hour: language.value(turkish: "1 saat", english: "1 hour")
        case .day: language.value(turkish: "1 gün", english: "1 day")
        case .week: language.value(turkish: "1 hafta", english: "1 week")
        }
    }
}

/// How strongly the theme colour tints the dark dashboard surface.
enum SurfaceTone: String, CaseIterable, Identifiable {
    case black
    case subtle
    case medium
    case vivid

    var id: String { rawValue }

    var tintOpacity: Double {
        switch self {
        case .black: 0
        case .subtle: 0.22
        case .medium: 0.4
        case .vivid: 0.62
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .black: language.value(turkish: "Saf siyah", english: "Pure black")
        case .subtle: language.value(turkish: "Hafif", english: "Subtle")
        case .medium: language.value(turkish: "Orta", english: "Medium")
        case .vivid: language.value(turkish: "Canlı", english: "Vivid")
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let theme = "appearance.theme"
        static let language = "general.language"
        static let notchIdleMode = "appearance.notchIdleMode"
        static let activationMode = "interaction.activationMode"
        static let expandOnHover = "interaction.expandOnHover"
        static let collapseDelay = "interaction.collapseDelay"
        static let showOnTrackChange = "interaction.showOnTrackChange"
        static let trackChangeDisplayDuration = "interaction.trackChangeDisplayDuration"
        static let hideInFullScreen = "interaction.hideInFullScreen"
        static let dashboardCommandEchoEnabled = "dashboard.commandEcho.enabled"
        static let dashboardFocusTimerEnabled = "dashboard.focusTimer.enabled"
        static let liveTimerInNotch = "dashboard.liveTimer.enabled"
        static let calendarEnabled = "dashboard.calendar.enabled"
        static let calendarAlertsEnabled = "dashboard.calendar.alerts"
        static let devicesHUDEnabled = "dashboard.devices.enabled"
        static let privacyIndicatorEnabled = "dashboard.privacy.enabled"
        static let lyricsEnabled = "dashboard.lyrics.enabled"
        static let weatherEnabled = "dashboard.weather.enabled"
        static let rainAlertsEnabled = "dashboard.weather.rainAlerts"
        static let hotKeyEnabled = "interaction.hotKey.enabled"
        static let screenshotPreviewEnabled = "dashboard.screenshots.enabled"
        static let hideSystemScreenshotThumbnail = "dashboard.screenshots.hideSystemThumbnail"
        static let downloadsEnabled = "dashboard.downloads.enabled"
        static let shortcutsEnabled = "dashboard.shortcuts.enabled"
        static let agentsEnabled = "dashboard.agents.enabled"
        static let agentsApproveInNotch = "dashboard.agents.approveInNotch"
        static let shortcutFavorites = "dashboard.shortcuts.favorites"
        static let focusStartShortcut = "focus.startShortcut"
        static let focusEndShortcut = "focus.endShortcut"
        static let toggleHotKey = "interaction.hotKey"
        static let weatherLocation = "dashboard.weather.location"
        static let dashboardKeepAwakeEnabled = "dashboard.keepAwake.enabled"
        static let dashboardFileShelfEnabled = "dashboard.fileShelf.enabled"
        static let dashboardClipboardEnabled = "dashboard.clipboard.enabled"
        static let dashboardNotificationsEnabled = "dashboard.notifications.enabled"
        static let hideSystemNotificationBanners = "dashboard.notifications.hideSystemBanners"
        static let notificationPreviewStyle = "dashboard.notifications.preview"
        static let notificationAutoClear = "dashboard.notifications.autoClear"
        static let mutedNotificationApps = "dashboard.notifications.mutedApps"
        static let vipNames = "dashboard.notifications.vip"
        static let knownNotificationApps = "dashboard.notifications.knownApps"
        static let shelfAutoClear = "dashboard.fileShelf.autoClear"
        static let clipboardAutoClear = "dashboard.clipboard.autoClear"
        /// No longer used: Home has one layout.
        static let legacyHomeWidgetStyle = "dashboard.homeWidgetStyle"
        static let legacySceneStyle = "appearance.notchSceneStyle"
        static let accentTheme = "appearance.accentTheme"
        static let surfaceTone = "appearance.surfaceTone"
        static let onboardingCompleted = "onboarding.completed"
        static let permissionReminderBuild = "permissions.reminderBuild"
    }

    private let defaults: UserDefaults

    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Key.language)
        }
    }

    @Published var notchIdleMode: NotchIdleMode {
        didSet {
            defaults.set(notchIdleMode.rawValue, forKey: Key.notchIdleMode)
        }
    }

    @Published var activationMode: NotchActivationMode {
        didSet {
            defaults.set(activationMode.rawValue, forKey: Key.activationMode)
        }
    }

    @Published var collapseDelay: Double {
        didSet {
            let clampedValue = min(max(collapseDelay, 0.15), 1.2)
            defaults.set(clampedValue, forKey: Key.collapseDelay)
        }
    }

    @Published var showOnTrackChange: Bool {
        didSet {
            defaults.set(showOnTrackChange, forKey: Key.showOnTrackChange)
        }
    }

    @Published var trackChangeDisplayDuration: Double {
        didSet {
            let clampedValue = min(max(trackChangeDisplayDuration, 2), 8)
            defaults.set(
                clampedValue,
                forKey: Key.trackChangeDisplayDuration
            )
        }
    }

    @Published var hideInFullScreen: Bool {
        didSet {
            defaults.set(hideInFullScreen, forKey: Key.hideInFullScreen)
        }
    }

    @Published var dashboardCommandEchoEnabled: Bool {
        didSet { defaults.set(dashboardCommandEchoEnabled, forKey: Key.dashboardCommandEchoEnabled) }
    }

    @Published var dashboardFocusTimerEnabled: Bool {
        didSet { defaults.set(dashboardFocusTimerEnabled, forKey: Key.dashboardFocusTimerEnabled) }
    }

    /// Reads the user's calendars for the next event.
    @Published var calendarEnabled: Bool {
        didSet { defaults.set(calendarEnabled, forKey: Key.calendarEnabled) }
    }

    /// Widens the notch shortly before a meeting starts.
    @Published var calendarAlertsEnabled: Bool {
        didSet { defaults.set(calendarAlertsEnabled, forKey: Key.calendarAlertsEnabled) }
    }

    /// Charger plugged in or out, low battery, and headphone batteries.
    @Published var devicesHUDEnabled: Bool {
        didSet { defaults.set(devicesHUDEnabled, forKey: Key.devicesHUDEnabled) }
    }

    /// A preview of each new screenshot under the notch.
    @Published var screenshotPreviewEnabled: Bool {
        didSet { defaults.set(screenshotPreviewEnabled, forKey: Key.screenshotPreviewEnabled) }
    }

    /// Turn off macOS's floating screenshot thumbnail so the file is saved
    /// at once and the notch preview opens right away.
    @Published var hideSystemScreenshotThumbnail: Bool {
        didSet { defaults.set(hideSystemScreenshotThumbnail, forKey: Key.hideSystemScreenshotThumbnail) }
    }

    /// Download progress in the closed notch and a "Downloaded" HUD.
    @Published var downloadsEnabled: Bool {
        didSet { defaults.set(downloadsEnabled, forKey: Key.downloadsEnabled) }
    }

    /// The Shortcuts tab.
    @Published var shortcutsEnabled: Bool {
        didSet { defaults.set(shortcutsEnabled, forKey: Key.shortcutsEnabled) }
    }

    /// Coding agents (Claude Code, Codex) reporting to the notch.
    @Published var agentsEnabled: Bool {
        didSet { defaults.set(agentsEnabled, forKey: Key.agentsEnabled) }
    }

    /// Permission requests can be answered in the notch, not only shown.
    @Published var agentsApproveInNotch: Bool {
        didSet { defaults.set(agentsApproveInNotch, forKey: Key.agentsApproveInNotch) }
    }

    /// Shortcuts pinned to the tab, in order.
    @Published var shortcutFavorites: [String] {
        didSet { defaults.set(shortcutFavorites, forKey: Key.shortcutFavorites) }
    }

    /// Shortcuts run when a Pomodoro focus phase starts / ends.
    @Published var focusStartShortcut: String? {
        didSet { defaults.set(focusStartShortcut, forKey: Key.focusStartShortcut) }
    }

    @Published var focusEndShortcut: String? {
        didSet { defaults.set(focusEndShortcut, forKey: Key.focusEndShortcut) }
    }

    /// A system-wide shortcut that opens and closes the notch.
    @Published var hotKeyEnabled: Bool {
        didSet { defaults.set(hotKeyEnabled, forKey: Key.hotKeyEnabled) }
    }

    @Published var toggleHotKey: HotKey {
        didSet {
            if let data = try? JSONEncoder().encode(toggleHotKey) {
                defaults.set(data, forKey: Key.toggleHotKey)
            }
        }
    }

    /// Set when another app already owns the chosen shortcut.
    @Published var isHotKeyTaken = false

    /// Current weather on Home, from Open-Meteo.
    /// The notch says when rain starts within the hour.
    @Published var rainAlertsEnabled: Bool {
        didSet { defaults.set(rainAlertsEnabled, forKey: Key.rainAlertsEnabled) }
    }

    @Published var weatherEnabled: Bool {
        didSet { defaults.set(weatherEnabled, forKey: Key.weatherEnabled) }
    }

    /// The city for the weather; nil follows the Mac's time zone.
    @Published var weatherLocation: WeatherLocation? {
        didSet {
            if let weatherLocation, let data = try? JSONEncoder().encode(weatherLocation) {
                defaults.set(data, forKey: Key.weatherLocation)
            } else {
                defaults.removeObject(forKey: Key.weatherLocation)
            }
        }
    }

    /// Synced lyrics in the song card, fetched from LRCLIB.
    @Published var lyricsEnabled: Bool {
        didSet { defaults.set(lyricsEnabled, forKey: Key.lyricsEnabled) }
    }

    /// A dot and the app's name while the camera or microphone is in use.
    @Published var privacyIndicatorEnabled: Bool {
        didSet { defaults.set(privacyIndicatorEnabled, forKey: Key.privacyIndicatorEnabled) }
    }

    /// Shows a running countdown in the closed notch's wings.
    @Published var liveTimerInNotch: Bool {
        didSet { defaults.set(liveTimerInNotch, forKey: Key.liveTimerInNotch) }
    }

    @Published var dashboardKeepAwakeEnabled: Bool {
        didSet { defaults.set(dashboardKeepAwakeEnabled, forKey: Key.dashboardKeepAwakeEnabled) }
    }

    @Published var dashboardFileShelfEnabled: Bool {
        didSet { defaults.set(dashboardFileShelfEnabled, forKey: Key.dashboardFileShelfEnabled) }
    }

    /// Off: islo. doesn't read the pasteboard's contents at all.
    @Published var dashboardClipboardEnabled: Bool {
        didSet { defaults.set(dashboardClipboardEnabled, forKey: Key.dashboardClipboardEnabled) }
    }

    @Published var dashboardNotificationsEnabled: Bool {
        didSet { defaults.set(dashboardNotificationsEnabled, forKey: Key.dashboardNotificationsEnabled) }
    }

    @Published var notificationPreviewStyle: NotificationPreviewStyle {
        didSet { defaults.set(notificationPreviewStyle.rawValue, forKey: Key.notificationPreviewStyle) }
    }

    /// Apps whose notifications stay with macOS instead of the notch.
    @Published var mutedNotificationApps: [String] {
        didSet { defaults.set(mutedNotificationApps, forKey: Key.mutedNotificationApps) }
    }

    /// People whose messages stand out in the notch and stay longer.
    @Published var vipNames: [String] {
        didSet { defaults.set(vipNames, forKey: Key.vipNames) }
    }

    /// Apps that have sent a notification, newest first, for Settings.
    @Published private(set) var knownNotificationApps: [String]

    /// App names as macOS shows them, without direction marks, each once.
    private static func cleanedNames(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        return names.map(\.withoutDirectionMarks).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    func noteNotificationApp(_ name: String) {
        guard !knownNotificationApps.contains(name) else { return }
        knownNotificationApps = Array(([name] + knownNotificationApps).prefix(40))
        defaults.set(knownNotificationApps, forKey: Key.knownNotificationApps)
    }

    /// A message from someone on the VIP list: their name in the title (the
    /// sender for message apps) or subtitle, as whole words.
    func isVIP(_ item: CapturedNotification) -> Bool {
        let names = vipNames.map(Self.searchable).filter { !$0.isEmpty }
        guard !names.isEmpty else { return false }
        let fields = [item.title, item.subtitle].map { " " + Self.searchable($0) + " " }
        return names.contains { name in fields.contains { $0.contains(" " + name + " ") } }
    }

    private static func searchable(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
        let spaced = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }.joined()
        return spaced.split(separator: " ").joined(separator: " ")
    }

    /// Notifications older than this leave the notch's list.
    @Published var notificationAutoClear: AutoClearInterval {
        didSet { defaults.set(notificationAutoClear.rawValue, forKey: Key.notificationAutoClear) }
    }

    /// Files leave the shelf this long after they were added.
    @Published var shelfAutoClear: AutoClearInterval {
        didSet { defaults.set(shelfAutoClear.rawValue, forKey: Key.shelfAutoClear) }
    }

    /// Copied text leaves the clipboard history after this long.
    @Published var clipboardAutoClear: AutoClearInterval {
        didSet { defaults.set(clipboardAutoClear.rawValue, forKey: Key.clipboardAutoClear) }
    }

    /// Keep macOS's own banner off screen while the notch shows the
    /// notification; it still goes to Notification Center.
    @Published var hideSystemNotificationBanners: Bool {
        didSet { defaults.set(hideSystemNotificationBanners, forKey: Key.hideSystemNotificationBanners) }
    }

    @Published var accentTheme: AccentTheme {
        didSet { defaults.set(accentTheme.rawValue, forKey: Key.accentTheme) }
    }

    @Published var surfaceTone: SurfaceTone {
        didSet { defaults.set(surfaceTone.rawValue, forKey: Key.surfaceTone) }
    }

    @Published private(set) var onboardingCompleted: Bool
    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var launchAtLoginRequiresApproval: Bool
    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var isAccessibilityTrusted = AXIsProcessTrusted()
    @Published private(set) var automationStates: [AutomationTarget: PermissionState] = [:]
    /// Only folders whose feature is on and that macOS guards.
    @Published private(set) var folderStates: [ProtectedFolder: PermissionState] = [:]
    private var isCheckingAutomation = false
    private var checkingFolders: Set<ProtectedFolder> = []

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // islo.'s windows now always use its own dark look; the old
        // System/Light/Dark/Liquid Glass choice is gone.
        defaults.removeObject(forKey: Key.theme)

        // Until one is picked: Turkish on a Turkish Mac, English elsewhere.
        language = AppLanguage(
            rawValue: defaults.string(forKey: Key.language) ?? ""
        ) ?? (Locale.preferredLanguages.first?.hasPrefix("tr") == true ? .turkish : .english)

        notchIdleMode = NotchIdleMode(
            rawValue: defaults.string(forKey: Key.notchIdleMode) ?? ""
        ) ?? .visibleIsland

        if let savedMode = NotchActivationMode(
            rawValue: defaults.string(forKey: Key.activationMode) ?? ""
        ) {
            activationMode = savedMode
        } else {
            // Preserve the behavior selected in islo 1.5.
            let legacyHoverEnabled = defaults.object(
                forKey: Key.expandOnHover
            ) == nil || defaults.bool(forKey: Key.expandOnHover)
            activationMode = legacyHoverEnabled ? .hover : .click
        }

        if defaults.object(forKey: Key.collapseDelay) == nil {
            collapseDelay = 0.28
        } else {
            collapseDelay = min(
                max(defaults.double(forKey: Key.collapseDelay), 0.15),
                1.2
            )
        }


        if defaults.object(forKey: Key.showOnTrackChange) == nil {
            showOnTrackChange = true
        } else {
            showOnTrackChange = defaults.bool(forKey: Key.showOnTrackChange)
        }

        if defaults.object(forKey: Key.trackChangeDisplayDuration) == nil {
            trackChangeDisplayDuration = 3.5
        } else {
            trackChangeDisplayDuration = min(
                max(
                    defaults.double(forKey: Key.trackChangeDisplayDuration),
                    2
                ),
                8
            )
        }

        hideInFullScreen = defaults.bool(forKey: Key.hideInFullScreen)

        dashboardCommandEchoEnabled = Self.bool(
            forKey: Key.dashboardCommandEchoEnabled,
            defaults: defaults,
            fallback: true
        )
        dashboardFocusTimerEnabled = Self.bool(
            forKey: Key.dashboardFocusTimerEnabled,
            defaults: defaults,
            fallback: true
        )
        liveTimerInNotch = Self.bool(
            forKey: Key.liveTimerInNotch,
            defaults: defaults,
            fallback: true
        )
        calendarEnabled = Self.bool(forKey: Key.calendarEnabled, defaults: defaults, fallback: true)
        calendarAlertsEnabled = Self.bool(forKey: Key.calendarAlertsEnabled, defaults: defaults, fallback: true)
        devicesHUDEnabled = Self.bool(forKey: Key.devicesHUDEnabled, defaults: defaults, fallback: true)
        privacyIndicatorEnabled = Self.bool(forKey: Key.privacyIndicatorEnabled, defaults: defaults, fallback: true)
        lyricsEnabled = Self.bool(forKey: Key.lyricsEnabled, defaults: defaults, fallback: true)
        weatherEnabled = Self.bool(forKey: Key.weatherEnabled, defaults: defaults, fallback: true)
        rainAlertsEnabled = Self.bool(forKey: Key.rainAlertsEnabled, defaults: defaults, fallback: true)
        hotKeyEnabled = Self.bool(forKey: Key.hotKeyEnabled, defaults: defaults, fallback: true)
        screenshotPreviewEnabled = Self.bool(forKey: Key.screenshotPreviewEnabled, defaults: defaults, fallback: true)
        hideSystemScreenshotThumbnail = Self.bool(forKey: Key.hideSystemScreenshotThumbnail, defaults: defaults, fallback: true)
        downloadsEnabled = Self.bool(forKey: Key.downloadsEnabled, defaults: defaults, fallback: true)
        // Off until asked for; whoever already picked shortcuts keeps the tab.
        shortcutsEnabled = Self.bool(
            forKey: Key.shortcutsEnabled,
            defaults: defaults,
            fallback: !(defaults.stringArray(forKey: Key.shortcutFavorites) ?? []).isEmpty
        )
        agentsEnabled = Self.bool(forKey: Key.agentsEnabled, defaults: defaults, fallback: true)
        agentsApproveInNotch = Self.bool(forKey: Key.agentsApproveInNotch, defaults: defaults, fallback: true)
        shortcutFavorites = defaults.stringArray(forKey: Key.shortcutFavorites) ?? []
        focusStartShortcut = defaults.string(forKey: Key.focusStartShortcut)
        focusEndShortcut = defaults.string(forKey: Key.focusEndShortcut)
        toggleHotKey = defaults.data(forKey: Key.toggleHotKey)
            .flatMap { try? JSONDecoder().decode(HotKey.self, from: $0) } ?? .defaultToggle
        weatherLocation = defaults.data(forKey: Key.weatherLocation)
            .flatMap { try? JSONDecoder().decode(WeatherLocation.self, from: $0) }
        dashboardKeepAwakeEnabled = Self.bool(
            forKey: Key.dashboardKeepAwakeEnabled,
            defaults: defaults,
            fallback: true
        )
        dashboardFileShelfEnabled = Self.bool(
            forKey: Key.dashboardFileShelfEnabled,
            defaults: defaults,
            fallback: true
        )
        dashboardClipboardEnabled = Self.bool(
            forKey: Key.dashboardClipboardEnabled,
            defaults: defaults,
            fallback: true
        )
        dashboardNotificationsEnabled = Self.bool(
            forKey: Key.dashboardNotificationsEnabled,
            defaults: defaults,
            fallback: true
        )
        notificationPreviewStyle = NotificationPreviewStyle(
            rawValue: defaults.string(forKey: Key.notificationPreviewStyle) ?? ""
        ) ?? .content
        mutedNotificationApps = Self.cleanedNames(defaults.stringArray(forKey: Key.mutedNotificationApps) ?? [])
        vipNames = defaults.stringArray(forKey: Key.vipNames) ?? []
        knownNotificationApps = Self.cleanedNames(defaults.stringArray(forKey: Key.knownNotificationApps) ?? [])
        notificationAutoClear = AutoClearInterval(
            rawValue: defaults.string(forKey: Key.notificationAutoClear) ?? ""
        ) ?? .never
        shelfAutoClear = AutoClearInterval(
            rawValue: defaults.string(forKey: Key.shelfAutoClear) ?? ""
        ) ?? .never
        clipboardAutoClear = AutoClearInterval(
            rawValue: defaults.string(forKey: Key.clipboardAutoClear) ?? ""
        ) ?? .never
        hideSystemNotificationBanners = Self.bool(
            forKey: Key.hideSystemNotificationBanners,
            defaults: defaults,
            fallback: true
        )
        defaults.removeObject(forKey: Key.legacyHomeWidgetStyle)
        // The colour + tone theme replaces the old fixed scenes; carry an
        // existing scene over to its closest colour and tone.
        let legacyScene: (AccentTheme, SurfaceTone)? = switch defaults.string(
            forKey: Key.legacySceneStyle
        ) {
        case "graphite": (.graphite, .subtle)
        case "ember": (.orange, .medium)
        case "aurora": (.teal, .medium)
        case "album": (.pink, .medium)
        default: nil
        }
        accentTheme = AccentTheme(
            rawValue: defaults.string(forKey: Key.accentTheme) ?? ""
        ) ?? legacyScene?.0 ?? .blue
        surfaceTone = SurfaceTone(
            rawValue: defaults.string(forKey: Key.surfaceTone) ?? ""
        ) ?? legacyScene?.1 ?? .subtle

        onboardingCompleted = defaults.bool(
            forKey: Key.onboardingCompleted
        )

        let loginItemStatus = SMAppService.mainApp.status
        launchAtLogin = Self.isLoginItemRequested(loginItemStatus)
        launchAtLoginRequiresApproval = loginItemStatus == .requiresApproval
        launchAtLoginError = nil
    }

    func completeOnboarding() {
        onboardingCompleted = true
        defaults.set(true, forKey: Key.onboardingCompleted)
    }

    func resetInteractionDefaults() {
        activationMode = .hover
        collapseDelay = 0.28
        showOnTrackChange = true
        trackChangeDisplayDuration = 3.5
        hideInFullScreen = false
    }

    func resetDashboardFeatureDefaults() {
        dashboardCommandEchoEnabled = true
        dashboardFocusTimerEnabled = true
        liveTimerInNotch = true
        calendarEnabled = true
        calendarAlertsEnabled = true
        devicesHUDEnabled = true
        privacyIndicatorEnabled = true
        lyricsEnabled = true
        weatherEnabled = true
        screenshotPreviewEnabled = true
        hideSystemScreenshotThumbnail = true
        downloadsEnabled = true
        shortcutsEnabled = false
        agentsEnabled = true
        agentsApproveInNotch = true
        dashboardKeepAwakeEnabled = true
        dashboardFileShelfEnabled = true
        dashboardClipboardEnabled = true
        dashboardNotificationsEnabled = true
        notificationPreviewStyle = .content
        notificationAutoClear = .never
        shelfAutoClear = .never
        clipboardAutoClear = .never
        mutedNotificationApps = []
        vipNames = []
        rainAlertsEnabled = true
        hideSystemNotificationBanners = true
    }

    private static func bool(
        forKey key: String,
        defaults: UserDefaults,
        fallback: Bool
    ) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp

        do {
            if enabled {
                switch service.status {
                case .enabled, .requiresApproval:
                    break
                case .notRegistered, .notFound:
                    try service.register()
                @unknown default:
                    try service.register()
                }
            } else if service.status != .notRegistered {
                try service.unregister()
            }

            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }

        refreshLaunchAtLoginState()
    }

    func refreshLaunchAtLoginState() {
        let status = SMAppService.mainApp.status
        launchAtLogin = Self.isLoginItemRequested(status)
        launchAtLoginRequiresApproval = status == .requiresApproval
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Permissions that are missing and break a feature (not ones macOS
    /// simply hasn't asked about yet).
    var missingPermissionCount: Int {
        (isAccessibilityTrusted || !(dashboardCommandEchoEnabled || dashboardNotificationsEnabled) ? 0 : 1)
            + automationStates.values.filter { $0 == .missing }.count
            + folderStates.values.filter { $0 == .missing }.count
            + (calendarEnabled && CalendarManager.shared.authorization == .missing ? 1 : 0)
    }

    /// macOS doesn't notify apps when permissions change, so Settings and
    /// app activation re-read them.
    func refreshPermissionState() {
        let trusted = AXIsProcessTrusted()
        if trusted != isAccessibilityTrusted {
            isAccessibilityTrusted = trusted
        }
        CalendarManager.shared.refreshAuthorization()
        refreshAutomationStates()
        refreshFolderStates()
    }

    func folderURL(_ folder: ProtectedFolder) -> URL {
        switch folder {
        case .screenshots:
            ScreenshotMonitor.saveLocation
        case .downloads:
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        }
    }

    func isFolderFeatureEnabled(_ folder: ProtectedFolder) -> Bool {
        switch folder {
        case .screenshots: screenshotPreviewEnabled
        case .downloads: downloadsEnabled
        }
    }

    /// Asks macOS for a folder again. Once access was turned off it never
    /// asks by itself, so islo.'s own entry is cleared first.
    func requestFolderAccess(_ folder: ProtectedFolder) {
        let url = folderURL(folder)
        guard let service = ProtectedFolder.privacyService(for: url) else { return }
        let wasMissing = folderStates[folder] == .missing
        DispatchQueue.global(qos: .userInitiated).async {
            if wasMissing { Self.resetPermission(service: service) }
            // Touching the folder is what makes macOS show its prompt.
            let state = Self.folderState(at: url)
            DispatchQueue.main.async { [weak self] in
                self?.refreshPermissionState()
                if state == .missing { self?.openPrivacySettings("Privacy_FilesAndFolders") }
            }
        }
    }

    private func refreshFolderStates() {
        for folder in ProtectedFolder.allCases {
            let url = folderURL(folder)
            guard isFolderFeatureEnabled(folder),
                  ProtectedFolder.privacyService(for: url) != nil else {
                if folderStates[folder] != nil { folderStates[folder] = nil }
                continue
            }
            // Each folder on its own: a check waiting on macOS's prompt for
            // one folder mustn't hold up the other.
            guard !checkingFolders.contains(folder) else { continue }
            checkingFolders.insert(folder)
            DispatchQueue.global(qos: .utility).async {
                let state = Self.folderState(at: url)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    checkingFolders.remove(folder)
                    guard isFolderFeatureEnabled(folder) else { return }
                    if folderStates[folder] != state { folderStates[folder] = state }
                }
            }
        }
    }

    /// Opening a guarded folder fails with EPERM while access is off.
    nonisolated private static func folderState(at url: URL) -> PermissionState {
        guard let directory = opendir(url.path) else {
            return errno == EPERM || errno == EACCES ? .missing : .granted
        }
        closedir(directory)
        return .granted
    }

    func requestAccessibilityPermission() {
        let wasTrusted = AXIsProcessTrusted()
        DispatchQueue.global(qos: .userInitiated).async {
            // After an update macOS can keep an old islo. entry that still
            // looks switched on but no longer matches this copy, and then it
            // never asks again. Clearing islo.'s own entry lets it ask afresh.
            if !wasTrusted {
                Self.resetPermission(service: "Accessibility")
            }
            DispatchQueue.main.async { [weak self] in
                let options = [
                    kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
                ] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
                self?.refreshPermissionState()
            }
            // Open the list too, in case macOS shows no prompt.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard self?.isAccessibilityTrusted == false else { return }
                self?.openAccessibilitySettings()
            }
        }
    }

    func requestAutomationPermission(for target: AutomationTarget) {
        let previous = automationStates[target]
        // Resetting clears every app islo. may control; when another one is
        // already allowed, switch this one on in System Settings instead.
        let othersGranted = automationStates.contains { $0.key != target && $0.value == .granted }
        if previous == .missing, othersGranted {
            openAutomationSettings()
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            // macOS never asks again once access was turned off; resetting
            // islo.'s Automation entries brings the prompt back.
            if previous == .missing {
                Self.resetPermission(service: "AppleEvents")
            }
            // A player that leaves macOS's query unanswered is asked with
            // a real Apple event, which brings up the same prompt.
            Self.unresponsiveLock.lock()
            let isUnresponsive = Self.unresponsiveTargets.contains(target)
            Self.unresponsiveLock.unlock()
            let state = isUnresponsive
                ? Self.scriptedAutomationState(for: target, timeout: 120)
                : Self.automationState(for: target, askUser: true)
            DispatchQueue.main.async { [weak self] in
                self?.refreshPermissionState()
                if state == .missing { self?.openAutomationSettings() }
            }
        }
    }

    func openAccessibilitySettings() {
        openPrivacySettings("Privacy_Accessibility")
    }

    func openAutomationSettings() {
        openPrivacySettings("Privacy_Automation")
    }

    /// Opens Permissions once per version when an update left islo. without
    /// Accessibility; nothing else would tell the user why features stopped.
    func takePermissionReminder() -> Bool {
        guard onboardingCompleted,
              !AXIsProcessTrusted(),
              dashboardCommandEchoEnabled || dashboardNotificationsEnabled else {
            return false
        }
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        guard defaults.string(forKey: Key.permissionReminderBuild) != build else {
            return false
        }
        defaults.set(build, forKey: Key.permissionReminderBuild)
        return true
    }

    private func openPrivacySettings(_ anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func refreshAutomationStates() {
        guard !isCheckingAutomation else { return }
        isCheckingAutomation = true
        DispatchQueue.global(qos: .utility).async {
            var states: [AutomationTarget: PermissionState] = [:]
            for target in AutomationTarget.allCases {
                states[target] = Self.passiveAutomationState(for: target)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                isCheckingAutomation = false
                if states != automationStates { automationStates = states }
            }
        }
    }

    /// Targets whose permission query never came back (see below).
    nonisolated(unsafe) private static var unresponsiveTargets = Set<AutomationTarget>()
    nonisolated private static let unresponsiveLock = NSLock()

    /// The state without asking the user. macOS's own query never returns
    /// for some players (Spotify leaves it unanswered), which used to stall
    /// every later check; it gets a moment, then a plain Apple event to the
    /// player answers instead.
    nonisolated private static func passiveAutomationState(for target: AutomationTarget) -> PermissionState {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.rawValue) != nil else {
            return .appNotInstalled
        }
        // macOS only answers for an app that is running.
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: target.rawValue).isEmpty else {
            return .appClosed
        }

        unresponsiveLock.lock()
        let isKnownUnresponsive = unresponsiveTargets.contains(target)
        unresponsiveLock.unlock()

        if !isKnownUnresponsive {
            let finished = DispatchSemaphore(value: 0)
            let box = PermissionStateBox()
            Thread.detachNewThread {
                box.set(automationState(for: target, askUser: false))
                finished.signal()
            }
            if finished.wait(timeout: .now() + 1.5) == .success, let state = box.get() {
                return state
            }
            unresponsiveLock.lock()
            unresponsiveTargets.insert(target)
            unresponsiveLock.unlock()
        }
        return scriptedAutomationState(for: target)
    }

    /// Sends the player a harmless Apple event and reads the outcome.
    nonisolated private static func scriptedAutomationState(
        for target: AutomationTarget,
        timeout: Int = 3
    ) -> PermissionState {
        let source = """
        with timeout of \(timeout) seconds
            tell application id "\(target.rawValue)" to get name
        end timeout
        """
        guard let script = NSAppleScript(source: source) else { return .appClosed }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        guard let errorInfo else { return .granted }
        switch errorInfo[NSAppleScript.errorNumber] as? Int {
        case -1743: return .missing
        case -1744: return .notAsked
        default: return .appClosed
        }
    }

    /// Blocks while macOS shows its prompt, so never call it on the main thread.
    nonisolated private static func automationState(
        for target: AutomationTarget,
        askUser: Bool
    ) -> PermissionState {
        guard NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: target.rawValue
        ) != nil else {
            return .appNotInstalled
        }

        var address = AEAddressDesc()
        let status: OSStatus = target.rawValue.withCString { bundleID in
            guard AECreateDesc(
                DescType(typeApplicationBundleID),
                bundleID,
                strlen(bundleID),
                &address
            ) == noErr else {
                return OSStatus(procNotFound)
            }
            defer { AEDisposeDesc(&address) }
            return AEDeterminePermissionToAutomateTarget(
                &address,
                AEEventClass(typeWildCard),
                AEEventID(typeWildCard),
                askUser
            )
        }

        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .missing
        case OSStatus(errAEEventWouldRequireUserConsent): return .notAsked
        default: return .appClosed  // procNotFound: macOS only answers while it runs
        }
    }

    /// Removes islo.'s own entry for a privacy service.
    nonisolated private static func resetPermission(service: String) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return
        }
    }

    private static func isLoginItemRequested(
        _ status: SMAppService.Status
    ) -> Bool {
        status == .enabled || status == .requiresApproval
    }
}

/// Carries a result out of a helper thread that may never finish.
private final class PermissionStateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: PermissionState?

    func set(_ newValue: PermissionState) {
        lock.lock(); value = newValue; lock.unlock()
    }

    func get() -> PermissionState? {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}
