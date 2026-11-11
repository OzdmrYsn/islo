import Carbon.HIToolbox
import Combine
import SwiftUI

/// Pages other parts of islo. can open Settings on. `features` opens the
/// first feature's page.
enum SettingsDestination: String, CaseIterable, Identifiable {
    case general, appearance, features, permissions, about
    var id: String { rawValue }
}

/// Lets the menu bar and launch reminders open Settings on a given page.
final class SettingsRouter: ObservableObject {
    @Published var requestedDestination: SettingsDestination?
    /// A feature's page to open, by its identifier (e.g. "timer").
    @Published var requestedFeature: String?
    @Published var isWindowVisible = false
}

// MARK: - islo. look

/// The look islo.'s dark windows share with the notch and the website:
/// near black, white text at a few strengths, soft glass cards.
enum IsloStyle {
    static let background = Color(red: 0.035, green: 0.035, blue: 0.045)
    static let text = Color(red: 0.96, green: 0.96, blue: 0.97)
    static let muted = Color.white.opacity(0.58)
    static let faint = Color.white.opacity(0.36)
    static let line = Color.white.opacity(0.08)
    static let cardRadius: CGFloat = 20

    static var cardFill: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.075), Color.white.opacity(0.03)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// The colours shared controls use: the dark islo. look (welcome guide)
/// or the light one (Settings).
struct IsloPalette {
    let text: Color
    let muted: Color
    let faint: Color
    let line: Color
    /// Behind quiet controls: chips, buttons, fields.
    let fill: Color
    let fillPressed: Color
    let card: Color
    let page: Color
    let sidebar: Color
    let good: Color
    let warning: Color

    static let dark = IsloPalette(
        text: IsloStyle.text,
        muted: IsloStyle.muted,
        faint: IsloStyle.faint,
        line: IsloStyle.line,
        fill: Color.white.opacity(0.08),
        fillPressed: Color.white.opacity(0.16),
        card: Color.white.opacity(0.05),
        page: IsloStyle.background,
        sidebar: Color.black.opacity(0.32),
        good: .green,
        warning: .orange
    )

    static let light = IsloPalette(
        text: Color(hex: 0x1D1D1F),
        muted: Color(hex: 0x6E6E73),
        faint: Color(hex: 0xA1A1A6),
        line: Color.black.opacity(0.075),
        fill: Color.black.opacity(0.05),
        fillPressed: Color.black.opacity(0.1),
        card: .white,
        page: Color(hex: 0xF5F5F7),
        sidebar: Color(hex: 0xEBEBEE),
        good: Color(hex: 0x248A3D),
        warning: Color(hex: 0xC4560A)
    )

    static func of(_ scheme: ColorScheme) -> IsloPalette { scheme == .dark ? .dark : .light }
}

/// Black with the theme colour glowing in at the chosen tone, like the
/// open notch.
struct IsloWindowBackground: View {
    let accent: Color
    let tone: SurfaceTone

    var body: some View {
        ZStack {
            IsloStyle.background
            RadialGradient(
                colors: [accent.opacity(0.04 + tone.tintOpacity * 0.34), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 640
            )
            RadialGradient(
                colors: [accent.opacity(tone.tintOpacity * 0.12), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.25), value: tone)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Two-colour fills for icon tiles.
enum Tint {
    static let red = [Color(hex: 0xFF5A50), Color(hex: 0xC9221A)]
    static let indigo = [Color(hex: 0x8A87FF), Color(hex: 0x4B48D6)]
    static let pink = [Color(hex: 0xFF5C93), Color(hex: 0xD3245F)]
    static let green = [Color(hex: 0x3ED667), Color(hex: 0x1E9E45)]
    static let cyan = [Color(hex: 0x6AD6FF), Color(hex: 0x1597D6)]
    static let purple = [Color(hex: 0xC56BF5), Color(hex: 0x8A2BD6)]
    static let mint = [Color(hex: 0x36DDB0), Color(hex: 0x0E9F7A)]
    static let orange = [Color(hex: 0xFFA826), Color(hex: 0xE86A00)]
    static let blue = [Color(hex: 0x3D9BFF), Color(hex: 0x0059D6)]
    static let shortcuts = [Color(hex: 0xFF5E9C), Color(hex: 0x7B61FF)]
    static let coffee = [Color(hex: 0xB8946A), Color(hex: 0x7A5C3A)]
    static let sky = [Color(hex: 0x5BC8F5), Color(hex: 0x2A6FFF)]
    static let magenta = [Color(hex: 0xFF72DA), Color(hex: 0xB233C2)]
    static let gray = [Color(hex: 0x9A9AA2), Color(hex: 0x5A5A62)]
    static let teal = [Color(hex: 0x4FD1D9), Color(hex: 0x16939E)]
    static let sunset = [Color(hex: 0xFF6B9A), Color(hex: 0xFF9F45)]
}

/// A rounded, coloured icon tile, like the notch's Shortcuts tiles.
struct IconTile: View {
    let symbol: String
    let colors: [Color]
    var size: CGFloat = 30
    var isOn = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        let offColors = scheme == .dark
            ? [Color.white.opacity(0.15), Color.white.opacity(0.07)]
            : [Color(hex: 0xCACACF), Color(hex: 0xADADB3)]
        shape
            .fill(LinearGradient(
                colors: isOn ? colors : offColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(isOn || scheme == .light ? 1 : 0.5))
            )
            .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
            .frame(width: size, height: size)
            .shadow(
                color: (isOn ? colors.last ?? .clear : .clear).opacity(scheme == .dark ? 0.35 : 0.22),
                radius: size * (scheme == .dark ? 0.22 : 0.12),
                y: size * 0.06
            )
            .accessibilityHidden(true)
    }
}

/// Capsule buttons: filled with the theme colour, or a quiet one.
struct IsloButtonStyle: ButtonStyle {
    var prominent = false
    var accent: Color
    /// Text on the theme colour; dark for the light colours.
    var onAccent: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, prominent: prominent, accent: accent, onAccent: onAccent)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let prominent: Bool
        let accent: Color
        let onAccent: Color
        @Environment(\.colorScheme) private var scheme
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let palette = IsloPalette.of(scheme)
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(prominent ? onAccent : palette.text)
                .padding(.horizontal, 13)
                .frame(height: 28)
                .background(
                    Capsule().fill(prominent ? accent : (configuration.isPressed ? palette.fillPressed : palette.fill))
                )
                .overlay(Capsule().strokeBorder(prominent ? Color.white.opacity(0.18) : palette.line, lineWidth: 0.5))
                .opacity(configuration.isPressed && prominent ? 0.85 : isEnabled ? 1 : 0.5)
                .contentShape(Capsule())
        }
    }
}

/// A row of capsule choices, the notch's tab-chip look as a picker.
struct ChipPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    let accent: Color
    var fillsWidth = false
    var onAccent: Color = .white
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = IsloPalette.of(scheme)
        HStack(spacing: 3) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? onAccent : palette.text.opacity(0.72))
                        .padding(.horizontal, 12)
                        .frame(maxWidth: fillsWidth ? .infinity : nil)
                        .frame(height: 26)
                        .background {
                            if isSelected {
                                Capsule().fill(accent)
                                    .shadow(color: accent.opacity(scheme == .dark ? 0.4 : 0.25), radius: 6, y: 2)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(palette.fill))
        .overlay(Capsule().strokeBorder(palette.line, lineWidth: 0.5))
        .fixedSize(horizontal: !fillsWidth, vertical: true)
    }
}

// MARK: - Features

/// Everything islo. can do that has an on/off switch.
private enum Feature: String, CaseIterable, Identifiable {
    case notifications, commandEcho, calendar, devices, privacy, screenshots, downloads
    case timer, shelf, clipboard, shortcuts, keepAwake, weather, lyrics

    var id: String { rawValue }

    /// Things the notch tells you about on its own.
    static let alerts: [Feature] = [.notifications, .commandEcho, .calendar, .devices, .privacy, .screenshots, .downloads]
    /// Tools that live in the open notch.
    static let panel: [Feature] = [.timer, .shelf, .clipboard, .shortcuts, .keepAwake, .weather, .lyrics]

    var symbol: String {
        switch self {
        case .notifications: "bell.badge.fill"
        case .commandEcho: "speaker.wave.2.fill"
        case .calendar: "calendar"
        case .devices: "battery.100percent.bolt"
        case .privacy: "video.fill"
        case .screenshots: "camera.viewfinder"
        case .downloads: "arrow.down.circle.fill"
        case .timer: "timer"
        case .shelf: "tray.full.fill"
        case .clipboard: "list.clipboard.fill"
        case .shortcuts: "bolt.fill"
        case .keepAwake: "cup.and.saucer.fill"
        case .weather: "cloud.sun.fill"
        case .lyrics: "quote.bubble.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .notifications: Tint.red
        case .commandEcho: Tint.indigo
        case .calendar: Tint.pink
        case .devices: Tint.green
        case .privacy: Tint.cyan
        case .screenshots: Tint.purple
        case .downloads: Tint.mint
        case .timer: Tint.orange
        case .shelf: Tint.blue
        case .clipboard: Tint.teal
        case .shortcuts: Tint.shortcuts
        case .keepAwake: Tint.coffee
        case .weather: Tint.sky
        case .lyrics: Tint.magenta
        }
    }
}

/// The macOS permission a feature depends on.
private enum FeaturePermission {
    case accessibility
    case calendar
    case folder(ProtectedFolder)
}

/// The tabs under the stage.
private enum SettingsTab: CaseIterable {
    case general, appearance, alerts, tools, permissions, about
}

/// A page of the Settings window.
private enum SettingsPage: Hashable {
    case general, appearance, permissions, about
    case feature(Feature)

    init(_ destination: SettingsDestination) {
        switch destination {
        case .general: self = .general
        case .appearance: self = .appearance
        case .features: self = .feature(.notifications)
        case .permissions: self = .permissions
        case .about: self = .about
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var updateManager = UpdateManager.shared
    @ObservedObject private var calendarManager = CalendarManager.shared
    @ObservedObject private var shortcutsManager = ShortcutsManager.shared
    var router: SettingsRouter?
    var onShowOnboarding: () -> Void = {}
    @State private var selection: SettingsPage = .general
    /// The feature each list last showed, so its tab reopens there.
    @State private var lastAlert: Feature = .notifications
    @State private var lastTool: Feature = .timer
    /// Pointing at a feature previews it on the stage.
    @State private var hoveredFeature: Feature?
    @State private var weatherQuery = ""
    @State private var vipDraft = ""
    @State private var weatherResults: [WeatherLocation] = []
    @State private var isSearchingWeather = false
    @State private var showsNotificationHelp = false
    @State private var confirmsReset = false

    /// Settings is always light; the notch and the welcome guide stay dark.
    private let p = IsloPalette.light

    var body: some View {
        VStack(spacing: 0) {
            SettingsStage(
                demo: stageDemo,
                caption: stageCaption,
                accent: accent,
                tone: settings.surfaceTone,
                language: settings.language
            )
            .frame(height: 196)

            tabBar
                // Sits on the stage's lower edge.
                .offset(y: -21)
                .padding(.bottom, -21)
                .zIndex(1)

            pageArea
        }
        .onChange(of: selection) { page in
            guard case .feature(let feature) = page else { return }
            if Feature.alerts.contains(feature) { lastAlert = feature } else { lastTool = feature }
        }
        .foregroundStyle(p.text)
        .frame(minWidth: 940, maxWidth: .infinity, minHeight: 690, maxHeight: .infinity)
        .background(p.page)
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        .tint(accent)
        .onReceive(router?.$requestedDestination.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { destination in
            guard let destination else { return }
            selection = SettingsPage(destination)
            router?.requestedDestination = nil
        }
        .onReceive(router?.$requestedFeature.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { identifier in
            guard let identifier, let feature = Feature(rawValue: identifier) else { return }
            selection = .feature(feature)
            router?.requestedFeature = nil
        }
        // macOS doesn't announce permission changes; re-read them while
        // Settings is open so badges update as soon as access is granted.
        .onAppear(perform: settings.refreshPermissionState)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            // Only while the window is on screen (no router: the standard
            // Settings scene, which closes for real).
            guard router?.isWindowVisible ?? true else { return }
            settings.refreshPermissionState()
        }
        .alert(text("Varsayılanlara dönülsün mü?", "Restore defaults?"), isPresented: $confirmsReset) {
            Button(text("Vazgeç", "Cancel"), role: .cancel) {}
            Button(text("Varsayılanlara dön", "Restore"), role: .destructive) {
                settings.resetInteractionDefaults()
                settings.resetDashboardFeatureDefaults()
            }
        } message: {
            Text(text(
                "Özellikler, bildirim kuralları ve çentiğin davranışı ilk hâline döner. Dil, renk ve kısayol tuşu değişmez.",
                "Features, notification rules and how the notch behaves go back to how they started. Language, colour and the keyboard shortcut stay."
            ))
        }
    }

    @ViewBuilder private var currentPage: some View {
        switch selection {
        case .general: generalPage
        case .appearance: appearancePage
        case .permissions: permissionsPage
        case .about: aboutPage
        case .feature(let feature): featurePage(feature)
        }
    }

    // MARK: Tabs

    private var tab: SettingsTab {
        switch selection {
        case .general: .general
        case .appearance: .appearance
        case .permissions: .permissions
        case .about: .about
        case .feature(let feature): Feature.alerts.contains(feature) ? .alerts : .tools
        }
    }

    private func select(_ tab: SettingsTab) {
        hoveredFeature = nil
        switch tab {
        case .general: selection = .general
        case .appearance: selection = .appearance
        case .alerts: selection = .feature(lastAlert)
        case .tools: selection = .feature(lastTool)
        case .permissions: selection = .permissions
        case .about: selection = .about
        }
    }

    private func title(_ tab: SettingsTab) -> String {
        switch tab {
        case .general: text("Genel", "General")
        case .appearance: text("Görünüm", "Appearance")
        case .alerts: text("Uyarılar", "Alerts")
        case .tools: text("Araçlar", "Tools")
        case .permissions: text("İzinler", "Permissions")
        case .about: text("Hakkında", "About")
        }
    }

    private func symbol(_ tab: SettingsTab) -> String {
        switch tab {
        case .general: "gearshape.fill"
        case .appearance: "paintpalette.fill"
        case .alerts: "bell.badge.fill"
        case .tools: "square.grid.2x2.fill"
        case .permissions: "lock.shield.fill"
        case .about: "info.circle.fill"
        }
    }

    private var tabBar: some View {
        HStack(spacing: 3) {
            ForEach(SettingsTab.allCases, id: \.self) { item in
                let isSelected = tab == item
                Button { select(item) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: symbol(item))
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(title(item))
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1)
                        if item == .permissions, settings.missingPermissionCount > 0 {
                            Text("\(settings.missingPermissionCount)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Capsule().fill(Color.orange))
                                .help(text("Eksik izin var", "A permission is missing"))
                        }
                    }
                    .foregroundStyle(isSelected ? onAccent : p.text.opacity(0.78))
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Capsule().fill(isSelected ? accent : .clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .modifier(NoFocusRing())
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(p.card)
                .shadow(color: Color.black.opacity(0.16), radius: 14, y: 5)
        )
        .overlay(Capsule().strokeBorder(p.line, lineWidth: 1))
    }

    /// Under the tabs: the two feature tabs pair a list of switches with
    /// the chosen feature's options; the rest are single pages.
    @ViewBuilder private var pageArea: some View {
        switch tab {
        case .alerts: featurePane(Feature.alerts)
        case .tools: featurePane(Feature.panel)
        default:
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    currentPage
                }
                .frame(maxWidth: 700, alignment: .leading)
                .padding(.horizontal, 34)
                .padding(.top, 24)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
            // Each page starts at the top.
            .id(selection)
        }
    }

    private func featurePane(_ features: [Feature]) -> some View {
        HStack(alignment: .top, spacing: 20) {
            featureList(features)
                .frame(width: 286)
                .padding(.top, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    currentPage
                }
                .padding(.top, 24)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .id(selection)
        }
        .padding(.horizontal, 30)
    }

    /// Every feature of the tab with its switch, so the whole set can be
    /// read and changed at a glance; a click shows that feature's options.
    private func featureList(_ features: [Feature]) -> some View {
        VStack(spacing: 2) {
            ForEach(features) { feature in
                let isSelected = selection == .feature(feature)
                let isOn = isEnabled(feature)
                HStack(spacing: 10) {
                    IconTile(symbol: feature.symbol, colors: feature.colors, size: 26, isOn: isOn.wrappedValue)
                    Text(title(feature))
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if needsPermission(feature) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.orange)
                            .help(text("İzin gerekli", "Needs permission"))
                    }
                    switchControl(isOn)
                        .controlSize(.small)
                        .accessibilityLabel(Text(title(feature)))
                }
                .padding(.horizontal, 10)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isSelected ? accent.opacity(0.13) : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .onTapGesture { selection = .feature(feature) }
                .onHover { inside in
                    if inside {
                        hoveredFeature = feature
                    } else if hoveredFeature == feature {
                        hoveredFeature = nil
                    }
                }
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(6)
        .background(cardBackground)
    }

    // MARK: Stage

    /// What the notch on the stage acts out: the feature under the pointer,
    /// else the page that is open, with the settings as they are now.
    private var stageDemo: StageDemo {
        if let hoveredFeature, tab == .alerts || tab == .tools { return demo(for: hoveredFeature) }
        switch selection {
        case .general: return .music
        case .appearance: return .dashboard
        case .permissions: return .permissions(missing: settings.missingPermissionCount)
        case .about:
            return .about(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
        case .feature(let feature): return demo(for: feature)
        }
    }

    private func demo(for feature: Feature) -> StageDemo {
        guard isEnabled(feature).wrappedValue else { return .off }
        switch feature {
        case .notifications: return settings.notificationPreviewStyle == .content ? .message : .messageCount
        case .commandEcho: return .volume
        case .calendar: return settings.calendarAlertsEnabled ? .meeting : .nextEvent
        case .devices: return .charging
        case .privacy: return .privacy
        case .screenshots: return .screenshot
        case .downloads: return .download
        case .timer: return settings.liveTimerInNotch ? .timer : .timerPanel
        case .shelf: return .shelf
        case .clipboard: return .clipboard
        case .shortcuts: return .shortcuts
        case .keepAwake: return .awake
        case .weather: return .weather(rain: settings.rainAlertsEnabled)
        case .lyrics: return .lyrics
        }
    }

    private var stageCaption: String {
        let feature: Feature? = {
            if let hoveredFeature, tab == .alerts || tab == .tools { return hoveredFeature }
            if case .feature(let feature) = selection { return feature }
            return nil
        }()
        guard let feature else { return text("Canlı önizleme", "Live preview") }
        return isEnabled(feature).wrappedValue
            ? text("Canlı önizleme · \(title(feature))", "Live preview · \(title(feature))")
            : text("Kapalı · \(title(feature))", "Off · \(title(feature))")
    }

    private func title(_ page: SettingsPage) -> String {
        switch page {
        case .general: text("Genel", "General")
        case .appearance: text("Görünüm", "Appearance")
        case .permissions: text("İzinler", "Permissions")
        case .about: text("Hakkında", "About")
        case .feature(let feature): title(feature)
        }
    }

    private func symbol(_ page: SettingsPage) -> String {
        switch page {
        case .general: "gearshape.fill"
        case .appearance: "paintpalette.fill"
        case .permissions: "lock.shield.fill"
        case .about: "info.circle.fill"
        case .feature(let feature): feature.symbol
        }
    }

    private func colors(_ page: SettingsPage) -> [Color] {
        switch page {
        case .general: Tint.gray
        case .appearance: Tint.sunset
        case .permissions: settings.missingPermissionCount > 0 ? Tint.orange : Tint.green
        case .about: Tint.indigo
        case .feature(let feature): feature.colors
        }
    }

    /// A feature that's switched off shows a grey tile.
    private func isLit(_ page: SettingsPage) -> Bool {
        if case .feature(let feature) = page { return isEnabled(feature).wrappedValue }
        return true
    }

    // MARK: General

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            if settings.missingPermissionCount > 0 {
                noticeCard(
                    message: text("Bazı izinler eksik, bu yüzden bazı özellikler çalışmıyor.", "Some permissions are missing, so some features don't work."),
                    buttonTitle: text("İzinlere git", "Go to Permissions")
                ) { selection = .permissions }
            }

            group {
                row(text("Dil", "Language")) {
                    ChipPicker(selection: $settings.language, options: AppLanguage.allCases.map { ($0, $0.title) }, accent: accent, onAccent: onAccent)
                }
                divider
                row(text("Mac açılınca başlat", "Launch at login")) {
                    switchControl(launchAtLoginBinding)
                }
                if settings.launchAtLoginRequiresApproval {
                    inlineNotice(text("Başlangıç izni macOS onayı bekliyor.", "Launch at login is waiting for macOS approval."), buttonTitle: text("Giriş Öğelerini Aç", "Open Login Items"), action: settings.openLoginItemsSettings)
                } else if let error = settings.launchAtLoginError {
                    inlineNotice(error)
                }
            }

            group(text("Çentik", "Notch")) {
                stackedRow(text("Açılma", "Opens"), subtitle: settings.activationMode.subtitle(language: settings.language)) {
                    ChipPicker(selection: $settings.activationMode, options: NotchActivationMode.allCases.map { ($0, $0.title(language: settings.language)) }, accent: accent, fillsWidth: true, onAccent: onAccent)
                }
                divider
                row(text("Şarkı değişince göster", "Show when the song changes")) {
                    switchControl($settings.showOnTrackChange)
                }
                if settings.showOnTrackChange {
                    divider
                    sliderRow(text("Gösterim süresi", "How long"), value: $settings.trackChangeDisplayDuration, range: 2...8, step: 0.5, valueText: String(format: text("%.1f sn", "%.1f s"), settings.trackChangeDisplayDuration))
                }
                divider
                row(text("Tam ekranda gizle", "Hide in full screen"), subtitle: text("Oyun, film ve sunumların üstünde görünmez.", "Stays out of games, films and presentations.")) {
                    switchControl($settings.hideInFullScreen)
                }
                divider
                sliderRow(text("Kapanma gecikmesi", "Collapse delay"), value: $settings.collapseDelay, range: 0.15...1.2, step: 0.05, valueText: String(format: text("%.2f sn", "%.2f s"), settings.collapseDelay))
            }

            hotKeyGroup

            HStack {
                Spacer()
                Button(text("Varsayılanlara dön…", "Restore defaults…")) { confirmsReset = true }
                    .buttonStyle(quietButton)
            }
        }
    }

    private var hotKeyGroup: some View {
        group(
            text("Kısayol tuşu", "Keyboard shortcut"),
            footer: settings.hotKeyEnabled
                ? text("Tuşlara tıkla ve yeni kısayola bas: ⌘ ya da ⌃ ile, veya ⌥ ile Boşluk, ok ya da F tuşu. Esc vazgeçer.", "Click the keys, then press the new shortcut: with ⌘ or ⌃, or ⌥ with Space, an arrow or an F-key. Esc cancels.")
                : nil
        ) {
            row(text("Kısayolla aç ve kapat", "Open and close with a shortcut"), subtitle: text("Hangi uygulamada olursan ol çentiği açar.", "Opens the notch from any app.")) {
                switchControl($settings.hotKeyEnabled)
            }
            if settings.hotKeyEnabled {
                divider
                row(
                    text("Tuşlar", "Keys"),
                    subtitle: settings.isHotKeyTaken ? text("Bunu başka bir uygulama kullanıyor; başka bir tane seç.", "Another app uses this one; pick a different one.") : nil
                ) {
                    HStack(spacing: 8) {
                        if settings.isHotKeyTaken {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                        if settings.toggleHotKey != .defaultToggle {
                            Button(text("Varsayılan", "Default")) { settings.toggleHotKey = .defaultToggle }
                                .buttonStyle(quietButton)
                        }
                        ShortcutRecorder(hotKey: $settings.toggleHotKey, language: settings.language, accent: accent)
                    }
                }
            }
        }
    }

    // MARK: Appearance

    private var appearancePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            group(text("Renk", "Colour")) {
                row(settings.accentTheme.title(language: settings.language)) {
                    AccentSwatchPicker(selection: $settings.accentTheme, language: settings.language)
                }
            }

            group(
                text("Ton", "Tone"),
                footer: text("Rengin açılan çentiğe ne kadar sineceği. Kamera çentiğinin yanı her zaman siyah kalır.", "How much the colour tints the open notch. Beside the camera it always stays black.")
            ) {
                SurfaceTonePicker(selection: $settings.surfaceTone, accent: accent, language: settings.language)
                    .padding(.vertical, 14)
            }
        }
    }

    // MARK: Feature pages

    private func featurePage(_ feature: Feature) -> some View {
        let isOn = isEnabled(feature)
        return VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                IconTile(symbol: feature.symbol, colors: feature.colors, size: 44, isOn: isOn.wrappedValue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title(feature)).font(.system(size: 18, weight: .semibold))
                    Text(summary(feature))
                        .font(.system(size: 12.5))
                        .foregroundStyle(p.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 16)
                switchControl(isOn)
                    .accessibilityLabel(Text(title(feature)))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(cardBackground)

            if needsPermission(feature), let permission = permission(for: feature) {
                group { permissionRow(permission) }
            }

            featureOptions(feature)
                .disabled(!isOn.wrappedValue)
                .opacity(isOn.wrappedValue ? 1 : 0.45)

            footnote(details(feature))
        }
        .onAppear {
            if feature == .timer || feature == .shortcuts, shortcutsManager.available.isEmpty {
                shortcutsManager.reload()
            }
        }
    }

    @ViewBuilder
    private func featureOptions(_ feature: Feature) -> some View {
        switch feature {
        case .notifications:
            group {
                row(text("macOS'un bildirimini gizle", "Hide macOS's banner"), subtitle: text("Köşedeki balon gizlenir; bildirim Bildirim Merkezi'nde kalır.", "The corner banner is hidden; the notification stays in Notification Center.")) {
                    switchControl($settings.hideSystemNotificationBanners)
                }
                divider
                row(text("Önizleme", "Preview")) {
                    ChipPicker(selection: $settings.notificationPreviewStyle, options: NotificationPreviewStyle.allCases.map { ($0, $0.title(language: settings.language)) }, accent: accent, onAccent: onAccent)
                }
            }
            notificationAppsGroup
            vipGroup
            notificationHelp
        case .calendar:
            group {
                row(text("Toplantı uyarısı", "Meeting alert"), subtitle: text("Etkinlikten 5 dakika önce çentik haber verir.", "The notch tells you 5 minutes before an event.")) {
                    switchControl($settings.calendarAlertsEnabled)
                }
            }
        case .screenshots:
            group(footer: text(
                "islo. kapalıyken macOS'un önizlemesi geri gelir. Klasörü değiştirmek için ⌘⇧5 > Seçenekler > Kaydetme Yeri; islo. yeni klasörü kendiliğinden izler.",
                "macOS's thumbnail comes back while islo. isn't running. To change the folder, use ⌘⇧5 > Options > Save to; islo. follows it by itself."
            )) {
                row(text("macOS'un küçük önizlemesini kapat", "Turn off macOS's thumbnail"), subtitle: text("Görüntü anında kaydedilir ve hemen çentikte açılır.", "The screenshot is saved at once and opens in the notch right away.")) {
                    switchControl($settings.hideSystemScreenshotThumbnail)
                }
                divider
                row(text("Klasör", "Folder"), subtitle: (settings.folderURL(.screenshots).path as NSString).abbreviatingWithTildeInPath) {
                    Button(text("Göster", "Show")) { NSWorkspace.shared.open(settings.folderURL(.screenshots)) }
                        .buttonStyle(quietButton)
                }
            }
        case .timer:
            group {
                row(text("Kapalı çentikte geri sayım", "Countdown in the closed notch"), subtitle: text("Kalan süre çentiğin yanlarında görünür.", "The time left shows beside the notch.")) {
                    switchControl($settings.liveTimerInNotch)
                }
            }
            group(
                text("Pomodoro", "Pomodoro"),
                footer: text("Kısayollar uygulamasında \"Odak Modunu Ayarla\" eylemiyle Rahatsız Etme'yi açıp kapatan iki kısayol oluşturabilirsin.", "In the Shortcuts app, the \"Set Focus\" action can turn Do Not Disturb on and off in two shortcuts.")
            ) {
                row(text("Odak başlarken", "When focus starts")) {
                    shortcutPicker($settings.focusStartShortcut)
                }
                divider
                row(text("Odak bitince", "When focus ends")) {
                    shortcutPicker($settings.focusEndShortcut)
                }
            }
        case .shortcuts:
            group(text("Çentikte görünecekler", "Shown in the notch")) {
                shortcutFavoritesPicker
            }
        case .weather:
            group(footer: text("Ana sayfada hava durumuna tıklayınca saatlik tahmin açılır.", "Click the weather on Home for the hourly forecast.")) {
                row(text("Yağmur uyarısı", "Rain alert"), subtitle: text("Yağmur bir saat içinde başlayacaksa çentik haber verir.", "The notch tells you when rain starts within the hour.")) {
                    switchControl($settings.rainAlertsEnabled)
                }
            }
            group(text("Şehir", "City")) {
                weatherCityPicker
            }
        default:
            EmptyView()
        }
    }

    // MARK: Notification apps and VIPs

    /// Every app that has sent a notification, with whether the notch shows
    /// it or leaves it to macOS.
    private var notificationAppsGroup: some View {
        group(
            text("Uygulamalar", "Apps"),
            footer: settings.knownNotificationApps.isEmpty ? nil : text("Kapattığın uygulamaların bildirimlerini macOS kendisi gösterir.", "macOS shows notifications from the apps you switch off itself.")
        ) {
            if settings.knownNotificationApps.isEmpty {
                Text(text("Bildirim gönderen uygulamalar burada listelenir.", "Apps that send notifications show up here."))
                    .font(.system(size: 12))
                    .foregroundStyle(p.muted)
                    .frame(minHeight: 46)
            } else {
                ForEach(Array(settings.knownNotificationApps.enumerated()), id: \.offset) { index, app in
                    if index > 0 { divider }
                    notificationAppRow(app)
                }
            }
        }
    }

    private func notificationAppRow(_ app: String) -> some View {
        let shown = Binding<Bool>(
            get: { !settings.mutedNotificationApps.contains(app) },
            set: { show in
                if show {
                    settings.mutedNotificationApps.removeAll { $0 == app }
                } else if !settings.mutedNotificationApps.contains(app) {
                    settings.mutedNotificationApps.append(app)
                }
            }
        )
        return HStack(spacing: 12) {
            Group {
                if let icon = Self.appIcon(named: app) {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    IconTile(symbol: "app.badge.fill", colors: Tint.red, size: 24)
                }
            }
            .frame(width: 26, height: 26)
            Text(app).font(.system(size: 13, weight: .medium))
            Spacer(minLength: 12)
            if !shown.wrappedValue {
                Text(text("macOS gösterir", "macOS shows it"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(p.muted)
            }
            switchControl(shown)
                .accessibilityLabel(Text(app))
        }
        .frame(minHeight: 46)
    }

    private static func appIcon(named name: String) -> NSImage? {
        if let running = NSWorkspace.shared.runningApplications.first(where: { ($0.localizedName ?? "").withoutDirectionMarks == name }),
           let icon = running.icon {
            return icon
        }
        for folder in ["/Applications", "/System/Applications", "/Applications/Utilities", "/System/Applications/Utilities"] {
            let path = "\(folder)/\(name).app"
            if FileManager.default.fileExists(atPath: path) { return NSWorkspace.shared.icon(forFile: path) }
        }
        return nil
    }

    private var vipGroup: some View {
        group(
            text("VIP kişiler", "VIPs"),
            footer: text("Bu kişilerden gelen mesajlar çentikte altın rengiyle ve daha uzun süre görünür. Adı bildirimde göründüğü gibi yaz.", "Messages from these people show in gold and stay longer. Write the name as it appears in the notification.")
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    TextField(text("Ad ekle, örn. Ahmet", "Add a name, e.g. Alex"), text: $vipDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .onSubmit(addVIP)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(fieldBackground)
                    Button(text("Ekle", "Add"), action: addVIP)
                        .buttonStyle(primaryButton)
                        .disabled(vipDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !settings.vipNames.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                        ForEach(settings.vipNames, id: \.self, content: vipChip)
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }

    private func vipChip(_ name: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "star.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color(hex: 0xE8A600))
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 2)
            Button {
                settings.vipNames.removeAll { $0 == name }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(p.muted)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(p.fill))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(text("\(name) kişisini kaldır", "Remove \(name)")))
        }
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .frame(height: 28)
        .background(Capsule().fill(Color(hex: 0xFFF6DD)))
        .overlay(Capsule().strokeBorder(Color(hex: 0xF0D68A), lineWidth: 1))
    }

    private func addVIP() {
        let name = vipDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if !settings.vipNames.contains(where: { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            settings.vipNames.append(name)
        }
        vipDraft = ""
    }

    /// Why notifications might not show, folded away until asked for.
    private var notificationHelp: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showsNotificationHelp.toggle() }
            } label: {
                HStack {
                    Text(text("Bildirim gelmiyor mu?", "Not seeing notifications?"))
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(p.faint)
                        .rotationEffect(.degrees(showsNotificationHelp ? 90 : 0))
                }
                .frame(minHeight: 46)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsNotificationHelp {
                divider
                VStack(alignment: .leading, spacing: 9) {
                    bullet(text("Odak (Rahatsız Etme) açıkken macOS bildirim göstermez, islo. de göremez.", "While a Focus (Do Not Disturb) is on, macOS shows no notifications, so islo. can't either."))
                    bullet(text("Uygulamanın bildirimleri Sistem Ayarları > Bildirimler'de açık olmalı ve uyarı stili \"Yok\" olmamalı.", "The app's notifications must be on in System Settings > Notifications, with an alert style other than \"None\"."))
                    bullet(text("Bir sohbet uygulaması (ör. WhatsApp) öndeyken o sohbetin mesajları için macOS bildirim göstermez.", "While a chat app (e.g. WhatsApp) is in front, macOS doesn't show notifications for that chat."))
                    HStack {
                        Spacer()
                        Button(text("Bildirim ayarlarını aç", "Open Notification settings"), action: openNotificationSettings)
                            .buttonStyle(quietButton)
                    }
                    .padding(.top, 2)
                }
                .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 14)
        .background(cardBackground)
    }

    // MARK: Feature facts

    private func isEnabled(_ feature: Feature) -> Binding<Bool> {
        switch feature {
        case .notifications: $settings.dashboardNotificationsEnabled
        case .commandEcho: $settings.dashboardCommandEchoEnabled
        case .calendar: $settings.calendarEnabled
        case .devices: $settings.devicesHUDEnabled
        case .privacy: $settings.privacyIndicatorEnabled
        case .screenshots: $settings.screenshotPreviewEnabled
        case .downloads: $settings.downloadsEnabled
        case .timer: $settings.dashboardFocusTimerEnabled
        case .shelf: $settings.dashboardFileShelfEnabled
        case .clipboard: $settings.dashboardClipboardEnabled
        case .shortcuts: $settings.shortcutsEnabled
        case .keepAwake: $settings.dashboardKeepAwakeEnabled
        case .weather: $settings.weatherEnabled
        case .lyrics: $settings.lyricsEnabled
        }
    }

    private func permission(for feature: Feature) -> FeaturePermission? {
        switch feature {
        case .notifications, .commandEcho: .accessibility
        case .calendar: .calendar
        case .screenshots:
            ProtectedFolder.privacyService(for: settings.folderURL(.screenshots)) == nil ? nil : .folder(.screenshots)
        case .downloads: .folder(.downloads)
        default: nil
        }
    }

    private func permissionState(_ permission: FeaturePermission) -> PermissionState {
        switch permission {
        case .accessibility: settings.isAccessibilityTrusted ? .granted : .missing
        case .calendar: calendarManager.authorization
        // Only checked while the feature is on; macOS asks when it starts.
        case .folder(let folder): settings.folderStates[folder] ?? .notAsked
        }
    }

    private func needsPermission(_ feature: Feature) -> Bool {
        guard isEnabled(feature).wrappedValue, let permission = permission(for: feature) else { return false }
        let state = permissionState(permission)
        if case .folder = permission { return state == .missing }
        return state == .missing || state == .notAsked
    }

    private func title(_ feature: Feature) -> String {
        switch feature {
        case .notifications: text("Bildirimler", "Notifications")
        case .commandEcho: text("Ses ve parlaklık", "Volume & brightness")
        case .calendar: text("Takvim", "Calendar")
        case .devices: text("Şarj ve kulaklık", "Charging & headphones")
        case .privacy: text("Kamera ve mikrofon", "Camera & microphone")
        case .screenshots: text("Ekran görüntüsü", "Screenshots")
        case .downloads: text("İndirmeler", "Downloads")
        case .timer: text("Zamanlayıcı", "Timer")
        case .shelf: text("Dosya Rafı", "File Shelf")
        case .clipboard: text("Pano", "Clipboard")
        case .shortcuts: text("Kısayollar", "Shortcuts")
        case .keepAwake: text("Uyanık Tut", "Keep Awake")
        case .weather: text("Hava durumu", "Weather")
        case .lyrics: text("Şarkı sözleri", "Lyrics")
        }
    }

    private func summary(_ feature: Feature) -> String {
        switch feature {
        case .notifications: text("WhatsApp, Mesajlar ve diğer uygulamaların bildirimleri çentikte açılır.", "Notifications from WhatsApp, Messages and other apps open in the notch.")
        case .commandEcho: text("Ses, parlaklık, kopyalama ve Caps Lock çentikte görünür.", "Volume, brightness, copy and Caps Lock show in the notch.")
        case .calendar: text("Sıradaki etkinlik ve görüşmeler için Katıl düğmesi.", "Your next event, with Join for video calls.")
        case .devices: text("Şarj, düşük pil ve AirPods pil seviyesi.", "Charging, low battery and AirPods battery.")
        case .privacy: text("Kamerayı ya da mikrofonu kullanan uygulamayı gösterir.", "Shows which app is using the camera or mic.")
        case .screenshots: text("Yeni ekran görüntüsü çentiğin altında önizlenir.", "New screenshots preview under the notch.")
        case .downloads: text("İndirme ilerlemesi kapalı çentikte bir halkayla.", "Download progress as a ring in the closed notch.")
        case .timer: text("Zamanlayıcı ve Pomodoro, geri sayımı çentikte.", "Timer and Pomodoro, counting down in the notch.")
        case .shelf: text("Dosyaları çentiğe bırak, taşı ya da AirDrop'la.", "Drop files on the notch, move or AirDrop them.")
        case .clipboard: text("Son kopyaladığın metinler çentikte bir tık uzağında.", "The text you copied recently, one click away in the notch.")
        case .shortcuts: text("Seçtiğin kısayollar çentikte tek tıkla çalışır.", "Your picked shortcuts run in one click.")
        case .keepAwake: text("Mac'in uykuya geçmesini istediğin kadar engeller.", "Keeps your Mac awake as long as you need.")
        case .weather: text("Ana sayfada sıcaklık ve hava durumu.", "Temperature and conditions on Home.")
        case .lyrics: text("Şarkı kartında satır satır akan sözler.", "Lyrics that follow the song, line by line.")
        }
    }

    /// One or two lines under a feature's page: how it works, and what
    /// leaves the Mac, if anything.
    private func details(_ feature: Feature) -> String {
        switch feature {
        case .notifications:
            text("Bildirime tıklayınca Bildirimler sekmesi açılır. islo. bildirimleri macOS'un ekranda gösterdiklerinden okur; bunun için yalnızca Erişilebilirlik izni gerekir.", "Click a notification to open the Notifications tab. islo. reads the notifications macOS shows on screen, so it only needs Accessibility access.")
        case .commandEcho:
            text("Kopyalama, ekran görüntüsü ve Caps Lock da aynı ince şeritle görünür. macOS'un kendi göstergesini gizlemek için Erişilebilirlik izni gerekir.", "Copying, screenshots and Caps Lock show in the same slim bar. Hiding macOS's own indicator needs Accessibility access.")
        case .calendar:
            text("Etkinlikler Mac'indeki Takvim'den okunur ve hiçbir yere gönderilmez.", "Events are read from Calendar on your Mac and never sent anywhere.")
        case .devices:
            text("AirPods gibi Bluetooth kulaklıklar bağlanınca pil seviyeleri görünür; çıkış cihazını şarkı kartından değiştirebilirsin.", "When Bluetooth headphones like AirPods connect, their battery shows; switch the output from the song card.")
        case .privacy:
            text("Kamera kullanılırken yeşil, mikrofon kullanılırken turuncu bir nokta belirir. Çentiği açınca hangi uygulama olduğu görünür.", "A green dot shows while the camera is in use, orange for the mic. Open the notch to see which app it is.")
        case .screenshots:
            text("Önizlemeyi istediğin yere sürükle ya da Kopyala, Rafa ekle, Göster ve Sil ile tek tıkla işini gör.", "Drag the preview anywhere, or Copy, add to the Shelf, Show or Delete it in one click.")
        case .downloads:
            text("Safari, Chrome, Firefox ve AirDrop'tan İndirilenler'e gelen dosyalar görünür; bitince Aç ve Göster düğmeleri çıkar.", "Files arriving in Downloads from Safari, Chrome, Firefox and AirDrop show up, with Open and Show when they're done.")
        case .timer:
            text("Kadranı çevirerek ya da −/+ ile süreyi kur. Pomodoro modunda odak ve mola turları sırayla ilerler.", "Turn the dial or use −/+ to set the time. Pomodoro mode alternates focus and breaks.")
        case .shelf:
            text("Raftan kaldırmak dosyayı silmez. Otomatik temizleme süresini Raf sekmesinden seçebilirsin.", "Removing a file from the shelf never deletes it. Pick an auto-clear time in the Shelf tab.")
        case .clipboard:
            text("Geçmiş yalnızca bellekte tutulur, diske yazılmaz ve islo. kapanınca silinir. Parola yöneticilerinin gizli olarak işaretlediği kopyalar alınmaz; işaretlenmemiş bir parola yine de görünebilir. Otomatik temizleme süresini Pano sekmesinden seçebilirsin.", "History stays in memory only, is never written to disk and is gone when islo. quits. Copies that password managers mark as concealed are skipped; an unmarked password can still show up. Pick an auto-clear time in the Clipboard tab.")
        case .shortcuts:
            text("Kısayollar uygulamasından en fazla 7 kısayol seç; çentikte renkli kutucuklar olarak durur.", "Pick up to 7 shortcuts from the Shortcuts app; they sit in the notch as coloured tiles.")
        case .keepAwake:
            text("Açtığında Mac, sen kapatana kadar uyumaz. Çentikten tek tıkla açıp kapatırsın.", "While it's on, your Mac won't sleep until you turn it off. Toggle it from the notch in one click.")
        case .weather:
            text("Veriler ücretsiz Open-Meteo'dan gelir; konum izni gerekmez. Şehir, Mac'in saat diliminden bulunur ya da yukarıdan seçilir.", "Data comes from the free Open-Meteo service with no location permission. The city comes from your Mac's time zone, or pick one above.")
        case .lyrics:
            text("Şarkı kartındaki söz düğmesine bas. Sözler ücretsiz LRCLIB'den gelir; bunun için şarkının adı ve sanatçısı oraya gönderilir.", "Press the lyrics button on the song card. Lyrics come from the free LRCLIB service, which receives the song's title and artist.")
        }
    }

    // MARK: Permissions

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            permissionSummary

            group(text("Sistem", "System")) {
                permissionRow(.accessibility)
                if !settings.isAccessibilityTrusted {
                    accessibilitySteps
                }
                divider
                permissionRow(.calendar)
                ForEach(ProtectedFolder.allCases) { folder in
                    if settings.folderStates[folder] != nil {
                        divider
                        permissionRow(.folder(folder))
                    }
                }
            }

            group(text("Müzik uygulamaları", "Music apps")) {
                ForEach(Array(AutomationTarget.allCases.enumerated()), id: \.element) { index, target in
                    if index > 0 { divider }
                    automationRow(target)
                }
            }
        }
    }

    private var permissionSummary: some View {
        let missing = settings.missingPermissionCount
        // Calendar is on but macOS hasn't asked yet: not broken, just waiting.
        let isCalendarWaiting = missing == 0 && settings.calendarEnabled && calendarManager.authorization == .notAsked
        let title = missing > 0
            ? text("\(missing) izin eksik", missing == 1 ? "1 permission missing" : "\(missing) permissions missing")
            : isCalendarWaiting ? text("Bir izin bekliyor", "One permission to give") : text("Her şey hazır", "All set")
        let detail = missing > 0
            ? missingPermissionImpact
            : isCalendarWaiting
                ? text("Takvim etkinliklerinin görünmesi için aşağıdan Takvim iznini ver.", "Allow Calendars below so your events can show.")
                : text("islo.'nun ihtiyaç duyduğu izinlerin hepsi verilmiş.", "islo. has every permission it needs.")
        return HStack(spacing: 13) {
            IconTile(
                symbol: missing > 0 ? "exclamationmark.shield.fill" : isCalendarWaiting ? "questionmark.circle.fill" : "checkmark.shield.fill",
                colors: missing > 0 ? Tint.orange : isCalendarWaiting ? Tint.blue : Tint.green,
                size: 36
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(p.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(cardBackground)
    }

    private var missingPermissionImpact: String {
        var parts: [String] = []
        if !settings.isAccessibilityTrusted {
            parts.append(text("Bildirimler çentikte görünmüyor ve ses/parlaklıkta macOS'un kendi göstergesi de çıkıyor.", "Notifications don't reach the notch, and macOS's own volume/brightness indicator still appears."))
        }
        if settings.calendarEnabled, calendarManager.authorization == .missing {
            parts.append(text("Takvim etkinlikleri gösterilemiyor.", "Calendar events can't be shown."))
        }
        if settings.folderStates[.screenshots] == .missing {
            parts.append(text("Ekran görüntüleri önizlenemiyor.", "Screenshots can't be previewed."))
        }
        if settings.folderStates[.downloads] == .missing {
            parts.append(text("Bazı indirmeler görünmüyor.", "Some downloads don't show."))
        }
        let blocked = AutomationTarget.allCases.filter { settings.automationStates[$0] == .missing }.map(\.name)
        if !blocked.isEmpty {
            let names = blocked.joined(separator: ", ")
            parts.append(text("\(names) çalan şarkısı gösterilemiyor ve kontrol edilemiyor.", "\(names) playback can't be shown or controlled."))
        }
        return parts.joined(separator: " ")
    }

    @ViewBuilder
    private func permissionRow(_ permission: FeaturePermission) -> some View {
        let state = permissionState(permission)
        switch permission {
        case .accessibility:
            row(text("Erişilebilirlik", "Accessibility"), subtitle: text("Bildirimleri okumak ve ses/parlaklık göstergesinin yerine geçmek için.", "To read notifications and stand in for the volume and brightness indicator."), symbol: "hand.raised.fill", colors: Tint.blue) {
                HStack(spacing: 8) {
                    permissionBadge(state)
                    if state != .granted {
                        Button(text("İzin ver", "Allow"), action: settings.requestAccessibilityPermission)
                            .buttonStyle(primaryButton)
                    }
                }
            }
        case .calendar:
            row(text("Takvim", "Calendars"), subtitle: text("Sıradaki etkinlik ve toplantı uyarısı için.", "For your next event and meeting alerts."), symbol: "calendar", colors: Tint.pink) {
                HStack(spacing: 8) {
                    permissionBadge(state)
                    if state == .notAsked {
                        Button(text("İzin ver", "Allow"), action: calendarManager.requestAccess)
                            .buttonStyle(primaryButton)
                    } else if state == .missing {
                        Button(text("Ayarları aç", "Open Settings"), action: calendarManager.openPrivacySettings)
                            .buttonStyle(primaryButton)
                    }
                }
            }
        case .folder(let folder):
            let name = (settings.folderURL(folder).path as NSString).abbreviatingWithTildeInPath
            row(
                folder == .screenshots ? text("Ekran görüntüsü klasörü", "Screenshot folder") : text("İndirilenler klasörü", "Downloads folder"),
                subtitle: name,
                symbol: folder == .screenshots ? "camera.viewfinder" : "arrow.down.circle.fill",
                colors: folder == .screenshots ? Tint.purple : Tint.mint
            ) {
                HStack(spacing: 8) {
                    permissionBadge(state)
                    if state == .missing {
                        Button(text("Düzelt", "Fix")) { settings.requestFolderAccess(folder) }
                            .buttonStyle(primaryButton)
                    }
                }
            }
        }
    }

    private var accessibilitySteps: some View {
        VStack(alignment: .leading, spacing: 8) {
            permissionStep(1, text("“İzin ver”e bas. macOS bir izin penceresi açar.", "Click “Allow”. macOS shows a permission prompt."))
            permissionStep(2, text("“Sistem Ayarları'nı Aç”ı seç ve listede islo.'nun anahtarını aç.", "Choose “Open System Settings” and switch islo. on in the list."))
            permissionStep(3, text("Bu sayfa birkaç saniye içinde kendiliğinden “Verildi” olur.", "This page changes to “Allowed” by itself within seconds."))
            Text(text("Güncellemeden sonra islo. listede açık görünse bile burada “Eksik” yazıyorsa yine “İzin ver”e bas; islo. eski kaydı kendisi temizler.", "If islo. looks switched on in the list after an update but this still says “Missing”, click “Allow” anyway; islo. clears the old entry itself."))
                .font(.system(size: 11))
                .foregroundStyle(p.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.09)))
        .padding(.leading, 38)
        .padding(.bottom, 12)
    }

    private func permissionStep(_ number: Int, _ message: String) -> some View {
        HStack(spacing: 9) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.orange))
            Text(message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func automationRow(_ target: AutomationTarget) -> some View {
        let state = settings.automationStates[target] ?? .appClosed
        return row(target.name, subtitle: automationSubtitle(state), symbol: target == .music ? "music.note" : "waveform", colors: target == .music ? Tint.red : Tint.green) {
            HStack(spacing: 8) {
                permissionBadge(state)
                if state == .missing || state == .notAsked {
                    Button(state == .missing ? text("Düzelt", "Fix") : text("İzin ver", "Allow")) {
                        settings.requestAutomationPermission(for: target)
                    }
                    .buttonStyle(primaryButton)
                }
            }
        }
    }

    private func automationSubtitle(_ state: PermissionState) -> String {
        switch state {
        case .missing:
            text("Kapalı; çalan şarkı gösterilemiyor. “Düzelt” macOS'un yeniden sormasını sağlar.", "Off, so the current song can't show. “Fix” makes macOS ask again.")
        case .appClosed:
            text("Çalan şarkı için. Durumu, uygulama açıkken görünür.", "For the current song. Its status shows while the app is open.")
        case .appNotInstalled:
            text("Bu Mac'te yüklü değil.", "Not installed on this Mac.")
        case .granted, .notAsked:
            text("Çalan şarkıyı göstermek ve kontrol etmek için.", "To show and control the current song.")
        }
    }

    private func permissionBadge(_ state: PermissionState) -> some View {
        let style: (title: String, symbol: String, color: Color) = switch state {
        case .granted: (text("Verildi", "Allowed"), "checkmark.circle.fill", p.good)
        case .missing: (text("Eksik", "Missing"), "exclamationmark.triangle.fill", p.warning)
        case .notAsked: (text("Sorulmadı", "Not asked"), "questionmark.circle.fill", p.muted)
        case .appClosed: (text("Uygulama kapalı", "App not running"), "moon.zzz.fill", p.muted)
        case .appNotInstalled: (text("Yüklü değil", "Not installed"), "minus.circle.fill", p.muted)
        }
        return Label(style.title, systemImage: style.symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(style.color)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill(style.color.opacity(0.12)))
            .fixedSize()
    }

    // MARK: About

    private var aboutPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().scaledToFit().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("islo.").font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(text("Mac'inin üstünde, gününün yanında.", "At the top of your Mac, close to your day."))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(p.muted)
                }
                Spacer(minLength: 12)
                Text(versionText)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(p.muted)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(p.fill))
            }
            .padding(18)
            .background(cardBackground)

            group(text("Güncellemeler", "Updates")) {
                row(text("Güncellemeleri denetle", "Check for updates"), subtitle: text("Yeni sürümler imzalı GitHub sürümlerinden gelir.", "New versions come from signed GitHub releases.")) {
                    Button(text("Şimdi denetle", "Check now")) { updateManager.checkForUpdates() }
                        .buttonStyle(primaryButton)
                        .disabled(!updateManager.canCheckForUpdates)
                }
                divider
                row(text("Otomatik güncelle", "Update automatically")) {
                    switchControl(automaticUpdatesBinding)
                }
            }

            group(text("Bağlantılar", "Links")) {
                row(text("Web sitesi", "Website"), subtitle: "ozdmrysn.github.io/islo") {
                    Button(text("Aç", "Open")) { open("https://ozdmrysn.github.io/islo/") }
                        .buttonStyle(quietButton)
                }
                divider
                row("GitHub", subtitle: "github.com/OzdmrYsn/islo") {
                    Button(text("Aç", "Open")) { open("https://github.com/OzdmrYsn/islo") }
                        .buttonStyle(quietButton)
                }
                divider
                row(text("Tanıtım", "Welcome guide"), subtitle: text("İlk açılıştaki tanıtımı yeniden göster.", "Show the guide from the first launch again.")) {
                    Button(text("Göster", "Show")) { onShowOnboarding() }
                        .buttonStyle(quietButton)
                }
            }

            Text(text("Yasin Özdemir tarafından geliştirildi.", "Built by Yasin Özdemir."))
                .font(.system(size: 11.5))
                .foregroundStyle(p.faint)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: Building blocks

    /// A white card of rows, with an optional title above and note below.
    private func group<Content: View>(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(p.text.opacity(0.88))
                    .padding(.leading, 2)
            }
            VStack(alignment: .leading, spacing: 0, content: content)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBackground)
            if let footer { footnote(footer) }
        }
    }

    private func row<Accessory: View>(
        _ title: String,
        subtitle: String? = nil,
        symbol: String? = nil,
        colors: [Color] = [],
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 12) {
            if let symbol { IconTile(symbol: symbol, colors: colors, size: 26) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(p.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            accessory()
        }
        .padding(.vertical, 9)
        .frame(minHeight: 46)
    }

    /// A row whose control is too wide to sit beside the title.
    private func stackedRow<Content: View>(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(p.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .padding(.vertical, 12)
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, valueText: String) -> some View {
        // Rounded here rather than with `step:`, which draws a row of ticks.
        let stepped = Binding<Double>(
            get: { value.wrappedValue },
            set: { value.wrappedValue = min(max((($0 - range.lowerBound) / step).rounded() * step + range.lowerBound, range.lowerBound), range.upperBound) }
        )
        return row(title) {
            HStack(spacing: 12) {
                Text(valueText)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(p.muted)
                    .frame(minWidth: 46, alignment: .trailing)
                Slider(value: stepped, in: range).frame(width: 180)
            }
        }
    }

    private func switchControl(_ isOn: Binding<Bool>) -> some View {
        Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).tint(accent)
    }

    private var divider: some View {
        Rectangle().fill(p.line).frame(height: 1)
    }

    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return shape
            .fill(p.card)
            .overlay(shape.strokeBorder(p.line, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.035), radius: 2, y: 1)
    }

    private var fieldBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return shape.fill(p.fill).overlay(shape.strokeBorder(p.line, lineWidth: 1))
    }

    private func footnote(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 11.5))
            .foregroundStyle(p.muted)
            .lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 2)
    }

    private func bullet(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Circle().fill(accent).frame(width: 5, height: 5).padding(.top, 6)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(p.text.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func noticeCard(message: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.system(size: 12.5, weight: .medium))
            Spacer()
            Button(buttonTitle, action: action)
                .buttonStyle(IsloButtonStyle(prominent: true, accent: .orange))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.orange.opacity(0.28), lineWidth: 1))
        )
    }

    private func inlineNotice(_ message: String, buttonTitle: String? = nil, action: @escaping () -> Void = {}) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.system(size: 12)).foregroundStyle(p.muted)
            Spacer()
            if let buttonTitle {
                Button(buttonTitle, action: action).buttonStyle(quietButton)
            }
        }
        .padding(.bottom, 12)
    }

    /// Up to seven shortcuts for the notch's Shortcuts tab, in the order
    /// they were picked.
    private var shortcutFavoritesPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(text("\(settings.shortcutFavorites.count)/7 seçili", "\(settings.shortcutFavorites.count) of 7 picked"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(p.muted)
                Spacer()
                if shortcutsManager.isLoading { ProgressView().controlSize(.small) }
                Button(text("Yenile", "Refresh"), action: shortcutsManager.reload)
                    .buttonStyle(quietButton)
                Button(text("Kısayollar'ı aç", "Open Shortcuts"), action: shortcutsManager.openShortcutsApp)
                    .buttonStyle(quietButton)
            }
            if shortcutsManager.available.isEmpty, !shortcutsManager.isLoading {
                Text(text("Hiç kısayol bulunamadı. Kısayollar uygulamasında bir kısayol oluşturup Yenile'ye bas.", "No shortcuts found. Create one in the Shortcuts app, then click Refresh."))
                    .font(.system(size: 12))
                    .foregroundStyle(p.muted)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                        // By position: two shortcuts can share a name that
                        // Swift treats as equal (different Unicode forms).
                        ForEach(Array(shortcutsManager.available.enumerated()), id: \.offset) { _, name in
                            shortcutChip(name)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 240)
            }
        }
        .padding(.vertical, 14)
    }

    private func shortcutChip(_ name: String) -> some View {
        let isOn = settings.shortcutFavorites.contains(name)
        let isFull = !isOn && settings.shortcutFavorites.count >= 7
        return Button {
            if isOn {
                settings.shortcutFavorites.removeAll { $0 == name }
            } else if !isFull {
                settings.shortcutFavorites.append(name)
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOn ? Color.white : p.faint)
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isOn ? Color.white : p.text)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isOn ? AnyShapeStyle(LinearGradient(colors: Tint.shortcuts, startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(p.fill))
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(isFull ? 0.4 : 1)
        .disabled(isFull)
        .help(name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func shortcutPicker(_ selection: Binding<String?>) -> some View {
        Picker("", selection: Binding(
            get: { selection.wrappedValue ?? "" },
            set: { selection.wrappedValue = $0.isEmpty ? nil : $0 }
        )) {
            Text(text("Yok", "None")).tag("")
            if let current = selection.wrappedValue, !shortcutsManager.available.contains(current) {
                Text(current).tag(current)
            }
            ForEach(Array(shortcutsManager.available.enumerated()), id: \.offset) { Text($0.element).tag($0.element) }
        }
        .labelsHidden()
        // The theme colour reads poorly as menu text on white (yellow, mint).
        .tint(p.text)
        .frame(width: 200)
    }

    private var weatherCityPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(settings.weatherLocation?.name ?? text("Otomatik", "Automatic"), subtitle: weatherLocationText) {
                if settings.weatherLocation != nil {
                    Button(text("Otomatiğe dön", "Use automatic")) { settings.weatherLocation = nil }
                        .buttonStyle(quietButton)
                }
            }
            divider
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(p.faint)
                    TextField(text("Şehir ara", "Search city"), text: $weatherQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .onSubmit(searchWeatherCity)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(fieldBackground)
                if isSearchingWeather { ProgressView().controlSize(.small) }
                Button(text("Ara", "Search"), action: searchWeatherCity)
                    .buttonStyle(primaryButton)
                    .disabled(weatherQuery.trimmingCharacters(in: .whitespaces).isEmpty || isSearchingWeather)
            }
            .padding(.vertical, 12)
            if !weatherResults.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(weatherResults) { location in
                        Button {
                            settings.weatherLocation = location
                            weatherResults = []
                            weatherQuery = ""
                        } label: {
                            HStack(spacing: 6) {
                                Text(location.name).font(.system(size: 12, weight: .semibold))
                                Text(location.detail).font(.system(size: 11.5)).foregroundStyle(p.muted)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(p.fill))
                .padding(.bottom, 12)
            }
        }
    }

    private var weatherLocationText: String {
        if let location = settings.weatherLocation {
            return [location.name, location.detail].filter { !$0.isEmpty }.joined(separator: ", ")
        }
        return text("Mac'in saat dilimindeki şehir", "The city in your Mac's time zone")
    }

    private func searchWeatherCity() {
        let query = weatherQuery
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearchingWeather = true
        Task {
            let results = await WeatherManager.search(query)
            weatherResults = results
            isSearchingWeather = false
        }
    }

    private func openNotificationSettings() {
        open("x-apple.systempreferences:com.apple.Notifications-Settings.extension")
    }

    private func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }

    private func text(_ turkish: String, _ english: String) -> String { settings.language.value(turkish: turkish, english: english) }
    private var accent: Color { settings.accentTheme.color }
    /// Text on the theme colour: dark on the light colours.
    private var onAccent: Color { settings.accentTheme == .yellow || settings.accentTheme == .mint ? .black : .white }
    private var primaryButton: IsloButtonStyle { IsloButtonStyle(prominent: true, accent: accent, onAccent: onAccent) }
    private var quietButton: IsloButtonStyle { IsloButtonStyle(accent: accent) }
    private var launchAtLoginBinding: Binding<Bool> { Binding(get: { settings.launchAtLogin }, set: settings.setLaunchAtLogin) }
    private var automaticUpdatesBinding: Binding<Bool> { Binding(get: { updateManager.automaticUpdatesEnabled }, set: updateManager.setAutomaticUpdates) }
    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        return "islo. \(version)"
    }
}

/// Click, then press a key combination; it becomes the shortcut.
private struct ShortcutRecorder: View {
    @Binding var hotKey: HotKey
    let language: AppLanguage
    let accent: Color
    @State private var isRecording = false
    @State private var monitor: Any?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = IsloPalette.of(scheme)
        Button(action: { isRecording ? stop() : start() }) {
            Text(isRecording ? language.value(turkish: "Tuşlara bas…", english: "Press keys…") : hotKey.displayString)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isRecording ? accent : palette.text)
                .frame(minWidth: 104)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(isRecording ? accent.opacity(0.14) : palette.fill))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(isRecording ? accent : palette.line, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onDisappear(perform: stop)
        // Closing Settings only hides it, so onDisappear may not run.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            if isRecording { stop() }
        }
        .accessibilityLabel(Text(language.value(turkish: "Kısayol: ", english: "Shortcut: ") + hotKey.displayString))
    }

    private func start() {
        isRecording = true
        HotKeyManager.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            guard HotKey.isAllowed(keyCode: Int(event.keyCode), flags: event.modifierFlags) else {
                NSSound.beep()
                return nil
            }
            hotKey = HotKey(
                keyCode: UInt32(event.keyCode),
                modifiers: HotKey.carbonModifiers(from: event.modifierFlags)
            )
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        HotKeyManager.shared.resume()
    }
}

private struct NoFocusRing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.focusEffectDisabled()
        } else {
            content
        }
    }
}

/// A row of colour swatches for the theme colour.
struct AccentSwatchPicker: View {
    @Binding var selection: AccentTheme
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AccentTheme.allCases) { theme in
                let isSelected = selection == theme
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selection = theme }
                } label: {
                    Circle()
                        .fill(LinearGradient(colors: [theme.color.opacity(0.85), theme.color], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 24, height: 24)
                        .overlay {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(theme == .yellow || theme == .mint ? Color.black : Color.white)
                            }
                        }
                        .shadow(color: theme.color.opacity(isSelected ? 0.45 : 0), radius: 6)
                        .padding(3)
                        .overlay(Circle().stroke(isSelected ? theme.color : Color.clear, lineWidth: 2))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(theme.title(language: language))
                .accessibilityLabel(Text(theme.title(language: language)))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// Cards that preview each tone with the current theme colour.
struct SurfaceTonePicker: View {
    @Binding var selection: SurfaceTone
    let accent: Color
    let language: AppLanguage
    @Environment(\.colorScheme) private var scheme
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        let palette = IsloPalette.of(scheme)
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(SurfaceTone.allCases) { tone in
                let isSelected = selection == tone
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selection = tone }
                } label: {
                    VStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black)
                            .overlay {
                                LinearGradient(
                                    colors: [accent.opacity(tone.tintOpacity), accent.opacity(tone.tintOpacity * 0.35), .black],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .frame(height: 42)
                        Text(tone.title(language: language))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isSelected ? palette.text : palette.muted)
                            .lineLimit(1)
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isSelected ? accent.opacity(0.08) : palette.fill.opacity(0.6)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(isSelected ? accent : palette.line, lineWidth: isSelected ? 2 : 1))
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}


// MARK: - The stage

/// What the notch at the top of Settings is acting out.
private enum StageDemo: Hashable {
    case off, music, dashboard
    case message, messageCount, volume, meeting, nextEvent, charging, privacy, screenshot, download
    case timer, timerPanel, shelf, clipboard, shortcuts, awake
    case weather(rain: Bool)
    case lyrics
    case permissions(missing: Int)
    case about(version: String)

    /// The notch's size, not counting the concave top corners.
    var size: CGSize {
        switch self {
        case .off: CGSize(width: 172, height: 30)
        case .music, .awake, .privacy: CGSize(width: 262, height: 30)
        case .messageCount, .charging, .download, .timer: CGSize(width: 318, height: 30)
        case .volume, .weather, .permissions, .about: CGSize(width: 340, height: 30)
        case .meeting, .nextEvent: CGSize(width: 404, height: 30)
        case .message, .lyrics: CGSize(width: 372, height: 88)
        case .screenshot, .shelf, .clipboard, .shortcuts, .timerPanel: CGSize(width: 404, height: 112)
        case .dashboard: CGSize(width: 452, height: 124)
        }
    }

    var isOpen: Bool { size.height > 30 }
}

/// The top of a Mac display running islo.: the Settings window's own top
/// edge is the screen's, so the notch hangs from it and acts out whatever
/// is being set up below.
private struct SettingsStage: View {
    let demo: StageDemo
    let caption: String
    let accent: Color
    let tone: SurfaceTone
    let language: AppLanguage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let fillet: CGFloat = 8

    var body: some View {
        ZStack(alignment: .top) {
            wallpaper
            desktopWindows
            menuBar
            notch
        }
        .overlay(alignment: .bottomLeading) { captionChip }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(caption))
    }

    private var wallpaper: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.06, blue: 0.16), Color(red: 0.1, green: 0.05, blue: 0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(colors: [accent.opacity(0.8), .clear], center: UnitPoint(x: 0.14, y: 0.1), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Color(red: 0.95, green: 0.35, blue: 0.65).opacity(0.5), .clear], center: UnitPoint(x: 0.92, y: 1), startRadius: 0, endRadius: 380)
            RadialGradient(colors: [Color(red: 0.2, green: 0.8, blue: 1).opacity(0.22), .clear], center: UnitPoint(x: 0.62, y: 0.5), startRadius: 0, endRadius: 280)
        }
        .animation(.easeInOut(duration: 0.4), value: accent)
    }

    private var desktopWindows: some View {
        HStack(alignment: .top, spacing: 0) {
            glassWindow.frame(width: 210, height: 150).offset(y: 96)
            Spacer()
            glassWindow.frame(width: 190, height: 150).offset(y: 78)
        }
        .padding(.horizontal, 64)
    }

    private var glassWindow: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            .overlay(alignment: .topLeading) {
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(Color.white.opacity(0.22)).frame(width: 7, height: 7)
                    }
                }
                .padding(10)
            }
    }

    /// The real window buttons sit at its left end.
    private var menuBar: some View {
        HStack(spacing: 14) {
            Text("islo.").font(.system(size: 12, weight: .bold))
            Text(language.value(turkish: "Ayarlar", english: "Settings"))
                .font(.system(size: 12, weight: .medium))
                .opacity(0.8)
            Spacer()
            Image(systemName: "battery.75percent").font(.system(size: 12))
            Image(systemName: "wifi").font(.system(size: 11, weight: .semibold))
            TimelineView(.everyMinute) { context in
                Text(context.date, style: .time).font(.system(size: 12, weight: .medium))
            }
        }
        .foregroundStyle(.white)
        .padding(.leading, 78)
        .padding(.trailing, 16)
        .frame(height: 30)
        .background(Color.black.opacity(0.22))
    }

    private var notch: some View {
        let size = demo.size
        let radius: CGFloat = demo.isOpen ? 24 : 11
        let shape = SettingsNotchShape(fillet: fillet, bottomRadius: radius)
        return ZStack(alignment: .top) {
            shape
                .fill(Color.white)
                .blur(radius: 14)
                .opacity(demo == .off ? 0 : 0.2)
            shape
                .fill(Color.black)
                .overlay {
                    if demo == .dashboard {
                        LinearGradient(
                            colors: [accent.opacity(tone.tintOpacity), accent.opacity(tone.tintOpacity * 0.3), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .mask {
                            LinearGradient(
                                stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.22), .init(color: .black, location: 0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        .clipShape(shape)
                    }
                }
            StageDemoContent(demo: demo, accent: accent, language: language)
                .frame(width: size.width, height: size.height)
                .clipShape(SettingsNotchShape(fillet: 0, bottomRadius: radius))
                .id(demo)
                .transition(.opacity.animation(.easeOut(duration: 0.16)))
        }
        .frame(width: size.width + fillet * 2, height: size.height)
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.42, dampingFraction: 0.76),
            value: demo
        )
        .animation(.easeInOut(duration: 0.25), value: tone)
    }

    private var captionChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(demo == .off ? Color.white.opacity(0.4) : Color.green)
                .frame(width: 6, height: 6)
            Text(caption)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Capsule().fill(Color.black.opacity(0.32)))
        .padding(.leading, 18)
        .padding(.bottom, 16)
    }
}

/// The notch outline: concave top corners, straight sides, round bottom.
private struct SettingsNotchShape: Shape {
    var fillet: CGFloat
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let f = fillet
        let r = min(bottomRadius, rect.height / 2, (rect.width - 2 * f) / 2)
        let left = rect.minX + f
        let right = rect.maxX - f
        let bottom = rect.maxY
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: left, y: rect.minY + f), control: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: left, y: bottom - r))
        path.addQuadCurve(to: CGPoint(x: left + r, y: bottom), control: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: right - r, y: bottom))
        path.addQuadCurve(to: CGPoint(x: right, y: bottom - r), control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: right, y: rect.minY + f))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: right, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// What's drawn inside the stage notch for each demo. Closed demos put
/// their marks in the wings beside the camera; open ones hang below it.
private struct StageDemoContent: View {
    let demo: StageDemo
    let accent: Color
    let language: AppLanguage

    var body: some View {
        Group {
            switch demo {
            case .off:
                Color.clear
            case .music:
                wings {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(LinearGradient(colors: [accent, Color(red: 1, green: 0.5, blue: 0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 18, height: 18)
                } trailing: {
                    StageBars(color: accent)
                }
            case .awake:
                wings {
                    Image(systemName: "cup.and.saucer.fill").foregroundStyle(Color(red: 0.85, green: 0.68, blue: 0.48))
                } trailing: {
                    label(t("Uyanık", "Awake"))
                }
            case .privacy:
                wings {
                    Image(systemName: "video.fill").foregroundStyle(.white.opacity(0.85))
                } trailing: {
                    HStack(spacing: 5) {
                        Circle().fill(Color.green).frame(width: 7, height: 7)
                        Circle().fill(Color.orange).frame(width: 7, height: 7)
                    }
                }
            case .messageCount:
                wings {
                    Image(systemName: "bell.fill").foregroundStyle(accent)
                } trailing: {
                    label(t("1 yeni bildirim", "1 new notification"))
                }
            case .charging:
                wings {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill").foregroundStyle(Color.green)
                        label(t("Şarj oluyor", "Charging"))
                    }
                } trailing: {
                    label("%64", tint: .green, digits: true)
                }
            case .download:
                wings {
                    HStack(spacing: 6) {
                        ring(0.62, color: .green, symbol: "arrow.down")
                        label("islo.dmg")
                    }
                } trailing: {
                    label("%62", tint: .green, digits: true)
                }
            case .timer:
                wings {
                    ring(0.7, color: accent, symbol: "timer")
                } trailing: {
                    StageCountdown(color: .white)
                }
            case .volume:
                wings {
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(.white.opacity(0.9))
                } trailing: {
                    StageLevel(color: .white)
                }
            case .weather(let rain):
                wings {
                    HStack(spacing: 6) {
                        Image(systemName: rain ? "cloud.rain.fill" : "cloud.sun.fill").symbolRenderingMode(.multicolor)
                        label("17°", digits: true)
                    }
                } trailing: {
                    if rain {
                        label(t("20 dk sonra yağmur", "Rain in 20 min"), tint: Color(red: 0.45, green: 0.72, blue: 1))
                    } else {
                        label(t("Parçalı bulutlu", "Partly cloudy"))
                    }
                }
            case .permissions(let missing):
                wings {
                    Image(systemName: missing > 0 ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                        .foregroundStyle(missing > 0 ? Color.orange : Color.green)
                } trailing: {
                    label(missing > 0 ? t("\(missing) izin eksik", "\(missing) missing") : t("Her şey hazır", "All set"))
                }
            case .about(let version):
                wings {
                    Text("islo.").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white)
                } trailing: {
                    label(version, digits: true)
                }
            case .meeting:
                wings {
                    HStack(spacing: 6) {
                        Capsule().fill(Color(red: 1, green: 0.36, blue: 0.58)).frame(width: 3, height: 14)
                        label(t("Tasarım toplantısı", "Design sync"))
                    }
                } trailing: {
                    HStack(spacing: 7) {
                        label(t("5 dk", "5 min"), digits: true)
                        Text(t("Katıl", "Join"))
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .frame(height: 18)
                            .background(Capsule().fill(Color.green.opacity(0.9)))
                    }
                }
            case .nextEvent:
                wings {
                    Image(systemName: "calendar").foregroundStyle(Color(red: 1, green: 0.36, blue: 0.58))
                } trailing: {
                    label(t("Sıradaki 14:30", "Next at 2:30 PM"), digits: true)
                }
            case .message:
                below {
                    HStack(spacing: 11) {
                        appMark("message.fill", [Color(red: 0.25, green: 0.85, blue: 0.4), Color(red: 0.1, green: 0.65, blue: 0.3)], size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Ahmet").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                                Text(t("şimdi", "now")).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                            }
                            Text(t("Akşam geliyor musun?", "Coming tonight?"))
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.72))
                        }
                        Spacer(minLength: 0)
                    }
                }
            case .lyrics:
                below {
                    HStack(spacing: 11) {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(LinearGradient(colors: [accent, Color(red: 1, green: 0.5, blue: 0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 36, height: 36)
                            .overlay(Image(systemName: "music.note").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t("Sözler şarkıyla birlikte akar", "Lyrics move with the song"))
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(t("sıradaki satır burada bekler", "the next line waits here"))
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        Spacer(minLength: 0)
                    }
                }
            case .screenshot:
                below {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LinearGradient(colors: [accent.opacity(0.9), Color(red: 0.95, green: 0.35, blue: 0.65).opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                            .frame(width: 96, height: 60)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(t("Ekran görüntüsü", "Screenshot")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                            HStack(spacing: 5) {
                                chip(t("Kopyala", "Copy"), filled: true)
                                chip(t("Rafa ekle", "Shelf"))
                                chip(t("Göster", "Show"))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            case .shelf:
                below {
                    HStack(spacing: 8) {
                        fileTile("doc.fill", "Rapor.pdf", Color(red: 1, green: 0.4, blue: 0.35))
                        fileTile("photo.fill", "Kapak.png", Color(red: 0.3, green: 0.75, blue: 1))
                        fileTile("tablecells.fill", "Bütçe.xlsx", Color(red: 0.25, green: 0.8, blue: 0.5))
                        fileTile("dot.radiowaves.left.and.right", "AirDrop", accent, dashed: true)
                    }
                }
            case .clipboard:
                below {
                    VStack(spacing: 6) {
                        clipRow("link", "islo.app/indir", "Safari")
                        clipRow("text.alignleft", t("Toplantı notları, salı 14:30", "Meeting notes, Tue 2:30 PM"), t("Notlar", "Notes"))
                    }
                }
            case .shortcuts:
                below {
                    HStack(spacing: 8) {
                        shortcutTile(t("Sabah Özeti", "Morning Brief"), Color(red: 0.2, green: 0.72, blue: 0.9))
                        shortcutTile(t("Mola Ver", "Take a Break"), Color(red: 0.25, green: 0.78, blue: 0.55))
                        shortcutTile(t("Odak Modu", "Focus Mode"), Color(red: 0.62, green: 0.42, blue: 0.98))
                    }
                }
            case .timerPanel:
                below {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.14), lineWidth: 5)
                            Circle().trim(from: 0, to: 0.7).stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                            StageCountdown(color: .white, size: 12)
                        }
                        .frame(width: 60, height: 60)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Pomodoro").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                            Text(t("Odak · 25 dk, mola · 5 dk", "Focus 25 min, break 5 min"))
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer(minLength: 0)
                    }
                }
            case .dashboard:
                below(top: 34) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Label(t("Ana", "Home"), systemImage: "house.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 9)
                                .frame(height: 22)
                                .background(Capsule().fill(Color.white.opacity(0.16)))
                            ForEach(["bell.fill", "calendar", "timer", "tray.full.fill"], id: \.self) { symbol in
                                Image(systemName: symbol)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .frame(width: 22, height: 22)
                            }
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(accent.opacity(0.85))
                                .frame(width: 34, height: 34)
                                .overlay(Image(systemName: "music.note").foregroundStyle(.white))
                            VStack(alignment: .leading, spacing: 6) {
                                Capsule().fill(Color.white.opacity(0.85)).frame(width: 110, height: 6)
                                Capsule().fill(Color.white.opacity(0.35)).frame(width: 70, height: 5)
                            }
                            Spacer(minLength: 8)
                            StageBars(color: accent)
                            ring(0.68, color: accent, symbol: nil)
                        }
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .font(.system(size: 11.5, weight: .semibold))
    }

    private func t(_ turkish: String, _ english: String) -> String {
        language.value(turkish: turkish, english: english)
    }

    /// Marks beside the camera housing of a closed notch.
    private func wings<Leading: View, Trailing: View>(
        @ViewBuilder _ leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 0) {
            leading()
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Content of an open notch, below the camera band.
    private func below<Content: View>(top: CGFloat = 30, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.top, top)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func label(_ string: String, tint: Color = .white, digits: Bool = false) -> some View {
        Text(string)
            .font(digits ? .system(size: 11.5, weight: .semibold).monospacedDigit() : .system(size: 11.5, weight: .semibold))
            .foregroundStyle(tint.opacity(0.92))
            .lineLimit(1)
            .fixedSize()
    }

    private func ring(_ fraction: Double, color: Color, symbol: String?) -> some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.16), lineWidth: 2.5)
            Circle().trim(from: 0, to: fraction).stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
            if let symbol {
                Image(systemName: symbol).font(.system(size: 8, weight: .bold)).foregroundStyle(color)
            }
        }
        .frame(width: 19, height: 19)
    }

    private func appMark(_ symbol: String, _ colors: [Color], size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.46, weight: .semibold)).foregroundStyle(.white))
    }

    private func chip(_ title: String, filled: Bool = false) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(filled ? Color.black : Color.white.opacity(0.85))
            .padding(.horizontal, 9)
            .frame(height: 21)
            .background(Capsule().fill(filled ? Color.white : Color.white.opacity(0.12)))
            .fixedSize()
    }

    private func fileTile(_ symbol: String, _ name: String, _ tint: Color, dashed: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        return VStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(tint)
            Text(name).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .background(shape.fill(Color.white.opacity(dashed ? 0 : 0.08)))
        .overlay(shape.strokeBorder(Color.white.opacity(dashed ? 0.28 : 0), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    private func clipRow(_ symbol: String, _ value: String, _ source: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(accent).frame(width: 16)
            Text(value).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
            Spacer(minLength: 6)
            Text(source).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 10)
        .frame(height: 29)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.08)))
    }

    private func shortcutTile(_ name: String, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [tint, tint.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 26, height: 26)
                .overlay(Image(systemName: "bolt.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.white))
            Text(name).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
    }
}

/// Four bars that move like the notch's playback mark.
private struct StageBars: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<4, id: \.self) { index in
                    let wave = (sin(phase * 5.2 + Double(index) * 1.25) + 1) / 2
                    Capsule().fill(color).frame(width: 2.5, height: 5 + 10 * wave)
                }
            }
            .frame(height: 16)
        }
    }
}

/// A volume bar that steps up and down, as if the keys were pressed.
private struct StageLevel: View {
    let color: Color
    @State private var level: CGFloat = 0.35

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(color.opacity(0.2))
            Capsule().fill(color).frame(width: 96 * level)
        }
        .frame(width: 96, height: 5)
        .task {
            let steps: [CGFloat] = [0.5, 0.65, 0.8, 0.65, 0.45, 0.35]
            var index = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.9))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.22)) { level = steps[index % steps.count] }
                index += 1
            }
        }
    }
}

/// A countdown that really counts, restarting when it runs out.
private struct StageCountdown: View {
    let color: Color
    var size: CGFloat = 11.5
    @State private var start = Date()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = Int(context.date.timeIntervalSince(start)) % (25 * 60)
            let left = 25 * 60 - 1 - elapsed
            Text(String(format: "%02d:%02d", left / 60, left % 60))
                .font(.system(size: size, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
        }
    }
}
