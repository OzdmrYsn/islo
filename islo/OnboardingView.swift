import AppKit
import SwiftUI

extension Notification.Name {
    /// Moves the welcome guide to a page (debug and tests).
    static let isloOnboardingPage = Notification.Name("com.ozdmrysn.islo.onboarding.page")
}

/// The welcome guide: the top of a MacBook display, where islo. comes to
/// life and shows what it does, above five short pages.
struct OnboardingView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var updateManager = UpdateManager.shared
    @ObservedObject private var calendarManager = CalendarManager.shared
    let onComplete: () -> Void

    enum Page: Int, CaseIterable { case hello, glance, style, privacy, ready }

    @State private var page: Page = .hello
    @State private var scene: StageScene = .sleep
    @State private var demo = 0
    @State private var demoRestart = 0
    @State private var revealed = 0
    @State private var isFinishing = false

    var body: some View {
        ZStack {
            IsloWindowBackground(accent: accent, tone: settings.surfaceTone)
            RadialGradient(colors: [accent.opacity(0.22), .clear], center: UnitPoint(x: 0.5, y: 0.08), startRadius: 0, endRadius: 420)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: settings.accentTheme)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    ChipPicker(selection: $settings.language, options: AppLanguage.allCases.map { ($0, $0.title) }, accent: accent)
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .frame(height: 44)

                NotchStage(scene: scene, accent: accent, tone: settings.surfaceTone, language: settings.language)
                    .frame(width: 700, height: 236)

                ZStack {
                    pageBody
                        .id(page)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 16)),
                            removal: .opacity.combined(with: .offset(y: -8))
                        ))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
        }
        .frame(minWidth: 1040, maxWidth: .infinity, minHeight: 680, maxHeight: .infinity)
        .ignoresSafeArea()
        .foregroundStyle(IsloStyle.text)
        .preferredColorScheme(.dark)
        .tint(accent)
        .task(id: "\(page.rawValue)-\(demoRestart)") { await playScenes() }
        .onReceive(NotificationCenter.default.publisher(for: .isloOnboardingPage)) { note in
            if let index = note.object as? Int, let target = Page(rawValue: index) { go(to: target) }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if page == .privacy { settings.refreshPermissionState() }
        }
    }

    // MARK: Pages

    @ViewBuilder private var pageBody: some View {
        switch page {
        case .hello: helloPage
        case .glance: glancePage
        case .style: stylePage
        case .privacy: privacyPage
        case .ready: readyPage
        }
    }

    private var helloPage: some View {
        VStack(spacing: 14) {
            Text(greeting)
                .font(.system(size: 50, weight: .bold))
                .tracking(-1.6)
                .opacity(revealed >= 1 ? 1 : 0)
                .offset(y: revealed >= 1 ? 0 : 18)
            headline(text("Çentiğin artık ", "Your notch has "), text("bir işi var.", "a job now."))
                .opacity(revealed >= 2 ? 1 : 0)
                .offset(y: revealed >= 2 ? 0 : 18)
            Text(text("islo., MacBook'unun çentiğini müziğe, mesajlara, dosyalara ve gününe açılan canlı bir adaya dönüştürür.", "islo. turns your MacBook's notch into a living island for your music, messages, files and day."))
                .font(.system(size: 15.5))
                .foregroundStyle(IsloStyle.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
                .padding(.top, 4)
                .opacity(revealed >= 3 ? 1 : 0)
        }
        .frame(maxHeight: .infinity)
        .offset(y: -6)
    }

    private var glancePage: some View {
        VStack(spacing: 14) {
            headline(text("Her şey, ", "Everything, "), text("tam yerinde.", "right where you look."))
            Text(text("Haber verdiği her şey çentikte belirir, işini bölmeden kaybolur.", "Everything it tells you appears in the notch, then gets out of your way."))
                .font(.system(size: 15))
                .foregroundStyle(IsloStyle.muted)
            HStack(spacing: 10) {
                ForEach(Array(GlanceDemo.all.enumerated()), id: \.offset) { index, item in
                    glanceChip(item, isCurrent: index == demo) {
                        demo = index
                        demoRestart += 1
                    }
                }
            }
            .padding(.top, 12)
        }
        .frame(maxHeight: .infinity)
        .offset(y: -6)
    }

    private func glanceChip(_ item: GlanceDemo, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 9) {
                IconTile(symbol: item.symbol, colors: item.colors, size: 34, isOn: isCurrent)
                Text(text(item.title.tr, item.title.en))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isCurrent ? IsloStyle.text : IsloStyle.muted)
                    .lineLimit(1)
            }
            .frame(width: 128, height: 92)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isCurrent ? 0.09 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isCurrent ? accent.opacity(0.75) : IsloStyle.line, lineWidth: isCurrent ? 1.5 : 1)
            )
            .scaleEffect(isCurrent ? 1.04 : 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isCurrent)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private var stylePage: some View {
        VStack(spacing: 18) {
            headline(text("Senin rengin, ", "Your colour, "), text("senin tonun.", "your tone."))
            AccentSwatchPicker(selection: $settings.accentTheme, language: settings.language)
                .padding(.top, 4)
            labeled(text("Ton", "Tone")) {
                ChipPicker(selection: $settings.surfaceTone, options: SurfaceTone.allCases.map { ($0, $0.title(language: settings.language)) }, accent: accent)
            }
            Text(text("Ton, rengin açılan çentiğe ne kadar sineceğini belirler.", "Tone sets how much the colour tints the open notch."))
                .font(.system(size: 12.5))
                .foregroundStyle(IsloStyle.faint)
        }
        .frame(maxHeight: .infinity)
        .offset(y: -6)
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 8) {
            Text(title.uppercased(with: Locale(identifier: settings.language == .turkish ? "tr_TR" : "en_US")))
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(1)
                .foregroundStyle(IsloStyle.faint)
            content()
        }
    }

    private var privacyPage: some View {
        VStack(spacing: 18) {
            headline(text("İzinler, ", "Permissions, "), text("yalnızca gerektiği kadar.", "only what it needs."))
            HStack(alignment: .top, spacing: 14) {
                permissionCard(
                    symbol: "hand.raised.fill", colors: Tint.blue,
                    title: text("Erişilebilirlik", "Accessibility"),
                    detail: text("Bildirimleri çentikte göstermek ve macOS'un ses ve parlaklık göstergesinin yerine geçmek için.", "To show notifications in the notch and stand in for macOS's volume and brightness indicator."),
                    state: settings.isAccessibilityTrusted ? .granted : .missing,
                    action: settings.requestAccessibilityPermission
                )
                permissionCard(
                    symbol: "calendar", colors: Tint.pink,
                    title: text("Takvim", "Calendar"),
                    detail: text("Sıradaki toplantını göstermek ve 5 dakika önce haber vermek için. İsteğe bağlı.", "To show your next meeting and give you a heads-up 5 minutes before. Optional."),
                    state: calendarManager.authorization,
                    action: calendarManager.authorization == .missing ? calendarManager.openPrivacySettings : calendarManager.requestAccess
                )
                permissionCard(
                    symbol: "lock.shield.fill", colors: Tint.green,
                    title: text("Gizlilik", "Privacy"),
                    detail: text("Hesap yok, izleme yok. Bildirimlerin, panon ve dosyaların Mac'inden çıkmaz.", "No account, no tracking. Your notifications, clipboard and files never leave your Mac."),
                    state: nil,
                    action: nil
                )
            }
        }
        .frame(maxHeight: .infinity)
        .offset(y: -6)
    }

    private func permissionCard(symbol: String, colors: [Color], title: String, detail: String, state: PermissionState?, action: (() -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                IconTile(symbol: symbol, colors: colors, size: 32)
                Spacer()
                if let state { badge(state) }
            }
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(IsloStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let state, let action, state != .granted {
                Button(state == .missing ? text("Ayarları aç", "Open Settings") : text("İzin ver", "Allow"), action: action)
                    .buttonStyle(IsloButtonStyle(prominent: true, accent: accent))
            }
        }
        .padding(16)
        .frame(width: 290, height: 176, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: IsloStyle.cardRadius, style: .continuous).fill(IsloStyle.cardFill)
                .overlay(RoundedRectangle(cornerRadius: IsloStyle.cardRadius, style: .continuous).strokeBorder(IsloStyle.line, lineWidth: 1))
        )
    }

    private func badge(_ state: PermissionState) -> some View {
        let style: (String, String, Color) = switch state {
        case .granted: (text("Verildi", "Allowed"), "checkmark.circle.fill", .green)
        case .missing: (text("Kapalı", "Off"), "exclamationmark.triangle.fill", .orange)
        default: (text("Bekliyor", "Not yet"), "circle.dashed", IsloStyle.muted)
        }
        return Label(style.0, systemImage: style.1)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(style.2)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill(style.2.opacity(0.14)))
    }

    private var readyPage: some View {
        VStack(spacing: 16) {
            headline("islo. ", text("hazır.", "is ready."))
            if settings.hotKeyEnabled {
                VStack(spacing: 10) {
                    Text(text("Çentiği istediğin an aç", "Open the notch whenever you like"))
                        .font(.system(size: 13.5))
                        .foregroundStyle(IsloStyle.muted)
                    Keycaps(label: settings.toggleHotKey.displayString, accent: accent)
                }
            }
            HStack(spacing: 12) {
                toggleCard(symbol: "power", colors: Tint.green, title: text("Mac açılınca başlat", "Launch at login"), isOn: launchAtLoginBinding)
                toggleCard(symbol: "arrow.triangle.2.circlepath", colors: Tint.teal, title: text("Otomatik güncelle", "Update automatically"), isOn: automaticUpdatesBinding)
            }
            .padding(.top, 6)
        }
        .frame(maxHeight: .infinity)
        .offset(y: -6)
    }

    private func toggleCard(symbol: String, colors: [Color], title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, colors: colors, size: 28)
            Text(title).font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 10)
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(accent)
        }
        .padding(.horizontal, 14)
        .frame(width: 280, height: 52)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(IsloStyle.cardFill)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(IsloStyle.line, lineWidth: 1))
        )
    }

    /// A bold line with an italic serif ending, like the website.
    private func headline(_ plain: String, _ flourish: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(plain)
                .font(.system(size: 40, weight: .bold))
                .tracking(-1.1)
            Text(flourish)
                .font(.system(size: 44, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(LinearGradient(colors: [Color(red: 0.62, green: 0.76, blue: 1), Color(red: 0.75, green: 0.64, blue: 1), Color(red: 1, green: 0.62, blue: 0.84)], startPoint: .leading, endPoint: .trailing))
        }
        .fixedSize()
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(Page.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item == page ? accent : Color.white.opacity(item.rawValue < page.rawValue ? 0.4 : 0.16))
                        .frame(width: item == page ? 22 : 7, height: 7)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: page)
            Spacer()
            if page != .hello, page != .ready {
                Button(text("Atla", "Skip")) { go(to: .ready) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(IsloStyle.faint)
                    .padding(.trailing, 4)
            }
            if page != .hello {
                Button(text("Geri", "Back")) { go(to: Page(rawValue: page.rawValue - 1) ?? .hello) }
                    .buttonStyle(IsloButtonStyle(accent: accent))
                    .keyboardShortcut(.leftArrow, modifiers: [])
            }
            Button(primaryTitle) {
                if page == .ready { finish() } else { go(to: Page(rawValue: page.rawValue + 1) ?? .ready) }
            }
            .buttonStyle(HeroButtonStyle(accent: accent))
            .keyboardShortcut(.defaultAction)
            .disabled(isFinishing)
        }
        .padding(.horizontal, 34)
        .padding(.bottom, 28)
        .frame(height: 84, alignment: .bottom)
    }

    private var primaryTitle: String {
        switch page {
        case .hello: text("Başlayalım", "Let's go")
        case .ready: text("islo.'yu başlat", "Start islo.")
        default: text("Devam", "Continue")
        }
    }

    // MARK: Flow

    private func go(to target: Page) {
        guard target != page, !isFinishing else { return }
        withAnimation(.easeOut(duration: 0.35)) { page = target }
    }

    /// What the stage plays on each page.
    private func playScenes() async {
        switch page {
        case .hello:
            if scene == .sleep {
                revealed = 0
                // Each step checks it's still wanted: leaving the page
                // cancels the task but not a step already under way.
                guard await pause(0.45) else { return }
                withAnimation(stageSpring) { scene = .wake }
                guard await pause(0.9) else { return }
                withAnimation(stageSpring) { scene = .music }
                for step in 1...3 {
                    guard await pause(step == 1 ? 0.15 : 0.3) else { return }
                    withAnimation(.easeOut(duration: 0.55)) { revealed = step }
                }
            } else {
                withAnimation(stageSpring) { scene = .music }
                withAnimation(.easeOut(duration: 0.4)) { revealed = 3 }
            }
        case .glance:
            while !Task.isCancelled {
                withAnimation(stageSpring) { scene = GlanceDemo.all[demo].scene }
                guard await pause(2.8) else { return }
                demo = (demo + 1) % GlanceDemo.all.count
            }
        case .style:
            withAnimation(stageSpring) { scene = .dashboard }
        case .privacy:
            var showMessage = true
            while !Task.isCancelled {
                withAnimation(stageSpring) { scene = showMessage ? .message : .volume }
                showMessage.toggle()
                guard await pause(2.6) else { return }
            }
        case .ready:
            withAnimation(stageSpring) { scene = .ready }
        }
    }

    /// The surprise: a burst on the stage, then the window flies into the
    /// real notch, which opens to say hello.
    private func finish() {
        guard !isFinishing else { return }
        isFinishing = true
        withAnimation(stageSpring) { scene = .launch }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            settings.completeOnboarding()
            onComplete()
        }
    }

    /// Waits; false when the page was left meanwhile.
    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        return !Task.isCancelled
    }

    private var stageSpring: Animation { .spring(response: 0.5, dampingFraction: 0.78) }
    private var greeting: String {
        let first = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? text("Merhaba.", "Hello.") : text("Merhaba, \(first).", "Hello, \(first).")
    }
    private func text(_ tr: String, _ en: String) -> String { settings.language.value(turkish: tr, english: en) }
    private var accent: Color { settings.accentTheme.color }
    private var launchAtLoginBinding: Binding<Bool> { Binding(get: { settings.launchAtLogin }, set: settings.setLaunchAtLogin) }
    private var automaticUpdatesBinding: Binding<Bool> { Binding(get: { updateManager.automaticUpdatesEnabled }, set: updateManager.setAutomaticUpdates) }
}

/// One of the moments the "At a glance" page plays.
private struct GlanceDemo {
    let scene: StageScene
    let symbol: String
    let colors: [Color]
    let title: (tr: String, en: String)

    static let all: [GlanceDemo] = [
        GlanceDemo(scene: .message, symbol: "bell.badge.fill", colors: Tint.red, title: ("Mesajlar", "Messages")),
        GlanceDemo(scene: .volume, symbol: "speaker.wave.2.fill", colors: Tint.indigo, title: ("Ses ve parlaklık", "Volume")),
        GlanceDemo(scene: .screenshot, symbol: "camera.viewfinder", colors: Tint.purple, title: ("Ekran görüntüsü", "Screenshots")),
        GlanceDemo(scene: .download, symbol: "arrow.down.circle.fill", colors: Tint.mint, title: ("İndirmeler", "Downloads")),
        GlanceDemo(scene: .timesUp, symbol: "timer", colors: Tint.orange, title: ("Zamanlayıcı", "Timer")),
        GlanceDemo(scene: .meeting, symbol: "calendar", colors: Tint.pink, title: ("Toplantılar", "Meetings")),
    ]
}

/// The big button that moves the guide along.
private struct HeroButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(height: 40)
            .background(
                Capsule().fill(LinearGradient(colors: [accent.opacity(0.95), accent], startPoint: .top, endPoint: .bottom))
                    .shadow(color: accent.opacity(configuration.isPressed ? 0.2 : 0.45), radius: 14, y: 4)
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// The shortcut as keyboard keys, pressing themselves now and then.
private struct Keycaps: View {
    let label: String
    let accent: Color

    var body: some View {
        let keys = Self.split(label)
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let cycle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4)
            HStack(spacing: 10) {
                ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                    let start = 0.2 + Double(index) * 0.08
                    let pressed = cycle > start && cycle < start + 0.45
                    Text(key)
                        .font(.system(size: key.count > 1 ? 18 : 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(minWidth: key.count > 1 ? 150 : 58)
                        .frame(height: 58)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.11)], startPoint: .top, endPoint: .bottom))
                                .shadow(color: pressed ? accent.opacity(0.6) : .black.opacity(0.5), radius: pressed ? 14 : 8, y: pressed ? 1 : 5)
                        )
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(pressed ? accent.opacity(0.8) : Color.white.opacity(0.1), lineWidth: 1))
                        .offset(y: pressed ? 3 : 0)
                        .animation(.easeOut(duration: 0.12), value: pressed)
                }
            }
        }
        .accessibilityLabel(Text(label))
    }

    /// "⌥⇧Space" → ["⌥", "⇧", "Space"].
    static func split(_ label: String) -> [String] {
        let modifiers: Set<Character> = ["⌘", "⌥", "⌃", "⇧"]
        var keys: [String] = []
        var rest = ""
        for character in label {
            if modifiers.contains(character), rest.isEmpty { keys.append(String(character)) } else { rest.append(character) }
        }
        if !rest.isEmpty { keys.append(rest) }
        return keys
    }
}

// MARK: - The stage

/// What the islo. notch on the stage is showing.
enum StageScene: Equatable {
    case sleep, wake, music, message, volume, screenshot, download, timesUp, meeting, dashboard, ready, launch

    /// The notch's size, not counting the concave top corners.
    var size: CGSize {
        switch self {
        case .sleep, .wake: CGSize(width: 150, height: 30)
        case .music, .download: CGSize(width: 262, height: 30)
        case .message: CGSize(width: 384, height: 88)
        case .volume: CGSize(width: 340, height: 30)
        case .screenshot: CGSize(width: 440, height: 112)
        case .timesUp: CGSize(width: 366, height: 30)
        case .meeting: CGSize(width: 410, height: 30)
        case .dashboard: CGSize(width: 480, height: 162)
        case .ready: CGSize(width: 352, height: 30)
        case .launch: CGSize(width: 372, height: 30)
        }
    }

    var glow: Double {
        switch self {
        case .sleep: 0
        case .wake, .ready, .launch: 0.75
        default: 0.22
        }
    }
}

/// The top of a MacBook display with islo. in the notch.
private struct NotchStage: View {
    let scene: StageScene
    let accent: Color
    let tone: SurfaceTone
    let language: AppLanguage

    private let fillet: CGFloat = 8

    var body: some View {
        ZStack(alignment: .top) {
            // Bezel and screen.
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color(white: 0.03))
                .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
                .frame(height: 320)
            screen
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .frame(height: 320, alignment: .top)
        }
        .frame(height: 236, alignment: .top)
        .clipped()
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
        .shadow(color: accent.opacity(0.18), radius: 40, y: 10)
        .accessibilityHidden(true)
    }

    private var screen: some View {
        ZStack(alignment: .top) {
            wallpaper
            desktopWindows
            menuBar
            islo
        }
    }

    private var wallpaper: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.16), Color(red: 0.1, green: 0.05, blue: 0.2)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [accent.opacity(0.75), .clear], center: UnitPoint(x: 0.18, y: 0.15), startRadius: 0, endRadius: 330)
            RadialGradient(colors: [Color(red: 0.95, green: 0.35, blue: 0.65).opacity(0.5), .clear], center: UnitPoint(x: 0.9, y: 0.95), startRadius: 0, endRadius: 330)
            RadialGradient(colors: [Color(red: 0.2, green: 0.8, blue: 1).opacity(0.25), .clear], center: UnitPoint(x: 0.6, y: 0.4), startRadius: 0, endRadius: 260)
        }
        .animation(.easeInOut(duration: 0.4), value: accent)
    }

    private var desktopWindows: some View {
        ZStack(alignment: .topLeading) {
            glassWindow.frame(width: 250, height: 170).offset(x: 54, y: 96)
            glassWindow.frame(width: 230, height: 150).offset(x: 392, y: 118)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var glassWindow: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            .overlay(alignment: .topLeading) {
                HStack(spacing: 5) {
                    Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 7, height: 7)
                    Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 7, height: 7)
                    Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: 7, height: 7)
                }
                .padding(10)
            }
    }

    private var menuBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "apple.logo").font(.system(size: 11, weight: .semibold))
            Text("islo.").font(.system(size: 11, weight: .bold))
            Spacer()
            Image(systemName: "battery.75percent").font(.system(size: 11))
            Image(systemName: "wifi").font(.system(size: 10.5, weight: .semibold))
            Text(language == .turkish ? "Cmt 09:41" : "Sat 9:41 AM").font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: 26)
        .background(Color.black.opacity(0.22))
    }

    /// The notch: the camera housing grown into whatever islo. shows.
    private var islo: some View {
        let size = scene.size
        let radius: CGFloat = size.height > 30 ? 24 : 11
        let shape = StageNotchShape(fillet: fillet, bottomRadius: radius)
        return ZStack(alignment: .top) {
            // The white light around the notch.
            TimelineView(.animation(minimumInterval: 1 / 30, paused: scene != .wake)) { context in
                let pulse = scene == .wake ? 0.55 + 0.45 * sin(context.date.timeIntervalSinceReferenceDate * 3.2) : 1
                shape
                    .fill(Color.white)
                    .blur(radius: 14)
                    .opacity(scene.glow * pulse)
            }
            shape
                .fill(Color.black)
                .overlay {
                    if scene == .dashboard {
                        LinearGradient(colors: [accent.opacity(tone.tintOpacity), accent.opacity(tone.tintOpacity * 0.3), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                            .clipShape(shape)
                    }
                }
            StageContent(scene: scene, accent: accent, language: language)
                .frame(width: size.width, height: size.height)
                .clipShape(StageNotchShape(fillet: 0, bottomRadius: radius))
        }
        .frame(width: size.width + fillet * 2, height: size.height)
        // Outside the notch's own frame, so the stars never resize it.
        .overlay(alignment: .top) {
            if scene == .launch || scene == .ready {
                Sparkles(accent: accent, isBurst: scene == .launch)
                    .frame(width: size.width + 220, height: 120)
                    .id(scene)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// The notch outline: concave top corners, straight sides, round bottom.
private struct StageNotchShape: Shape, InsettableShape {
    var fillet: CGFloat
    var bottomRadius: CGFloat
    var insetAmount: CGFloat = 0

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func inset(by amount: CGFloat) -> StageNotchShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let f = fillet
        let r = min(bottomRadius, (rect.height) / 2, (rect.width - 2 * f) / 2)
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

/// What's drawn inside the stage notch for each scene.
private struct StageContent: View {
    let scene: StageScene
    let accent: Color
    let language: AppLanguage

    private let housing: CGFloat = 150

    var body: some View {
        content.foregroundStyle(.white)
    }

    @ViewBuilder private var content: some View {
        switch scene {
        case .sleep, .wake:
            Color.clear
        case .music:
            wings {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 1, green: 0.42, blue: 0.62), Color(red: 1, green: 0.66, blue: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 20, height: 20)
            } right: {
                Waveform(color: accent)
            }
        case .message:
            VStack(alignment: .leading, spacing: 0) {
                wings {
                    HStack(spacing: 6) {
                        appBadge("message.fill", Color(red: 0.2, green: 0.8, blue: 0.35))
                        Text(t("Mesajlar", "Messages")).font(.system(size: 11, weight: .semibold))
                    }
                } right: {
                    Text(t("şimdi", "now")).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ayşe").font(.system(size: 13.5, weight: .bold))
                    Text(t("Yarın akşam görüşelim mi? Mekânı ben ayarlarım.", "Dinner tomorrow? I'll book the place."))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                Spacer(minLength: 0)
            }
        case .volume:
            wings {
                Image(systemName: "speaker.wave.2.fill").font(.system(size: 12, weight: .semibold))
            } right: {
                HStack(spacing: 7) {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule().fill(accent).frame(width: 35)
                    }
                    .frame(width: 56, height: 4)
                    Text(verbatim: "62").font(.system(size: 11, weight: .semibold).monospacedDigit())
                }
            }
        case .screenshot:
            VStack(alignment: .leading, spacing: 0) {
                wings {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.viewfinder").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(red: 0.77, green: 0.42, blue: 0.96))
                        Text(t("Ekran görüntüsü", "Screenshot")).font(.system(size: 11, weight: .semibold))
                    }
                } right: {
                    Text(t("Sürükle, bırak", "Drag it anywhere")).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.45, blue: 1), Color(red: 0.95, green: 0.42, blue: 0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.92)).padding(.horizontal, 13).padding(.vertical, 11))
                        .frame(width: 78, height: 50)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(t("Ekran Resmi 09.41.png", "Screenshot 9.41.png")).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                        HStack(spacing: 5) {
                            chip("doc.on.doc", t("Kopyala", "Copy"))
                            chip("tray.and.arrow.down", t("Rafa ekle", "Shelf"))
                            chip("folder", t("Göster", "Show"))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer(minLength: 0)
            }
        case .download:
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                let cycle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.8)
                let progress = min(1, cycle / 2.3)
                wings {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.18), lineWidth: 2.5)
                        Circle().trim(from: 0, to: progress).stroke(Color(red: 0.2, green: 0.85, blue: 0.5), style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
                        Image(systemName: progress >= 1 ? "checkmark" : "arrow.down").font(.system(size: 7.5, weight: .heavy)).foregroundStyle(Color(red: 0.2, green: 0.85, blue: 0.5))
                    }
                    .frame(width: 17, height: 17)
                } right: {
                    Text(verbatim: "%\(Int(progress * 100))").font(.system(size: 11, weight: .semibold).monospacedDigit())
                }
            }
        case .timesUp:
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                wings {
                    HStack(spacing: 6) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(red: 1, green: 0.66, blue: 0.15))
                            .rotationEffect(.degrees(sin(t * 22) * 14 * max(0, sin(t * 2.4))), anchor: .top)
                        Text(self.t("Süre doldu", "Time's up")).font(.system(size: 11, weight: .bold))
                    }
                } right: {
                    Text(verbatim: "25:00").font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(Color(red: 1, green: 0.66, blue: 0.15))
                }
            }
        case .meeting:
            wings {
                HStack(spacing: 6) {
                    Image(systemName: "calendar").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(red: 1, green: 0.4, blue: 0.6))
                    Text(t("Tasarım · 5 dk", "Design · 5 min")).font(.system(size: 11, weight: .semibold))
                }
            } right: {
                Text(t("Katıl", "Join"))
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 18)
                    .background(Capsule().fill(Color(red: 0.2, green: 0.78, blue: 0.35)))
            }
        case .dashboard:
            VStack(spacing: 10) {
                wings {
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "house.fill").font(.system(size: 8.5, weight: .semibold))
                            Text(t("Ana", "Home")).font(.system(size: 9.5, weight: .semibold))
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 18)
                        .background(Capsule().fill(Color.white.opacity(0.16)))
                        ForEach(["bell", "calendar", "timer"], id: \.self) {
                            Image(systemName: $0).font(.system(size: 8.5, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                        }
                    }
                } right: {
                    HStack(spacing: 8) {
                        ForEach(["tray.full", "bolt.fill", "gearshape.fill"], id: \.self) {
                            Image(systemName: $0).font(.system(size: 8.5, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
                HStack(spacing: 8) {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(LinearGradient(colors: [accent, Color(red: 1, green: 0.45, blue: 0.62)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 50, height: 50)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t("Gece Yarısı Treni", "Midnight Train")).font(.system(size: 11.5, weight: .bold))
                            Text("Lofi Ensemble").font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.55))
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.18))
                                Capsule().fill(Color.white).frame(width: 52)
                            }
                            .frame(width: 130, height: 3)
                            .padding(.top, 3)
                            HStack(spacing: 14) {
                                Image(systemName: "backward.fill")
                                Image(systemName: "pause.fill").font(.system(size: 11, weight: .bold))
                                Image(systemName: "forward.fill")
                            }
                            .font(.system(size: 8.5, weight: .bold))
                            .padding(.top, 2)
                        }
                        Spacer(minLength: 0)
                        Waveform(color: accent).scaleEffect(0.9)
                    }
                    .padding(10)
                    .frame(width: 300, height: 92)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("CUMARTESİ", "SATURDAY")).font(.system(size: 7.5, weight: .bold)).tracking(0.6).foregroundStyle(Color(red: 1, green: 0.42, blue: 0.4))
                        Text(t("1 Kas", "Nov 1")).font(.system(size: 16, weight: .bold))
                        HStack(spacing: 5) {
                            Capsule().fill(Color(red: 0.7, green: 0.45, blue: 1)).frame(width: 3, height: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t("Tasarım", "Design")).font(.system(size: 9, weight: .semibold))
                                Text("13:00").font(.system(size: 8)).foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        .padding(.top, 2)
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(width: 140, height: 92, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
                }
                Spacer(minLength: 0)
            }
        case .ready, .launch:
            wings {
                MiniMark().frame(width: 16, height: 16)
            } right: {
                HStack(spacing: 5) {
                    Text(t("islo. hazır", "islo. is ready")).font(.system(size: 11, weight: .bold))
                    Image(systemName: "sparkles").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(red: 1, green: 0.8, blue: 0.4))
                }
            }
        }
    }

    /// Content either side of the camera housing, like the real notch.
    private func wings<Left: View, Right: View>(@ViewBuilder _ left: () -> Left, @ViewBuilder right: () -> Right) -> some View {
        HStack(spacing: 0) {
            left().fixedSize().frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 16)
            Color.clear.frame(width: housing)
            right().fixedSize().frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 16)
        }
        .foregroundStyle(.white)
        .frame(height: 30)
    }

    private func appBadge(_ symbol: String, _ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
            .fill(color)
            .frame(width: 16, height: 16)
            .overlay(Image(systemName: symbol).font(.system(size: 8, weight: .bold)).foregroundStyle(.white))
    }

    private func chip(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 8.5, weight: .semibold))
            Text(title).font(.system(size: 9.5, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Capsule().fill(Color.white.opacity(0.12)))
    }

    private func t(_ tr: String, _ en: String) -> String { language.value(turkish: tr, english: en) }
}

/// The app icon's "i." drawn small, in colour.
private struct MiniMark: View {
    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.height / 562
            ZStack(alignment: .topLeading) {
                Capsule().fill(Color(red: 0.36, green: 0.55, blue: 1))
                    .frame(width: 250 * s, height: 118 * s)
                    .offset(x: 0, y: 0)
                Capsule().fill(Color.white)
                    .frame(width: 150 * s, height: 390 * s)
                    .offset(x: 50 * s, y: 172 * s)
                Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.44, blue: 0.65), Color(red: 1, green: 0.6, blue: 0.24)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 150 * s, height: 150 * s)
                    .offset(x: 283 * s, y: 412 * s)
            }
            .frame(width: 433 * s, height: 562 * s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Bars that move like music.
private struct Waveform: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<5, id: \.self) { index in
                    let phase = t * (5 + Double(index) * 1.3) + Double(index) * 1.7
                    Capsule()
                        .fill(color)
                        .frame(width: 2.6, height: 5 + 10 * abs(sin(phase)))
                }
            }
            .frame(height: 16)
        }
    }
}

/// Little stars around the notch; a bigger burst when islo. starts.
private struct Sparkles: View {
    let accent: Color
    let isBurst: Bool
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            Canvas { canvas, size in
                let count = isBurst ? 26 : 10
                for index in 0..<count {
                    let seed = Double(index) * 12.9898
                    let angle = (seed.truncatingRemainder(dividingBy: 6.283))
                    let speed = 40 + (seed * 7).truncatingRemainder(dividingBy: 70)
                    let life = isBurst ? 1.2 : 2.4
                    let delay = isBurst ? 0 : Double(index) * 0.24
                    let age = (elapsed - delay).truncatingRemainder(dividingBy: isBurst ? 100 : life)
                    guard age > 0, age < life else { continue }
                    let progress = age / life
                    let distance = speed * (isBurst ? progress * 1.6 : progress)
                    let x = size.width / 2 + cos(angle) * (isBurst ? distance * 2.2 : 120 + distance * 0.5) * (index.isMultiple(of: 2) ? 1 : -1)
                    let y = 14 + abs(sin(angle)) * distance * 0.6
                    let scale = (1 - progress) * (isBurst ? 1.2 : 0.8)
                    let starSize = 7 * scale
                    var star = Path()
                    star.move(to: CGPoint(x: x, y: y - starSize))
                    star.addQuadCurve(to: CGPoint(x: x + starSize, y: y), control: CGPoint(x: x, y: y))
                    star.addQuadCurve(to: CGPoint(x: x, y: y + starSize), control: CGPoint(x: x, y: y))
                    star.addQuadCurve(to: CGPoint(x: x - starSize, y: y), control: CGPoint(x: x, y: y))
                    star.addQuadCurve(to: CGPoint(x: x, y: y - starSize), control: CGPoint(x: x, y: y))
                    let color = index % 3 == 0 ? Color(red: 1, green: 0.82, blue: 0.45) : (index % 3 == 1 ? Color.white : accent)
                    canvas.fill(star, with: .color(color.opacity(1 - progress * 0.6)))
                }
            }
        }
        .onAppear { start = Date() }
    }
}
