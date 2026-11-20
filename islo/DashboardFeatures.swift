import AppKit
import ApplicationServices
import Combine
import CoreAudio
import Darwin
import IOKit.graphics
import OSLog
import QuickLookThumbnailing
import UniformTypeIdentifiers

enum MediaSkipDirection: Equatable {
    case previous
    case next

    var symbolName: String { self == .previous ? "backward.fill" : "forward.fill" }
}

/// Which countdown just ran out, so the notch can say what comes next.
enum TimerFinish: Equatable {
    case timer
    case focusDone
    case breakDone
}

enum CommandEchoKind: Equatable {
    case timerFinished(TimerFinish)
    case upcomingEvent(CalendarEventInfo)
    case power(PowerEvent)
    case headphones(HeadphoneBattery)
    case privacy(PrivacyUsage)
    case screenshotPreview(ScreenshotCapture)
    case downloadFinished(FinishedDownload)
    case volume(Double)
    case brightness(Double)
    case copied
    case pasted
    case screenshot(String)
    case capsLock(Bool)
    case mediaSkip(MediaSkipDirection)
    case trackChanged(String, MediaSkipDirection?)
    case notification(CapturedNotification)
    /// A call or an AirDrop asking for an answer, with its buttons.
    case request(CapturedNotification)
    case rain(RainOutlook)
    case agentFinished(AgentSession)
    case agentWaiting(AgentSession)
    case agentPermission(AgentPermission)
    /// A new islo. version, by its number.
    case updateAvailable(String)

    var symbolName: String {
        switch self {
        case .volume(let value):
            value == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .brightness: "sun.max.fill"
        case .copied: "doc.on.doc.fill"
        case .pasted: "doc.on.clipboard.fill"
        case .screenshot: "camera.viewfinder"
        case .capsLock: "capslock.fill"
        case .mediaSkip(let direction): direction.symbolName
        case .trackChanged(_, let direction): direction?.symbolName ?? "music.note"
        case .notification: "bell.fill"
        case .request(let item): item.requestSymbolName
        case .rain: "cloud.rain.fill"
        case .agentFinished: "checkmark.circle.fill"
        case .agentWaiting: "hand.raised.fill"
        case .agentPermission: "lock.shield.fill"
        case .updateAvailable: "arrow.down.circle.fill"
        case .upcomingEvent: "calendar"
        case .power(let event):
            switch event {
            case .pluggedIn: "bolt.fill"
            case .unplugged: "battery.75"
            case .low: "battery.25"
            }
        case .headphones(let battery): battery.symbolName
        case .privacy(let usage): usage.camera ? "video.fill" : "mic.fill"
        case .screenshotPreview: "camera.viewfinder"
        case .downloadFinished(let download): download.isAirDrop ? "dot.radiowaves.left.and.right" : "arrow.down.circle.fill"
        case .timerFinished(let finish):
            switch finish {
            case .timer: "bell.fill"
            case .focusDone: "cup.and.saucer.fill"
            case .breakDone: "brain.head.profile"
            }
        }
    }

    /// Alerts that everyday echoes (volume, copy, Caps Lock, track changes)
    /// must not replace while they're on screen.
    var isImportant: Bool {
        switch self {
        // A call in progress steps aside for the volume keys and comes back.
        case .request(let item): !item.isOngoingCall
        case .notification, .upcomingEvent, .timerFinished, .headphones, .privacy, .power,
             .screenshotPreview, .downloadFinished, .rain, .agentFinished, .agentWaiting, .agentPermission, .updateAvailable: true
        case .volume, .brightness, .copied, .pasted, .screenshot, .capsLock, .mediaSkip, .trackChanged: false
        }
    }
}

@MainActor
final class CommandEchoManager: ObservableObject {
    @Published private(set) var event: CommandEchoKind = .copied
    @Published private(set) var revision = 0

    private var timer: Timer?
    private var lastVolume: Double?
    private var lastPasteboardChangeCount = NSPasteboard.general.changeCount
    private var lastCapsLockState = NSEvent.modifierFlags.contains(.capsLock)
    private var screenshotObservers: [NSObjectProtocol] = []
    private var keyboardMonitor: Any?
    private var mediaKeyMonitor: Any?

    func startMonitoring() {
        guard timer == nil else { return }
        lastVolume = Self.readSystemVolume()
        lastPasteboardChangeCount = NSPasteboard.general.changeCount
        lastCapsLockState = NSEvent.modifierFlags.contains(.capsLock)
        startScreenshotMonitoring()
        startInputMonitoring()

        setSystemPollingEnabled(true)
    }

    /// The volume, copy and Caps Lock watch only feeds the Command Echo
    /// HUD, so it rests while that is off. Five looks a second is quick
    /// enough for a HUD and less than half the wake-ups of before.
    func setSystemPollingEnabled(_ enabled: Bool) {
        guard enabled != (timer != nil) else { return }
        guard enabled else {
            timer?.invalidate()
            timer = nil
            return
        }
        lastVolume = nil
        lastPasteboardChangeCount = NSPasteboard.general.changeCount
        lastCapsLockState = NSEvent.modifierFlags.contains(.capsLock)
        let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.pollSystemState() }
        }
        timer.tolerance = 0.04
        self.timer = timer
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        let center = DistributedNotificationCenter.default()
        screenshotObservers.forEach(center.removeObserver)
        screenshotObservers.removeAll()
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        if let mediaKeyMonitor { NSEvent.removeMonitor(mediaKeyMonitor) }
        keyboardMonitor = nil
        mediaKeyMonitor = nil
    }

    func showVolume(_ value: Double) {
        let normalized = value > 1 ? value / 100 : value
        publish(.volume(min(max(normalized, 0), 1)))
    }

    func showMediaSkip(_ direction: MediaSkipDirection) {
        publish(.mediaSkip(direction))
    }

    func showTrackChanged(_ title: String, direction: MediaSkipDirection?) {
        publish(.trackChanged(title, direction))
    }

    func showNotification(_ notification: CapturedNotification) {
        publish(.notification(notification))
    }

    func showTimerFinished(_ finish: TimerFinish) {
        publish(.timerFinished(finish))
    }

    func showUpcomingEvent(_ event: CalendarEventInfo) {
        publish(.upcomingEvent(event))
    }

    func showRequest(_ item: CapturedNotification) {
        publish(.request(item))
    }

    func showUpdateAvailable(_ version: String) {
        publish(.updateAvailable(version))
    }

    func showAgent(_ event: AgentEvent) {
        switch event {
        case .finished(let session): publish(.agentFinished(session))
        case .waiting(let session): publish(.agentWaiting(session))
        case .permission(let permission): publish(.agentPermission(permission))
        }
    }

    func showPower(_ event: PowerEvent) {
        publish(.power(event))
    }

    func showHeadphones(_ battery: HeadphoneBattery) {
        publish(.headphones(battery))
    }

    func showPrivacy(_ usage: PrivacyUsage) {
        publish(.privacy(usage))
    }

    func showScreenshot(_ capture: ScreenshotCapture) {
        publish(.screenshotPreview(capture))
    }

    func showRain(_ outlook: RainOutlook) {
        publish(.rain(outlook))
    }

    func showDownloadFinished(_ download: FinishedDownload) {
        publish(.downloadFinished(download))
    }

    /// For key presses islo. handled itself. Also primes the volume poller so
    /// the same change isn't announced a second time.
    func showHandledVolume(_ value: Double) {
        lastVolume = Self.readSystemVolume()
        publish(.volume(min(max(value, 0), 1)))
    }

    func showHandledBrightness(_ value: Double) {
        publish(.brightness(min(max(value, 0), 1)))
    }

    /// Without Accessibility, macOS handles the brightness keys itself; read
    /// the value once it has applied the step. Brightness isn't polled, so
    /// auto-brightness changes never show up in the notch.
    private func announceBrightnessAfterKeyPress() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let brightness = Self.readBrightness() else { return }
            self?.publish(.brightness(brightness))
        }
    }

    private func startInputMonitoring() {
        guard keyboardMonitor == nil, mediaKeyMonitor == nil else { return }
        keyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard event.modifierFlags.contains(.command),
                  event.charactersIgnoringModifiers?.lowercased() == "v" else { return }
            Task { @MainActor in self?.publish(.pasted) }
        }
        mediaKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) {
            [weak self] event in
            guard event.subtype.rawValue == 8 else { return }
            let data = UInt32(bitPattern: Int32(truncatingIfNeeded: event.data1))
            let keyCode = Int((data & 0xFFFF0000) >> 16)
            let keyFlags = Int(data & 0x0000FFFF)
            guard keyFlags & 0xFF00 == 0x0A00 else { return }
            // Global monitors see these keys without Accessibility. When
            // islo.'s own key handler is active it consumes them first.
            if keyCode == HUDKey.brightnessUp.rawValue ||
                keyCode == HUDKey.brightnessDown.rawValue {
                Task { @MainActor in self?.announceBrightnessAfterKeyPress() }
                return
            }
            let direction: MediaSkipDirection?
            switch keyCode {
            case 17: direction = .next
            case 18: direction = .previous
            default: direction = nil
            }
            guard let direction else { return }
            Task { @MainActor in self?.publish(.mediaSkip(direction)) }
        }
    }

    private func pollSystemState() {
        if let volume = Self.readSystemVolume() {
            if let previous = lastVolume, abs(volume - previous) >= 0.005 {
                publish(.volume(volume))
            }
            lastVolume = volume
        }

        let pasteboardCount = NSPasteboard.general.changeCount
        if pasteboardCount != lastPasteboardChangeCount {
            lastPasteboardChangeCount = pasteboardCount
            publish(.copied)
        }

        let capsLockState = NSEvent.modifierFlags.contains(.capsLock)
        if capsLockState != lastCapsLockState {
            lastCapsLockState = capsLockState
            publish(.capsLock(capsLockState))
        }
    }

    private func startScreenshotMonitoring() {
        guard screenshotObservers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        let names = [
            "com.apple.screencaptureui.completed",
            "com.apple.screencapture.completed"
        ]
        screenshotObservers = names.map { rawName in
            center.addObserver(
                forName: Notification.Name(rawName),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let filename = (notification.userInfo?["filename"] as? String)
                    .map { URL(fileURLWithPath: $0).lastPathComponent }
                    ?? "PNG"
                Task { @MainActor in self?.publish(.screenshot(filename)) }
            }
        }
    }

    private func publish(_ event: CommandEchoKind) {
        self.event = event
        revision &+= 1
    }

    private static func readBrightness() -> Double? {
        // On Apple Silicon only DisplayServices reports the live value; the
        // AppleARMBacklight registry entry keeps its boot-time value.
        if let brightness = BuiltInDisplayBrightness.brightness() {
            return brightness
        }

        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect")
        )
        if service != 0 {
            defer { IOObjectRelease(service) }

            var brightness: Float = 0
            let result = IODisplayGetFloatParameter(
                service,
                0,
                kIODisplayBrightnessKey as CFString,
                &brightness
            )
            if result == kIOReturnSuccess {
                return min(max(Double(brightness), 0), 1)
            }
        }
        return nil
    }

    private static func readSystemVolume() -> Double? {
        SystemAudioOutput.volume()
    }
}

/// The default output device's volume and mute state through CoreAudio.
enum SystemAudioOutput {
    private static let channelElements: [AudioObjectPropertyElement] = [
        kAudioObjectPropertyElementMain,
        AudioObjectPropertyElement(1),
        AudioObjectPropertyElement(2)
    ]

    static func defaultDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        ) == noErr, device != 0 else { return nil }
        return device
    }

    static func volume() -> Double? {
        guard let device = defaultDevice() else { return nil }
        var values: [Double] = []
        for element in channelElements {
            var address = volumeAddress(element)
            guard AudioObjectHasProperty(device, &address) else { continue }
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr {
                values.append(Double(value))
                if element == kAudioObjectPropertyElementMain { break }
            }
        }
        guard !values.isEmpty else { return nil }
        return min(max(values.reduce(0, +) / Double(values.count), 0), 1)
    }

    /// Sets the main volume, or each stereo channel when the device has no
    /// main control. Returns false when the device can't be adjusted.
    @discardableResult
    static func setVolume(_ value: Double) -> Bool {
        guard let device = defaultDevice() else { return false }
        var scalar = Float32(min(max(value, 0), 1))
        let settable = channelElements.filter { isSettable(device, volumeAddress($0)) }
        let targets = settable.contains(kAudioObjectPropertyElementMain)
            ? [kAudioObjectPropertyElementMain]
            : settable
        guard !targets.isEmpty else { return false }
        for element in targets {
            var address = volumeAddress(element)
            AudioObjectSetPropertyData(
                device,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<Float32>.size),
                &scalar
            )
        }
        return true
    }

    static var canSetVolume: Bool {
        guard let device = defaultDevice() else { return false }
        return channelElements.contains { isSettable(device, volumeAddress($0)) }
    }

    static func isMuted() -> Bool? {
        guard let device = defaultDevice() else { return nil }
        var address = muteAddress
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr
        else { return nil }
        return muted != 0
    }

    @discardableResult
    static func setMuted(_ muted: Bool) -> Bool {
        guard let device = defaultDevice(), isSettable(device, muteAddress) else {
            return false
        }
        var address = muteAddress
        var value = UInt32(muted ? 1 : 0)
        return AudioObjectSetPropertyData(
            device,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &value
        ) == noErr
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func volumeAddress(
        _ element: AudioObjectPropertyElement
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
    }

    private static func isSettable(
        _ device: AudioDeviceID,
        _ address: AudioObjectPropertyAddress
    ) -> Bool {
        var address = address
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr
            && settable.boolValue
    }
}

/// The built-in display's brightness. macOS has no public API for this on
/// Apple Silicon, so DisplayServices is loaded at runtime; if it's missing,
/// islo. leaves the brightness keys to macOS.
enum BuiltInDisplayBrightness {
    private typealias Getter = @convention(c) (
        CGDirectDisplayID,
        UnsafeMutablePointer<Float>
    ) -> Int32
    private typealias Setter = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let framework = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        RTLD_LAZY
    )
    private static let getter: Getter? = symbol("DisplayServicesGetBrightness")
    private static let setter: Setter? = symbol("DisplayServicesSetBrightness")

    private static func symbol<T>(_ name: String) -> T? {
        guard let framework, let pointer = dlsym(framework, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    static var displayID: CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return nil
        }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else {
            return nil
        }
        return displays.first { CGDisplayIsBuiltin($0) != 0 }
    }

    static func brightness() -> Double? {
        guard let getter, let display = displayID else { return nil }
        var value: Float = 0
        guard getter(display, &value) == 0 else { return nil }
        return min(max(Double(value), 0), 1)
    }

    @discardableResult
    static func setBrightness(_ value: Double) -> Bool {
        guard let setter, let display = displayID else { return false }
        return setter(display, Float(min(max(value, 0), 1))) == 0
    }
}

private enum HUDKey: Int {
    case soundUp = 0
    case soundDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
}

/// Takes over the hardware volume and brightness keys so macOS doesn't draw
/// its own HUD next to islo.'s. Needs Accessibility access. Without it, or
/// for an output or display islo. can't adjust, the keys pass through and
/// macOS handles them as usual.
final class SystemHUDInterceptor {
    private let onVolume: (Double) -> Void
    private let onBrightness: (Double) -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?
    private var isEnabled = false
    /// While the notch is off screen (full-screen apps) there is no HUD to
    /// show, so the keys go back to macOS and its own indicator.
    var isNotchVisible = true

    init(
        onVolume: @escaping (Double) -> Void,
        onBrightness: @escaping (Double) -> Void
    ) {
        self.onVolume = onVolume
        self.onBrightness = onBrightness
    }

    deinit {
        stop()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        guard enabled else {
            stop()
            return
        }
        installTapIfPossible()
        // Accessibility can be granted while islo. runs; keep trying so the
        // takeover starts without a relaunch.
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) {
            [weak self] _ in
            self?.installTapIfPossible()
        }
    }

    private func installTapIfPossible() {
        guard isEnabled else { return }
        if let eventTap {
            if !CGEvent.tapIsEnabled(tap: eventTap) {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }
        guard AXIsProcessTrusted() else { return }

        // NX_SYSDEFINED carries the media and brightness keys.
        let systemDefinedMask = CGEventMask(1) << 14
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: systemDefinedMask,
            callback: systemHUDTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
    }

    private func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    fileprivate func handle(
        _ type: CGEventType,
        _ event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return passThrough
        }

        guard type.rawValue == 14,
              let systemEvent = NSEvent(cgEvent: event),
              systemEvent.subtype.rawValue == 8 else {
            return passThrough
        }

        let data = UInt32(bitPattern: Int32(truncatingIfNeeded: systemEvent.data1))
        guard let key = HUDKey(rawValue: Int((data & 0xFFFF_0000) >> 16)) else {
            return passThrough
        }
        let isKeyDown = (data & 0xFF00) >> 8 == 0x0A
        // Option-Shift gives quarter steps, as it does in macOS. Any other
        // combination (Option opens the settings pane, Shift flips the
        // feedback sound, Control targets an external display) is macOS's.
        let modifiers = systemEvent.modifierFlags.intersection([.option, .shift, .control, .command])
        let isFineStep = modifiers == [.option, .shift]
        guard isNotchVisible, modifiers.isEmpty || isFineStep else { return passThrough }

        // Swallow both halves of a press islo. can handle; act on key-down
        // (including key repeat) only.
        guard canHandle(key) else { return passThrough }
        if isKeyDown { perform(key, fineStep: isFineStep) }
        return nil
    }

    private func canHandle(_ key: HUDKey) -> Bool {
        switch key {
        case .soundUp, .soundDown, .mute:
            return SystemAudioOutput.canSetVolume
        case .brightnessUp, .brightnessDown:
            return BuiltInDisplayBrightness.brightness() != nil
        }
    }

    private func perform(_ key: HUDKey, fineStep: Bool) {
        let step = fineStep ? 1.0 / 64 : 1.0 / 16

        switch key {
        case .soundUp, .soundDown:
            let current = SystemAudioOutput.volume() ?? 0
            let direction: Double = key == .soundUp ? 1 : -1
            let next = stepped(current, by: step, direction: direction)
            if key == .soundUp, SystemAudioOutput.isMuted() == true {
                SystemAudioOutput.setMuted(false)
            }
            SystemAudioOutput.setVolume(next)
            report(onVolume, value: next)

        case .mute:
            let muted = !(SystemAudioOutput.isMuted() ?? false)
            SystemAudioOutput.setMuted(muted)
            report(onVolume, value: muted ? 0 : SystemAudioOutput.volume() ?? 0)

        case .brightnessUp, .brightnessDown:
            guard let current = BuiltInDisplayBrightness.brightness() else { return }
            let direction: Double = key == .brightnessUp ? 1 : -1
            let next = stepped(current, by: step, direction: direction)
            BuiltInDisplayBrightness.setBrightness(next)
            report(onBrightness, value: next)
        }
    }

    private func stepped(_ value: Double, by step: Double, direction: Double) -> Double {
        min(max(((value / step).rounded() + direction) * step, 0), 1)
    }

    private func report(_ callback: @escaping (Double) -> Void, value: Double) {
        DispatchQueue.main.async { callback(value) }
    }
}

private func systemHUDTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let interceptor = Unmanaged<SystemHUDInterceptor>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    return interceptor.handle(type, event)
}

struct ClipboardEntry: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let source: String
    let capturedAt: Date
}

/// A deliberately in-memory clipboard history. Nothing is written to disk and
/// the list is discarded when islo. quits.
@MainActor
final class ClipboardHistoryManager: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount

    func startMonitoring() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.captureIfNeeded() }
        }
        timer.tolerance = 0.1
        self.timer = timer
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    /// Off also forgets what was collected.
    func setEnabled(_ enabled: Bool) {
        if enabled {
            startMonitoring()
        } else {
            stopMonitoring()
            entries.removeAll()
        }
    }

    func copy(_ entry: ClipboardEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
    }

    func remove(_ entry: ClipboardEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    func clear() { entries.removeAll() }

    #if DEBUG
    /// Debug builds: a history entry copied `age` seconds ago.
    func debugInject(_ text: String, age: TimeInterval) {
        entries.insert(ClipboardEntry(text: text, source: "islo. test", capturedAt: Date().addingTimeInterval(-age)), at: 0)
    }
    #endif

    /// Drops entries copied more than `interval` ago.
    func removeEntries(olderThan interval: TimeInterval?) {
        guard let interval, !entries.isEmpty else { return }
        let cutoff = Date().addingTimeInterval(-interval)
        guard entries.contains(where: { $0.capturedAt < cutoff }) else { return }
        entries.removeAll { $0.capturedAt < cutoff }
    }

    private func captureIfNeeded() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        let concealedTypes = [
            NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
            NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
            NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"),
            NSPasteboard.PasteboardType("com.agilebits.onepassword")
        ]
        let availableTypes = pasteboard.types ?? []
        guard concealedTypes.allSatisfy({ !availableTypes.contains($0) }) else { return }
        guard let text = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              entries.first?.text != text else { return }
        let source = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Mac"
        entries.insert(ClipboardEntry(text: text, source: source, capturedAt: .now), at: 0)
        entries = Array(entries.prefix(40))
    }
}

extension ClipboardEntry {
    /// A web address worth opening rather than only copying.
    var linkURL: URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(" "), !trimmed.contains("\n") else { return nil }
        let candidate = trimmed.lowercased().hasPrefix("www.") ? "https://" + trimmed : trimmed
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return url
    }
}

private let notificationLog = Logger(subsystem: "com.ozdmrysn.islo", category: "notifications")

/// Keeps macOS's own banners off screen while the notch shows them.
/// Notification Center draws banners in one window; moving that window
/// past the right edge of the screens hides them without dismissing
/// anything, so each notification still times out into Notification
/// Center. macOS puts the window back itself when Notification Center is
/// opened. Everything except the two settings runs on the scan queue.
final class SystemBannerHider {
    /// An alert still up after this long is waiting for an answer
    /// (Calendar's, for example), so it comes back on screen.
    static let waitingAfter: TimeInterval = 10

    private let lock = NSLock()
    private var allowed = false
    private var offscreen: CGFloat = 40_000

    var isAllowed: Bool {
        get { locked { allowed } }
        set { locked { allowed = newValue } }
    }

    var offscreenX: CGFloat {
        get { locked { offscreen } }
        set { locked { offscreen = newValue } }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private var muted: Set<String> = []

    /// Apps whose notifications the notch leaves to macOS.
    var mutedApps: Set<String> {
        get { locked { muted } }
        set { locked { muted = newValue } }
    }

    private var held: Set<String> = []

    /// Banners the notch is answering for macOS (a ringing call, an
    /// AirDrop): they wait for an answer, but in the notch, so they stay
    /// off screen however long that takes.
    var heldBanners: Set<String> {
        get { locked { held } }
        set { locked { held = newValue } }
    }

    private var shown: Set<String> = []

    /// Banners only macOS can handle right now (a call in progress whose
    /// controls the notch can't reach): they stay on screen.
    var shownBanners: Set<String> {
        get { locked { shown } }
        set { locked { shown = newValue } }
    }

    private var firstSeen: [String: Date] = [:]
    private var moved: (window: AXUIElement, original: CGPoint)?

    func update(
        window: AXUIElement,
        keys: [String],
        identifiers: [String],
        appNames: [String],
        unreadable: Int,
        isCenterOpen: Bool
    ) {
        guard !isCenterOpen else {
            // macOS normally moves the window back itself to show its
            // panel; make sure it's never left off screen.
            if let moved, let position = Self.position(of: moved.window), position.x >= offscreenX - 1 {
                Self.setPosition(moved.original, of: moved.window)
            }
            firstSeen.removeAll()
            moved = nil
            return
        }
        let now = Date()
        firstSeen = firstSeen.filter { keys.contains($0.key) }
        let arrived = keys.filter { firstSeen[$0] == nil }
        for key in arrived { firstSeen[key] = now }

        // A banner on its way out leaves the window empty for a moment
        // while macOS animates it away; bringing the window back then
        // would show it, so leave it until macOS closes the window.
        if keys.isEmpty && unreadable == 0 { return }

        let heldNow = heldBanners
        let heldKeys = Set(zip(keys, identifiers).filter { heldNow.contains($0.1) }.map(\.0))
        let isWaiting = firstSeen.contains {
            !heldKeys.contains($0.key) && now.timeIntervalSince($0.value) > Self.waitingAfter
        }
        // Apps the notch leaves to macOS keep macOS's banner.
        let hasMuted = !mutedApps.isDisjoint(with: appNames)
        let mustShow = !shownBanners.isDisjoint(with: identifiers)
        // Banners islo. couldn't read stay visible, as do alerts that wait
        // for an answer.
        if unreadable > 0 || isWaiting || hasMuted || mustShow {
            restore()
        } else if isAllowed {
            hide(window)
        } else if !arrived.isEmpty || !heldKeys.isEmpty {
            // The notch can't show this one (it's open or hidden), so let
            // macOS show it.
            restore()
        }
    }

    func windowsClosed() {
        firstSeen.removeAll()
        moved = nil
    }

    func restore() {
        guard let moved else { return }
        self.moved = nil
        Self.setPosition(moved.original, of: moved.window)
    }

    private func hide(_ window: AXUIElement) {
        guard let position = Self.position(of: window) else { return }
        let target = offscreenX
        guard position.x < target - 1 else { return }
        moved = (window, position)
        Self.setPosition(CGPoint(x: target, y: position.y), of: window)
    }

    private static func position(of window: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    private static func setPosition(_ point: CGPoint, of window: AXUIElement) {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }
}

extension String {
    /// Without the invisible direction marks some apps put in their names
    /// (WhatsApp's is "\u{200E}WhatsApp").
    var withoutDirectionMarks: String {
        let marks: Set<Unicode.Scalar> = [
            "\u{200E}", "\u{200F}", "\u{061C}",
            "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",
            "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}"
        ]
        let kept = unicodeScalars.filter { !marks.contains($0) }
        return String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A button macOS shows on a banner ("Accept", "Decline", "End"…).
struct NotificationAction: Equatable, Hashable {
    enum Role: Equatable, Hashable {
        case accept, decline, end, mute, other
    }

    /// Its title, in the system's language.
    let title: String
    /// The Accessibility action that presses it; nil for a plain button,
    /// which is found by its title.
    let actionName: String?

    var role: Role {
        let lowered = title.lowercased()
        func matches(_ words: [String]) -> Bool {
            words.contains { lowered == $0 || lowered.hasPrefix($0 + " ") }
        }
        if matches(["kabul et", "kabul", "accept", "answer", "yanıtla", "katıl", "join"]) { return .accept }
        if matches(["reddet", "decline", "geri çevir", "yoksay", "ignore"]) { return .decline }
        if matches(["bitir", "end", "sonlandır", "aramayı bitir", "end call", "hang up"]) { return .end }
        if matches(["sessiz", "sesi kapat", "sesi aç", "mute", "unmute", "sessize al"]) { return .mute }
        return .other
    }
}

/// A notification macOS showed as a banner, read through Accessibility.
struct CapturedNotification: Identifiable, Equatable {
    let id: String
    let appName: String
    let bundleIdentifier: String?
    let title: String
    let subtitle: String
    let body: String
    let date: Date
    /// The banner's identifier in Notification Center.
    var bannerIdentifier = ""
    /// The banner's own buttons, reachable while macOS keeps it up.
    var actions: [NotificationAction] = []

    enum RequestKind { case call, airDrop, other }

    /// The banner macOS uses for a ringing or ongoing call, whether it
    /// comes from the iPhone or over FaceTime.
    static let callBannerIdentifier = "FACETIME_NOTIFICATION"

    var isCallBanner: Bool { bannerIdentifier == Self.callBannerIdentifier }

    var requestKind: RequestKind {
        let name = appName.lowercased()
        if name.contains("airdrop") { return .airDrop }
        if isCallBanner || ["facetime", "telefon", "phone"].contains(name) { return .call }
        return .other
    }

    func action(_ role: NotificationAction.Role) -> NotificationAction? {
        actions.first { $0.role == role }
    }

    /// A call that was answered: it can be ended, no longer accepted. The
    /// call banner with buttons but nothing to accept is one too, whatever
    /// its buttons are called.
    var isOngoingCall: Bool {
        guard action(.accept) == nil else { return false }
        return action(.end) != nil || (isCallBanner && !actions.isEmpty)
    }

    /// The call banner in its first moment, before macOS has filled in who
    /// is calling and the buttons.
    var isArrivingCall: Bool { isCallBanner && actions.isEmpty }

    /// Something that waits for an answer: it can be accepted and declined,
    /// or it is a call in progress.
    var isRequest: Bool {
        (action(.accept) != nil && action(.decline) != nil) || isOngoingCall
    }

    var requestSymbolName: String {
        switch requestKind {
        case .call: isOngoingCall ? "phone.fill" : "phone.arrow.down.left.fill"
        case .airDrop: "dot.radiowaves.left.and.right"
        case .other: "bell.badge.fill"
        }
    }

    /// The line to lead with: the title, or the body when there's no title.
    var headline: String { title.isEmpty ? body : title }

    /// What follows the headline, without repeating it.
    var detail: String {
        let parts = title.isEmpty ? [subtitle] : [subtitle, body]
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Watches the banners Notification Center puts on screen. macOS has no API
/// for other apps' notifications, but each banner is an Accessibility
/// element with a unique identifier and separate title, subtitle and body,
/// so islo. can read new ones as they appear. Needs Accessibility access;
/// notifications that never show a banner (e.g. in a Focus) aren't seen.
@MainActor
final class NotificationMonitor: ObservableObject {
    @Published private(set) var items: [CapturedNotification] = []
    @Published private(set) var unreadCount = 0
    /// Bumps once per notification worth announcing in the notch.
    @Published private(set) var announcementRevision = 0
    private(set) var latest: CapturedNotification?
    /// A call or an AirDrop that is waiting for an answer right now, kept
    /// current with its banner. Nil once macOS takes the banner away.
    @Published private(set) var liveRequest: CapturedNotification?
    /// Requests handed back to macOS's own banner.
    /// Requests handed back to macOS's own banner, with the buttons each
    /// had then. A banner that moves on (a call that gets answered) is a
    /// new state and comes back to the notch.
    private var releasedRequests: [String: [NotificationAction]] = [:]
    private var pressed: (identifier: String, actions: [NotificationAction], action: NotificationAction, at: Date)? {
        didSet {
            let role = pressed?.action.role
            if pendingRole != role { pendingRole = role }
        }
    }
    /// The button just pressed, until its banner reacts (a call takes a
    /// couple of seconds to connect).
    @Published private(set) var pendingRole: NotificationAction.Role?
    private var fastRescanScheduled = false
    /// macOS starts the Phone app in the background the moment a call
    /// reaches the Mac, a good two seconds before it has a banner up. That
    /// is when the notch says a call is coming.
    private var earlyCall: Date?
    private var launchObserver: NSObjectProtocol?
    private static let phoneBundleIdentifier = "com.apple.mobilephone"
    /// The call banner as it goes from ringing to answered to gone.
    private var callBanner: (since: Date, wasRequest: Bool, answeredHere: Bool, sawControls: Bool, loggedLive: Bool, lastButtons: Date)?
    private var loggedActionApps: Set<String> = []

    /// A ringing call is read here too, so it must not wait behind
    /// background work.
    private let scanQueue = DispatchQueue(label: "islo.notifications", qos: .userInitiated)
    private var timer: Timer?
    private var isScanning = false
    private var needsRescan = false
    private var hasBaseline = false
    private var seenIdentifiers: [String] = []
    private var loggedUnreadable: Set<String> = []

    /// Tells islo. the moment Notification Center puts a banner up, so the
    /// notch can take over before macOS's banner is really seen.
    private var observer: AXObserver?
    private var observedProcess: pid_t = 0
    private let hider = SystemBannerHider()
    private var mutedApps: Set<String> = []
    private var hidesSystemBanners = false
    private var isNotchReady = true
    private var isNotchVisible = true
    private var wasHiding = false

    func setEnabled(_ enabled: Bool) {
        guard enabled != (timer != nil) else { return }
        if enabled {
            hasBaseline = false
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
                [weak self] _ in
                Task { @MainActor in self?.scheduleScan() }
            }
            launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
            ) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == Self.phoneBundleIdentifier else { return }
                Task { @MainActor in self?.phoneAppLaunched(app) }
            }
        } else {
            timer?.invalidate()
            timer = nil
            removeObserver()
            if let launchObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(launchObserver)
            }
            launchObserver = nil
            earlyCall = nil
        }
        updateHiding()
    }

    /// Whether macOS's banner should give way to the notch's own.
    func setHidesSystemBanners(_ hides: Bool) {
        hidesSystemBanners = hides
        updateHiding()
    }

    /// The notch is closed and can show a notification as it arrives.
    func setNotchReady(_ ready: Bool) {
        isNotchReady = ready
        updateHiding()
    }

    /// The notch is on screen (it hides over full-screen apps).
    func setNotchVisible(_ visible: Bool) {
        isNotchVisible = visible
        updateHiding()
    }

    private func updateHiding() {
        let isOn = hidesSystemBanners && timer != nil
        hider.offscreenX = (NSScreen.screens.map(\.frame.maxX).max() ?? 4_000) + 8_000
        hider.isAllowed = isOn && isNotchReady && isNotchVisible
        if wasHiding, !isOn {
            // Put back anything still hidden; on quit too, so nothing is
            // left off screen.
            let hider = hider
            scanQueue.sync { hider.restore() }
        }
        wasHiding = isOn
    }

    /// Apps whose notifications stay with macOS: not shown or listed here,
    /// and macOS's banner isn't hidden for them.
    func setMutedApps(_ apps: [String]) {
        mutedApps = Set(apps)
        hider.mutedApps = mutedApps
    }

    func markAllRead() {
        if unreadCount != 0 { unreadCount = 0 }
    }

    func clear() {
        items.removeAll()
        unreadCount = 0
    }

    func remove(_ item: CapturedNotification) {
        items.removeAll { $0.id == item.id }
    }

    /// Drops notifications that arrived more than `interval` ago.
    func removeItems(olderThan interval: TimeInterval?) {
        guard let interval, !items.isEmpty else { return }
        let cutoff = Date().addingTimeInterval(-interval)
        guard items.contains(where: { $0.date < cutoff }) else { return }
        items.removeAll { $0.date < cutoff }
        // The unread ones are the newest, so the count can only shrink.
        unreadCount = min(unreadCount, items.count)
    }

    func openApplication(for item: CapturedNotification) {
        guard let bundleIdentifier = item.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
              ) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    /// Opened by the user, the Phone app comes to the front; started by
    /// macOS for an incoming call, it stays in the background.
    private func phoneAppLaunched(_ app: NSRunningApplication) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.timer != nil, !app.isTerminated, !app.isActive,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier
            else { return }
            self.announceEarlyCall()
        }
    }

    private func announceEarlyCall() {
        guard liveRequest == nil, callBanner == nil, !mutedApps.contains("FaceTime") else { return }
        notificationLog.notice("Phone started in the background: a call is arriving")
        earlyCall = Date()
        scheduleScan()
    }

    /// The call the Phone app's start gave away, before it has a banner.
    private var arrivingCallPlaceholder: CapturedNotification {
        CapturedNotification(
            id: "call-arriving", appName: "FaceTime", bundleIdentifier: nil,
            title: "", subtitle: "", body: "", date: earlyCall ?? .now,
            bannerIdentifier: CapturedNotification.callBannerIdentifier
        )
    }

    /// The process that draws the banners.
    private var notificationCenterPID: pid_t? {
        #if DEBUG
        if let debugCenterPID { return debugCenterPID }
        #endif
        return NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.notificationcenterui"
        ).first?.processIdentifier
    }

    private func scheduleScan() {
        guard timer != nil else { return }
        guard !isScanning else {
            needsRescan = true
            return
        }
        guard AXIsProcessTrusted(), let pid = notificationCenterPID else { return }
        if pid != observedProcess { installObserver(processIdentifier: pid) }
        isScanning = true
        let hider = hider
        // Accessibility calls are cross-process; keep them off the main thread.
        scanQueue.async { [weak self] in
            let scan = Self.readBanners(processIdentifier: pid, hider: hider)
            Task { @MainActor in
                guard let self else { return }
                self.isScanning = false
                self.ingest(scan)
                if self.needsRescan {
                    self.needsRescan = false
                    self.scheduleScan()
                }
            }
        }
    }

    private func installObserver(processIdentifier pid: pid_t) {
        removeObserver()
        observedProcess = pid
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let monitor = Unmanaged<NotificationMonitor>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in monitor.scheduleScan() }
        }
        var created: AXObserver?
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
        let application = AXUIElementCreateApplication(pid)
        // The monitor lives as long as the app.
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowCreatedNotification, kAXCreatedNotification, kAXLayoutChangedNotification] {
            AXObserverAddNotification(created, application, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
    }

    private func removeObserver() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        observedProcess = 0
    }

    private func ingest(_ scan: BannerScan) {
        // Say once per kind, so a future macOS layout change shows up in
        // the system log instead of notifications silently going missing.
        for subrole in Set(scan.unreadable) where !loggedUnreadable.contains(subrole) {
            loggedUnreadable.insert(subrole)
            notificationLog.info("Couldn't read a notification element: \(subrole, privacy: .public)")
        }
        let banners = scan.banners
        let fresh = banners.filter { !seenIdentifiers.contains($0.key) }
        seenIdentifiers.append(contentsOf: fresh.map(\.key))
        if seenIdentifiers.count > 400 {
            seenIdentifiers.removeFirst(seenIdentifiers.count - 400)
        }

        trackRequest(in: scan)

        // Banners already on screen when monitoring starts aren't new, and
        // neither is the history the user sees in an open Notification Center.
        guard hasBaseline, !scan.isCenterOpen else {
            hasBaseline = true
            return
        }
        // Opening Notification Center lists the whole history at once; only
        // banners arriving a few at a time are real new notifications.
        guard !fresh.isEmpty, fresh.count <= 3 else { return }

        // Settings lists the apps that send notifications, muted ones too.
        for name in Set(fresh.filter { !$0.title.isEmpty || !$0.body.isEmpty }.map(\.appName)) where !name.isEmpty {
            AppSettings.shared.noteNotificationApp(name)
        }
        // The call banner is only ever a live request; a missed call gets
        // its own notification from macOS afterwards.
        let wanted = fresh.filter {
            !mutedApps.contains($0.appName) && $0.id != CapturedNotification.callBannerIdentifier
        }
        guard !wanted.isEmpty else { return }

        for banner in wanted where !banner.actions.isEmpty && !loggedActionApps.contains(banner.appName) {
            loggedActionApps.insert(banner.appName)
            let titles = banner.actions.map(\.title).joined(separator: ", ")
            notificationLog.notice("Buttons on \(banner.appName, privacy: .public) notifications: \(titles, privacy: .public)")
        }

        let captured = wanted.map(Self.captured(from:))
        // A call in progress is not a notification to keep; a request is
        // listed (it may go unanswered) but announced by its own HUD.
        let listed = captured.filter { !$0.isOngoingCall }
        guard !listed.isEmpty else { return }
        items.insert(contentsOf: listed.reversed(), at: 0)
        items = Array(items.prefix(60))
        unreadCount += listed.count
        guard listed.contains(where: { !$0.isRequest }) else { return }
        latest = items.first { !$0.isRequest }
        announcementRevision &+= 1
    }

    private static func captured(from banner: RawBanner) -> CapturedNotification {
        CapturedNotification(
            id: banner.key,
            appName: banner.appName,
            bundleIdentifier: bundleIdentifier(forAppNamed: banner.appName),
            title: banner.title,
            subtitle: banner.subtitle,
            body: banner.body,
            date: Date().addingTimeInterval(-(banner.elapsed ?? 0)),
            bannerIdentifier: banner.id,
            actions: banner.actions
        )
    }

    /// Follows the banner that waits for an answer: picks it up when it
    /// appears, keeps its buttons current (a call that is answered swaps
    /// Accept for End) and lets go when macOS removes it.
    private func trackRequest(in scan: BannerScan) {
        #if DEBUG
        if debugRequestActive { return }
        #endif
        guard !scan.isCenterOpen else {
            earlyCall = nil
            setLiveRequest(nil)
            return
        }
        let identifier = CapturedNotification.callBannerIdentifier
        let present = Set(scan.banners.map(\.id))
        releasedRequests = releasedRequests.filter { present.contains($0.key) }

        let banners = scan.banners
            .filter { !mutedApps.contains($0.appName) }
            .map(Self.captured(from:))
        // A banner given back to macOS returns to the notch once it has
        // moved on to different buttons.
        for banner in banners {
            if let before = releasedRequests[banner.bannerIdentifier], before != banner.actions, !banner.actions.isEmpty {
                releasedRequests[banner.bannerIdentifier] = nil
            }
        }
        let candidates = banners.filter { $0.isRequest && releasedRequests[$0.bannerIdentifier] == nil }
        var current = candidates.first { $0.bannerIdentifier == liveRequest?.bannerIdentifier }
            ?? candidates.first

        // The call banner is up before macOS has filled it in: the notch
        // says a call is coming right away and gets the name and buttons
        // a moment later.
        if present.contains(identifier), callBanner == nil {
            callBanner = (since: Date(), wasRequest: false, answeredHere: false, sawControls: false, loggedLive: false, lastButtons: Date())
            notificationLog.notice("Call banner appeared")
        }
        if current == nil, let state = callBanner, !state.wasRequest, !state.answeredHere,
           releasedRequests[identifier] == nil, Date().timeIntervalSince(state.since) < 3,
           let arriving = banners.first(where: { $0.isArrivingCall }) {
            current = arriving
        }
        // Earlier still: the Phone app has just been started for a call
        // and the banner is on its way. Without one within a few seconds
        // it was something else.
        if let early = earlyCall {
            if present.contains(identifier) || Date().timeIntervalSince(early) > 5 {
                earlyCall = nil
            } else if current == nil {
                current = arrivingCallPlaceholder
            }
        }

        // A press that changes nothing either didn't reach a banner that
        // is off screen, or macOS wants more (a menu of where to save,
        // say). Its own banner comes back and the press is repeated there.
        // An answered call needs a few seconds to connect, so it gets them.
        if let pressed, let request = current, request.bannerIdentifier == pressed.identifier {
            let patience: TimeInterval = request.isCallBanner ? 8 : 2.5
            if request.actions != pressed.actions {
                self.pressed = nil
            } else if Date().timeIntervalSince(pressed.at) > patience {
                self.pressed = nil
                releasedRequests[request.bannerIdentifier] = request.actions
                current = nil
                repeatOnScreen(pressed.action, onBanner: pressed.identifier)
            }
        }
        // Keep the time the request first showed up (a call's length).
        if let request = current, let live = liveRequest,
           live.bannerIdentifier == request.bannerIdentifier,
           live.isOngoingCall == request.isOngoingCall {
            current = CapturedNotification(
                id: request.id, appName: request.appName, bundleIdentifier: request.bundleIdentifier,
                title: request.title, subtitle: request.subtitle, body: request.body,
                date: live.date, bannerIdentifier: request.bannerIdentifier, actions: request.actions
            )
        }
        if current == nil { pressed = nil }
        setLiveRequest(current)
        followCallBanner(present: present, request: current)

        // While a call is arriving or connecting, half a second between
        // looks is long: look again right away.
        if (current?.isArrivingCall == true || pressed != nil), !fastRescanScheduled {
            fastRescanScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.fastRescanScheduled = false
                self?.scheduleScan()
            }
        }
    }

    /// The call banner outlives its buttons: it rings, is answered, and
    /// lingers a moment after the call. While the notch can answer for it,
    /// it stays hidden; when it shows a call the notch has no buttons for
    /// (answered, but macOS keeps the controls to itself), it has to be on
    /// screen or there would be no way to hang up.
    private func followCallBanner(present: Set<String>, request: CapturedNotification?) {
        let identifier = CapturedNotification.callBannerIdentifier
        guard present.contains(identifier), var state = callBanner else {
            callBanner = nil
            if !hider.shownBanners.isEmpty { hider.shownBanners = [] }
            return
        }
        let isShownHere = request?.bannerIdentifier == identifier
        let hasButtons = isShownHere && request?.actions.isEmpty == false
        if hasButtons {
            state.wasRequest = true
            state.lastButtons = Date()
            if !state.loggedLive {
                state.loggedLive = true
                let waited = String(format: "%.2f", Date().timeIntervalSince(state.since))
                notificationLog.notice("Call buttons ready \(waited, privacy: .public) s after the banner")
            }
        }
        // The notch had the call's own controls, so it never needs macOS's.
        if hasButtons, request?.isOngoingCall == true { state.sawControls = true }
        callBanner = state

        let mustShow: Bool
        if isShownHere {
            mustShow = false
        } else if releasedRequests[identifier] != nil {
            mustShow = true
        } else if state.answeredHere && !state.sawControls {
            // Answered from the notch and the buttons are gone: unless
            // that is only the banner changing over, macOS has the call.
            mustShow = Date().timeIntervalSince(state.lastButtons) > 1.5
        } else if !state.wasRequest {
            // Never had buttons the notch could use: leave it to macOS.
            mustShow = true
        } else {
            // Rang and stopped, or was hung up: it is on its way out.
            mustShow = false
        }
        let shown: Set<String> = mustShow ? [identifier] : []
        if hider.shownBanners != shown { hider.shownBanners = shown }
    }

    private func setLiveRequest(_ request: CapturedNotification?) {
        hider.heldBanners = request.map { [$0.bannerIdentifier] } ?? []
        if liveRequest != request { liveRequest = request }
    }

    /// Presses one of the request's buttons on macOS's banner.
    func perform(_ action: NotificationAction, on request: CapturedNotification) {
        #if DEBUG
        if debugRequestActive {
            debugRequest(action.role == .accept && request.requestKind == .call ? "answer" : "clear")
            return
        }
        #endif
        guard let pid = notificationCenterPID else { return }
        // Muting changes nothing the notch can see; every other button
        // should, and is handed to macOS if it doesn't.
        if action.role != .mute {
            pressed = (request.bannerIdentifier, request.actions, action, Date())
        }
        if request.isCallBanner, action.role == .accept { callBanner?.answeredHere = true }
        let identifier = request.bannerIdentifier
        scanQueue.async { [weak self] in
            let done = Self.press(action, onBanner: identifier, processIdentifier: pid)
            notificationLog.notice("Pressed \(action.title, privacy: .public): \(done, privacy: .public)")
            Task { @MainActor in self?.scheduleScan() }
        }
    }

    private func repeatOnScreen(_ action: NotificationAction, onBanner identifier: String) {
        guard let pid = notificationCenterPID else { return }
        let hider = hider
        scanQueue.async {
            hider.restore()
            // Give the window a moment to be back in place.
            Thread.sleep(forTimeInterval: 0.3)
            let done = Self.press(action, onBanner: identifier, processIdentifier: pid)
            notificationLog.notice("Pressed \(action.title, privacy: .public) again on screen: \(done, privacy: .public)")
        }
    }

    /// Gives the request back to macOS's own banner.
    func releaseRequest() {
        guard let request = liveRequest else { return }
        releasedRequests[request.bannerIdentifier] = request.actions
        pressed = nil
        setLiveRequest(nil)
        let hider = hider
        scanQueue.async { hider.restore() }
    }

    private static func bundleIdentifier(forAppNamed name: String) -> String? {
        let apps = NSWorkspace.shared.runningApplications.filter {
            ($0.localizedName ?? "").withoutDirectionMarks == name
        }
        if let app = apps.first(where: { $0.activationPolicy == .regular }) ?? apps.first {
            return app.bundleIdentifier
        }
        for folder in ["/Applications", "/System/Applications"] {
            let url = URL(fileURLWithPath: "\(folder)/\(name).app")
            if let identifier = Bundle(url: url)?.bundleIdentifier { return identifier }
        }
        return nil
    }

    fileprivate struct RawBanner {
        let id: String
        let appName: String
        let title: String
        let subtitle: String
        let body: String
        var actions: [NotificationAction] = []
        /// How long a call has lasted, read from its banner.
        var elapsed: TimeInterval?

        /// A stack keeps its identifier while new messages replace its top
        /// one (e.g. several WhatsApp messages from one chat), so the text
        /// is part of what makes a notification new.
        var key: String { [id, title, subtitle, body].joined(separator: "\u{1F}") }
    }

    fileprivate struct BannerScan {
        var banners: [RawBanner] = []
        /// Notification Center's panel is open, listing older notifications.
        var isCenterOpen = false
        /// Subroles of notification elements whose text couldn't be read.
        var unreadable: [String] = []
    }

    nonisolated private static func readBanners(processIdentifier: pid_t, hider: SystemBannerHider) -> BannerScan {
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.25)
        var scan = BannerScan()
        var sawWindow = false
        for window in children(of: application)
        where string(window, kAXSubroleAttribute) == "AXSystemDialog" {
            sawWindow = true
            var windowScan = BannerScan()
            collectBanners(in: window, depth: 0, into: &windowScan)
            hider.update(
                window: window,
                keys: windowScan.banners.map(\.key),
                identifiers: windowScan.banners.map(\.id),
                appNames: windowScan.banners.map(\.appName),
                unreadable: windowScan.unreadable.count,
                isCenterOpen: windowScan.isCenterOpen
            )
            scan.banners += windowScan.banners
            scan.unreadable += windowScan.unreadable
            scan.isCenterOpen = scan.isCenterOpen || windowScan.isCenterOpen
        }
        if !sawWindow { hider.windowsClosed() }
        return scan
    }

    nonisolated private static func collectBanners(
        in element: AXUIElement,
        depth: Int,
        into scan: inout BannerScan
    ) {
        guard depth < 10 else { return }
        let subrole = string(element, kAXSubroleAttribute) ?? ""
        // Single banners, stacks ("AXNotificationCenterBannerStack") and
        // alerts all share this prefix.
        if subrole.hasPrefix("AXNotificationCenter") {
            if let banner = banner(from: element) {
                scan.banners.append(banner)
            } else {
                scan.unreadable.append(subrole)
            }
            return
        }
        // Only the open panel has the history button and the widget grid.
        if subrole == "AXOpaqueProviderGrid"
            || string(element, kAXIdentifierAttribute) == "AXShowHistoryButton" {
            scan.isCenterOpen = true
        }
        for child in children(of: element) {
            collectBanners(in: child, depth: depth + 1, into: &scan)
        }
    }

    nonisolated private static func banner(from element: AXUIElement) -> RawBanner? {
        // Texts are usually direct children, but richer banners (message
        // apps with a sender photo) can wrap them in groups.
        var fields: [String: String] = [:]
        collectTexts(in: element, depth: 0, fields: &fields)

        let description = string(element, kAXDescriptionAttribute) ?? ""
        var title = fields["title"] ?? ""
        let subtitle = fields["subtitle"] ?? ""
        var body = fields["body"] ?? ""
        // Without named fields, fall back to the description, which reads
        // "App, title, body".
        if title.isEmpty && body.isEmpty {
            let parts = description.components(separatedBy: ", ")
            if parts.count >= 3 {
                title = parts[1]
                body = parts[2...].joined(separator: ", ")
            } else if parts.count == 2 {
                body = parts[1]
            }
        }
        let identifier = string(element, kAXIdentifierAttribute) ?? ""
        if identifier == CapturedNotification.callBannerIdentifier {
            // A call has no title or message fields: who is calling is the
            // description of a plain element next to the buttons. Before
            // macOS has filled it in, the banner is still a call.
            let texts = looseTexts(in: element, depth: 0)
            // "Name, from your iPhone", and once answered the length of
            // the call after a dash: "Name, from your iPhone-0:42".
            var line = texts.first ?? ""
            var elapsed: TimeInterval?
            if let range = line.range(of: #"\s*[-–—]\s*(\d+:)?\d{1,2}:\d{2}$"#, options: .regularExpression) {
                let clock = line[range].filter { $0.isNumber || $0 == ":" }
                elapsed = clock.split(separator: ":").reduce(0) { $0 * 60 + (TimeInterval($1) ?? 0) }
                line.removeSubrange(range)
            }
            let parts = line
                .components(separatedBy: CharacterSet(charactersIn: ",\n"))
                .map { $0.withoutDirectionMarks }
                .filter { !$0.isEmpty }
            return RawBanner(
                id: identifier,
                appName: "FaceTime",
                title: parts.first ?? "",
                subtitle: "",
                body: (parts.dropFirst() + texts.dropFirst()).joined(separator: " · "),
                actions: actions(of: element),
                elapsed: elapsed
            )
        }
        if title.isEmpty && body.isEmpty {
            // Some other banner built like the call's: take what it says
            // from its plain elements rather than give up on it.
            let texts = looseTexts(in: element, depth: 0)
            title = texts.first ?? ""
            body = texts.dropFirst().joined(separator: " · ")
        }
        guard !(title.isEmpty && body.isEmpty) else { return nil }

        let leading = title.isEmpty ? body : title
        var appName: String
        if !leading.isEmpty, let range = description.range(of: ", " + leading) {
            appName = String(description[..<range.lowerBound])
        } else {
            appName = description.components(separatedBy: ", ").first ?? ""
        }
        appName = appName.withoutDirectionMarks
        var id = string(element, kAXIdentifierAttribute) ?? ""
        if id.isEmpty { id = appName }
        return RawBanner(
            id: id, appName: appName, title: title, subtitle: subtitle, body: body,
            actions: actions(of: element)
        )
    }

    /// Descriptions of the plain elements under a banner that has no named
    /// text fields, leaving out its buttons and the caller's picture.
    nonisolated private static func looseTexts(in element: AXUIElement, depth: Int) -> [String] {
        guard depth < 6 else { return [] }
        var found: [String] = []
        for child in children(of: element) {
            let role = string(child, kAXRoleAttribute) ?? ""
            if buttonRoles.contains(role) || string(child, kAXIdentifierAttribute) == "AvatarView" { continue }
            let text = (string(child, kAXValueAttribute) ?? string(child, kAXDescriptionAttribute) ?? "")
                .withoutDirectionMarks
            if !text.isEmpty {
                found.append(text)
            } else {
                found += looseTexts(in: child, depth: depth + 1)
            }
        }
        return found
    }

    nonisolated private static let buttonRoles: Set<String> = [
        kAXButtonRole as String, kAXPopUpButtonRole as String,
        kAXMenuButtonRole as String, kAXCheckBoxRole as String
    ]

    // MARK: Buttons

    /// Buttons that belong to the banner itself, not to what it asks.
    nonisolated private static let ignoredButtonTitles: Set<String> = [
        "kapat", "close", "göster", "show", "seçenekler", "options", "temizle", "clear",
        "tümünü temizle", "clear all", "tümünü sil", "sil", "delete", "delete all",
        "ayrıntıları göster", "show details", "ayrıntıları gizle", "hide details",
        "daha az göster", "show less", "gönder", "send"
    ]

    /// A banner's buttons: the ones macOS exposes as named actions (shown
    /// on hover), then any drawn as plain buttons.
    nonisolated private static func actions(of element: AXUIElement) -> [NotificationAction] {
        var found = namedActions(of: element)
        if found.isEmpty {
            for child in children(of: element)
            where (string(child, kAXSubroleAttribute) ?? "").hasPrefix("AXNotificationCenter") {
                found = namedActions(of: child)
                if !found.isEmpty { break }
            }
        }
        var titles = Set(found.map { $0.title.lowercased() })
        for button in buttons(in: element, depth: 0) {
            let title = buttonTitle(button)
            guard !title.isEmpty, !ignoredButtonTitles.contains(title.lowercased()),
                  titles.insert(title.lowercased()).inserted else { continue }
            // A button with a menu ("Decline" plus "Remind me later…")
            // has its plain meaning as a named action of its own; pressing
            // the button itself would open the menu instead.
            let own = namedActions(of: button).first { $0.title.lowercased() == title.lowercased() }
            found.append(NotificationAction(title: title, actionName: own?.actionName))
        }
        return found
    }

    nonisolated private static func actionNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
              let list = names as? [String] else { return [] }
        return list
    }

    nonisolated private static func namedActions(of element: AXUIElement) -> [NotificationAction] {
        let list = actionNames(of: element)
        return list.compactMap { name in
            guard name.hasPrefix("Name:") else { return nil }
            var described: CFString?
            var title = ""
            if AXUIElementCopyActionDescription(element, name as CFString, &described) == .success,
               let described = described as String? {
                title = described
            }
            if title.isEmpty || title == name {
                title = String(name.dropFirst("Name:".count)).components(separatedBy: "\n").first ?? ""
            }
            title = title.withoutDirectionMarks
            guard !title.isEmpty, !ignoredButtonTitles.contains(title.lowercased()) else { return nil }
            return NotificationAction(title: title, actionName: name)
        }
    }

    nonisolated private static func buttons(in element: AXUIElement, depth: Int) -> [AXUIElement] {
        guard depth < 6 else { return [] }
        var found: [AXUIElement] = []
        for child in children(of: element) {
            let role = string(child, kAXRoleAttribute) ?? ""
            if buttonRoles.contains(role) {
                found.append(child)
            } else {
                found += buttons(in: child, depth: depth + 1)
            }
        }
        return found
    }

    nonisolated private static func buttonTitle(_ button: AXUIElement) -> String {
        for attribute in [kAXTitleAttribute, kAXDescriptionAttribute] {
            if let text = string(button, attribute)?.withoutDirectionMarks, !text.isEmpty { return text }
        }
        return ""
    }

    nonisolated private static func locateBanner(
        identifier: String,
        in element: AXUIElement,
        depth: Int
    ) -> AXUIElement? {
        guard depth < 10 else { return nil }
        if (string(element, kAXSubroleAttribute) ?? "").hasPrefix("AXNotificationCenter") {
            return banner(from: element)?.id == identifier ? element : nil
        }
        for child in children(of: element) {
            if let found = locateBanner(identifier: identifier, in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    nonisolated private static func press(
        _ action: NotificationAction,
        onBanner identifier: String,
        processIdentifier pid: pid_t
    ) -> Bool {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.5)
        var banner: AXUIElement?
        for window in children(of: application)
        where string(window, kAXSubroleAttribute) == "AXSystemDialog" {
            banner = locateBanner(identifier: identifier, in: window, depth: 0)
            if banner != nil { break }
        }
        guard let banner else { return false }
        // Notification Center answers "failure" for buttons it did press.
        func done(_ result: AXError) -> Bool { result == .success || result == .failure }
        let button = buttons(in: banner, depth: 0).first {
            buttonTitle($0).lowercased() == action.title.lowercased()
        }
        if let name = action.actionName {
            // The element that lists the action is the one to ask.
            let holders = ([button].compactMap { $0 } + [banner] + children(of: banner))
                .filter { actionNames(of: $0).contains(name) }
            for holder in holders where done(AXUIElementPerformAction(holder, name as CFString)) {
                return true
            }
            return false
        }
        guard let button else { return false }
        return done(AXUIElementPerformAction(button, kAXPressAction as CFString))
    }

    #if DEBUG
    private var debugRequestActive = false
    /// Debug builds: read banners from a stand-in process instead of
    /// Notification Center (0 goes back to the real one).
    var debugCenterPID: pid_t? {
        didSet { hasBaseline = false }
    }

    /// Debug builds: a pretend call or AirDrop ("call", "airdrop",
    /// "answer", "clear").
    func debugRequest(_ command: String) {
        func make(_ app: String, _ title: String, _ body: String, _ buttons: [String]) -> CapturedNotification {
            CapturedNotification(
                id: "debug-request-\(buttons.joined())", appName: app, bundleIdentifier: nil,
                title: title, subtitle: "", body: body, date: .now,
                bannerIdentifier: "debug-request",
                actions: buttons.map { NotificationAction(title: $0, actionName: nil) }
            )
        }
        switch command {
        case "early":
            // What the Phone app's background start does.
            announceEarlyCall()
        case "call":
            debugRequestActive = true
            liveRequest = make("FaceTime", "Ahmet Yılmaz", "iPhone'unuzdan", ["Reddet", "Yanıtla"])
        case "airdrop":
            debugRequestActive = true
            liveRequest = make("AirDrop", "AirDrop", "Elif'in iPhone'u size bir fotoğraf paylaşmak istiyor.", ["Reddet", "Kabul Et"])
        case "answer":
            debugRequestActive = true
            liveRequest = make("FaceTime", "Ahmet Yılmaz", "iPhone'unuzdan", ["Sessiz", "Bitir"])
        default:
            debugRequestActive = false
            liveRequest = nil
        }
    }

    /// Debug builds: a notification that arrived `age` seconds ago.
    func debugInject(age: TimeInterval = 0) {
        let item = CapturedNotification(
            id: "debug-\(UUID().uuidString)",
            appName: "WhatsApp",
            bundleIdentifier: nil,
            title: age > 0 ? "Eski mesaj" : "Ahmet",
            subtitle: "",
            body: age > 0 ? "2 saat önce geldi" : "Akşam geliyor musun?",
            date: Date().addingTimeInterval(-age)
        )
        items.insert(item, at: 0)
        unreadCount += 1
        latest = item
        announcementRevision &+= 1
    }
    #endif

    /// Named texts ("title", "subtitle", "body") anywhere under a banner.
    nonisolated private static func collectTexts(
        in element: AXUIElement,
        depth: Int,
        fields: inout [String: String]
    ) {
        guard depth < 4 else { return }
        for child in children(of: element) {
            if string(child, kAXRoleAttribute) == kAXStaticTextRole as String {
                if let key = string(child, kAXIdentifierAttribute), !key.isEmpty,
                   let value = string(child, kAXValueAttribute), !value.isEmpty,
                   fields[key] == nil {
                    fields[key] = value
                }
            } else {
                collectTexts(in: child, depth: depth + 1, fields: &fields)
            }
        }
    }

    nonisolated private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &value
        ) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    nonisolated private static func string(
        _ element: AXUIElement,
        _ attribute: String
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else { return nil }
        return value as? String
    }
}

enum FocusTimerMode: String, CaseIterable, Identifiable {
    case timer
    case pomodoro

    var id: String { rawValue }
}

@MainActor
final class FocusTimerManager: ObservableObject {
    static let timerRange = 1...180
    static let focusRange = 5...90
    static let breakRange = 1...30
    /// Focus sessions in one Pomodoro round.
    static let sessionsPerRound = 4

    @Published var mode: FocusTimerMode = .pomodoro {
        // Re-picking the current mode must not wipe a running countdown.
        didSet { if mode != oldValue { reset() } }
    }
    @Published private(set) var isRunning = false
    @Published private(set) var isBreak = false
    @Published private(set) var remainingSeconds = 25 * 60

    @Published var timerMinutes: Int {
        didSet {
            durationChanged(timerMinutes, range: Self.timerRange, key: Key.timer, isCurrent: mode == .timer) {
                $0.timerMinutes = $1
            }
        }
    }
    @Published var focusMinutes: Int {
        didSet {
            durationChanged(focusMinutes, range: Self.focusRange, key: Key.focus, isCurrent: mode == .pomodoro && !isBreak) {
                $0.focusMinutes = $1
            }
        }
    }
    @Published var breakMinutes: Int {
        didSet {
            durationChanged(breakMinutes, range: Self.breakRange, key: Key.breakLength, isCurrent: mode == .pomodoro && isBreak) {
                $0.breakMinutes = $1
            }
        }
    }

    /// Run when a Pomodoro focus phase starts and when it ends (finished,
    /// skipped, reset or switched away), e.g. to turn Do Not Disturb on/off.
    var onFocusStart: (() -> Void)?
    var onFocusEnd: (() -> Void)?
    private var isFocusActive = false

    /// Bumped each time a countdown runs out; `lastFinish` says which.
    @Published private(set) var finishRevision = 0
    private(set) var lastFinish: TimerFinish = .timer

    /// Finished focus time and sessions, counted per calendar day.
    @Published private(set) var todayFocusSeconds = 0
    @Published private(set) var todaySessions = 0

    private enum Key {
        static let timer = "focus.timerMinutes"
        static let focus = "focus.pomodoroFocusMinutes"
        static let breakLength = "focus.pomodoroBreakMinutes"
        static let statsDay = "focus.statsDay"
        static let statsSeconds = "focus.statsSeconds"
        static let statsSessions = "focus.statsSessions"
    }

    private let defaults: UserDefaults
    private var timer: Timer?
    private var targetDate: Date?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func stored(_ key: String, _ fallback: Int, _ range: ClosedRange<Int>) -> Int {
            let value = defaults.object(forKey: key) as? Int ?? fallback
            return min(max(value, range.lowerBound), range.upperBound)
        }
        timerMinutes = stored(Key.timer, 10, Self.timerRange)
        focusMinutes = stored(Key.focus, 25, Self.focusRange)
        breakMinutes = stored(Key.breakLength, 5, Self.breakRange)
        remainingSeconds = focusMinutes * 60
        loadTodayStats()
        // A countdown must not run out, and count as a session, while the
        // lid is closed: sleeping pauses it.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                self.pause()
            }
        }
    }

    var totalSeconds: Int {
        switch mode {
        case .timer: timerMinutes * 60
        case .pomodoro: (isBreak ? breakMinutes : focusMinutes) * 60
        }
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return 1 - Double(remainingSeconds) / Double(totalSeconds)
    }

    /// How much of the dial is lit: the timer works like a kitchen timer
    /// (one turn is an hour), Pomodoro shows what's left of the phase.
    var dialFraction: Double {
        switch mode {
        case .timer:
            min(Double(remainingSeconds) / 3600, 1)
        case .pomodoro:
            totalSeconds > 0 ? Double(remainingSeconds) / Double(totalSeconds) : 0
        }
    }

    /// Focus sessions finished in the current round of four; a completed
    /// round shows all four until the next session starts a new one.
    var sessionsInRound: Int {
        guard todaySessions > 0 else { return 0 }
        return (todaySessions - 1) % Self.sessionsPerRound + 1
    }

    var formattedTime: String {
        let hours = remainingSeconds / 3600
        let minutes = remainingSeconds / 60 % 60
        let seconds = remainingSeconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    /// Up in single minutes to 10, then in fives; down the same way.
    static func steppedMinutes(_ value: Int, up: Bool, range: ClosedRange<Int>) -> Int {
        let next: Int
        if up {
            next = value < 10 ? value + 1 : (value / 5 + 1) * 5
        } else {
            next = value <= 10 ? value - 1 : (value - 1) / 5 * 5
        }
        return min(max(next, range.lowerBound), range.upperBound)
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    func reset() {
        endFocusIfActive()
        stopTimer()
        isRunning = false
        isBreak = false
        remainingSeconds = (mode == .pomodoro ? focusMinutes : timerMinutes) * 60
    }

    func skipPhase() {
        guard mode == .pomodoro else { return }
        endFocusIfActive()
        stopTimer()
        isRunning = false
        isBreak.toggle()
        remainingSeconds = totalSeconds
    }

    private func endFocusIfActive() {
        guard isFocusActive else { return }
        isFocusActive = false
        onFocusEnd?()
    }

    private func durationChanged(
        _ value: Int,
        range: ClosedRange<Int>,
        key: String,
        isCurrent: Bool,
        assign: (FocusTimerManager, Int) -> Void
    ) {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        guard clamped == value else {
            assign(self, clamped)
            return
        }
        defaults.set(value, forKey: key)
        // A new length for the phase on the dial applies right away, unless
        // it is counting down.
        guard isCurrent, !isRunning else { return }
        stopTimer()
        remainingSeconds = totalSeconds
    }

    private func start() {
        if remainingSeconds <= 0 { reset() }
        if mode == .pomodoro, !isBreak, !isFocusActive {
            isFocusActive = true
            onFocusStart?()
        }
        isRunning = true
        targetDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func pause() {
        tick()
        stopTimer()
        isRunning = false
    }

    private func tick() {
        guard let targetDate else { return }
        remainingSeconds = max(Int(ceil(targetDate.timeIntervalSinceNow)), 0)
        guard remainingSeconds == 0 else { return }
        stopTimer()
        isRunning = false
        if NSSound(named: "Glass")?.play() != true { NSSound.beep() }
        if mode == .timer || !isBreak {
            recordFinishedFocus(seconds: totalSeconds, countsAsSession: mode == .pomodoro)
        }
        lastFinish = mode == .timer ? .timer : (isBreak ? .breakDone : .focusDone)
        if lastFinish == .focusDone { endFocusIfActive() }
        if mode == .pomodoro {
            isBreak.toggle()
            remainingSeconds = totalSeconds
        }
        finishRevision &+= 1
    }

    private func recordFinishedFocus(seconds: Int, countsAsSession: Bool) {
        loadTodayStats()
        todayFocusSeconds += seconds
        if countsAsSession { todaySessions += 1 }
        defaults.set(todayFocusSeconds, forKey: Key.statsSeconds)
        defaults.set(todaySessions, forKey: Key.statsSessions)
    }

    /// Starts the counts from zero on a new day.
    func loadTodayStats() {
        let today = Self.dayKey(Date())
        if defaults.string(forKey: Key.statsDay) != today {
            defaults.set(today, forKey: Key.statsDay)
            defaults.set(0, forKey: Key.statsSeconds)
            defaults.set(0, forKey: Key.statsSessions)
        }
        let seconds = defaults.integer(forKey: Key.statsSeconds)
        let sessions = defaults.integer(forKey: Key.statsSessions)
        if seconds != todayFocusSeconds { todayFocusSeconds = seconds }
        if sessions != todaySessions { todaySessions = sessions }
    }

    private static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        targetDate = nil
    }
}

@MainActor
final class KeepAwakeManager: ObservableObject {
    @Published private(set) var isActive = false
    private var activity: NSObjectProtocol?

    func toggle() {
        setActive(!isActive)
    }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        if active {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .idleDisplaySleepDisabled, .userInitiated],
                reason: "islo. Keep Awake"
            )
        } else if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        isActive = active
    }
}

@MainActor
final class FileShelfManager: ObservableObject {
    @Published private(set) var items: [URL] = []
    /// True while the user holds files being dragged anywhere on screen.
    @Published private(set) var isFileDragActive = false
    private let defaultsKey = "dashboard.fileShelf.items"
    /// When each file went on the shelf, by path, for clearing it later.
    private let addedKey = "dashboard.fileShelf.addedAt"
    private var addedAt: [String: Date] = [:]
    /// Shelved files out of reach at launch (an unplugged drive, a folder
    /// macOS hasn't opened up yet). They stay saved, just not shown, so a
    /// moment without access never takes them off the shelf for good.
    private var unreachable: [String] = []
    private var dragMonitors: [Any] = []
    private var dragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
    private var dragEndTimer: Timer?

    /// Mouse monitors only see other apps' events, which is exactly a file
    /// being dragged out of Finder or elsewhere. A new drag writes to the
    /// drag pasteboard, so a changed count with file URLs means files are
    /// in hand. Mouse events need no extra permission.
    func startDragMonitoring() {
        guard dragMonitors.isEmpty else { return }
        let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] _ in
            Task { @MainActor in
                self?.dragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
            }
        }
        let dragged = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) {
            [weak self] _ in
            Task { @MainActor in self?.checkForFileDrag() }
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) {
            [weak self] _ in
            Task { @MainActor in self?.endFileDrag() }
        }
        dragMonitors = [down, dragged, up].compactMap { $0 }
    }

    func stopDragMonitoring() {
        dragMonitors.forEach(NSEvent.removeMonitor)
        dragMonitors.removeAll()
        endFileDrag()
    }

    private func checkForFileDrag() {
        guard !isFileDragActive else { return }
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragPasteboardChangeCount,
              pasteboard.types?.contains(.fileURL) == true else { return }
        isFileDragActive = true

        // A drop onto islo. itself is delivered to this app, where the global
        // mouse-up monitor can't see it, so also watch the button directly.
        dragEndTimer?.invalidate()
        dragEndTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                if NSEvent.pressedMouseButtons & 1 == 0 { self?.endFileDrag() }
            }
        }
    }

    private func endFileDrag() {
        dragEndTimer?.invalidate()
        dragEndTimer = nil
        dragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
        if isFileDragActive { isFileDragActive = false }
    }

    /// Small previews for the shelf grid, made by Quick Look.
    @Published private(set) var thumbnails: [URL: NSImage] = [:]
    private var detailsCache: [URL: ShelfItemDetails] = [:]

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        items = paths.map(URL.init(fileURLWithPath:)).filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        let shown = Set(items.map(\.path))
        unreachable = paths.filter { !shown.contains(URL(fileURLWithPath: $0).path) }
        let stored = UserDefaults.standard.dictionary(forKey: addedKey) as? [String: Double] ?? [:]
        // Files shelved before islo. kept dates count from now.
        for path in items.map(\.path) + unreachable {
            addedAt[path] = stored[path].map(Date.init(timeIntervalSince1970:)) ?? Date()
        }
        items.forEach(makeThumbnail)
        // Only the dates are written here; the list stays exactly as it was.
        UserDefaults.standard.set(addedAt.mapValues(\.timeIntervalSince1970), forKey: addedKey)
    }

    func receive(_ providers: [NSItemProvider]) -> Bool {
        let matching = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        for provider in matching {
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { [weak self] item, _ in
                guard let url = Self.url(from: item) else { return }
                Task { @MainActor in self?.add(url) }
            }
        }
        return !matching.isEmpty
    }

    func add(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        items.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        unreachable.removeAll { URL(fileURLWithPath: $0).standardizedFileURL == url.standardizedFileURL }
        items.insert(url, at: 0)
        items = Array(items.prefix(60))
        addedAt[url.path] = Date()
        persist()
        makeThumbnail(url)
    }

    func remove(_ url: URL) {
        items.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        unreachable.removeAll { URL(fileURLWithPath: $0).standardizedFileURL == url.standardizedFileURL }
        thumbnails[url] = nil
        persist()
    }

    /// Empties the shelf. The files themselves stay where they are.
    func clear() {
        items.removeAll()
        unreachable.removeAll()
        thumbnails.removeAll()
        persist()
    }

    /// Takes files off the shelf `interval` after they were added; the files
    /// themselves stay where they are.
    func removeItems(olderThan interval: TimeInterval?) {
        guard let interval, !(items.isEmpty && unreachable.isEmpty) else { return }
        let cutoff = Date().addingTimeInterval(-interval)
        let expired = items.filter { (addedAt[$0.path] ?? Date()) < cutoff }
        let expiredUnreachable = unreachable.filter { (addedAt[$0] ?? Date()) < cutoff }
        guard !expired.isEmpty || !expiredUnreachable.isEmpty else { return }
        items.removeAll { expired.contains($0) }
        unreachable.removeAll { expiredUnreachable.contains($0) }
        expired.forEach { thumbnails[$0] = nil }
        persist()
    }

    func details(for url: URL) -> ShelfItemDetails {
        if let cached = detailsCache[url] { return cached }
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .isDirectoryKey])
        let type = values?.contentType
        let made = ShelfItemDetails(
            isImage: type?.conforms(to: .image) ?? false,
            kind: ShelfItemDetails.kind(for: type, isDirectory: values?.isDirectory ?? false),
            size: values?.fileSize.map {
                ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
            }
        )
        detailsCache[url] = made
        return made
    }

    private func makeThumbnail(_ url: URL) {
        guard thumbnails[url] == nil else { return }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 160, height: 100),
            scale: 2,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            [weak self] representation, _ in
            guard let image = representation?.nsImage else { return }
            Task { @MainActor in self?.thumbnails[url] = image }
        }
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func sendViaAirDrop(_ url: URL) {
        sendViaAirDrop([url])
    }

    /// Sends dropped files straight to AirDrop without keeping them on the
    /// shelf.
    func sendViaAirDrop(_ providers: [NSItemProvider]) -> Bool {
        let matching = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !matching.isEmpty else { return false }

        let group = DispatchGroup()
        let collected = CollectedURLs()
        for provider in matching {
            group.enter()
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { item, _ in
                if let url = Self.url(from: item) { collected.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            let urls = collected.all
            guard !urls.isEmpty else { return }
            Task { @MainActor in self?.sendViaAirDrop(urls) }
        }
        return true
    }

    private func sendViaAirDrop(_ urls: [URL]) {
        // The AirDrop picker is a window of its own; bring it forward.
        NSApp.activate(ignoringOtherApps: true)
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
    }

    private func persist() {
        let paths = items.map(\.path) + unreachable.filter { path in
            !items.contains { $0.path == path }
        }
        addedAt = addedAt.filter { paths.contains($0.key) }
        UserDefaults.standard.set(addedAt.mapValues(\.timeIntervalSince1970), forKey: addedKey)
        UserDefaults.standard.set(paths, forKey: defaultsKey)
    }

    /// Gathers URLs that item providers deliver on background queues.
    private final class CollectedURLs: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []

        func append(_ url: URL) {
            lock.lock()
            urls.append(url)
            lock.unlock()
        }

        var all: [URL] {
            lock.lock()
            defer { lock.unlock() }
            return urls
        }
    }

    nonisolated private static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        if let string = item as? String { return URL(string: string) }
        return nil
    }
}

struct ShelfItemDetails {
    let isImage: Bool
    let kind: String
    let size: String?

    static func kind(for type: UTType?, isDirectory: Bool) -> String {
        if isDirectory { return "folder" }
        guard let type else { return "file" }
        if type.conforms(to: .image) { return "image" }
        if type.conforms(to: .pdf) { return "pdf" }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return "video" }
        if type.conforms(to: .audio) { return "audio" }
        if type.conforms(to: .archive) { return "archive" }
        if type.conforms(to: .text) || type.conforms(to: .sourceCode) { return "text" }
        return "file"
    }
}
