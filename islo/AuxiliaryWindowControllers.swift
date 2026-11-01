import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private let router = SettingsRouter()

    init(settings: AppSettings, onShowOnboarding: @escaping () -> Void) {
        let rootView = SettingsView(
            settings: settings,
            router: router,
            onShowOnboarding: onShowOnboarding
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 690),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = settings.language.value(
            turkish: "islo. Ayarları",
            english: "islo. Settings"
        )
        // The dark islo. look runs edge to edge, under the traffic lights.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0.035, green: 0.035, blue: 0.045, alpha: 1)
        let hostingController = NSHostingController(rootView: rootView)
        // The window sets the size; the view fills it, titlebar area included.
        hostingController.sizingOptions = []
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        centerOnPrimaryDisplay(
            window,
            contentSize: NSSize(width: 940, height: 690)
        )

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func present(destination: SettingsDestination? = nil, feature: String? = nil) {
        if let destination {
            router.requestedDestination = destination
        }
        if let feature {
            router.requestedFeature = feature
        }
        router.isWindowVisible = true
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        // NSWindowController may apply its cascade position after showWindow.
        // Center on the next run-loop pass so our final geometry wins.
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else { return }
            centerOnPrimaryDisplay(
                window,
                contentSize: NSSize(width: 940, height: 690)
            )
            window.makeKeyAndOrderFront(nil)
        }
    }
}

@MainActor
final class OnboardingWindowController: NSWindowController {
    init(settings: AppSettings, onComplete: @escaping () -> Void) {
        let rootView = OnboardingView(
            settings: settings,
            onComplete: onComplete
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = settings.language.value(
            turkish: "islo.'ya Hoş Geldiniz",
            english: "Welcome to islo."
        )
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0.035, green: 0.035, blue: 0.045, alpha: 1)
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = []
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        centerOnPrimaryDisplay(
            window,
            contentSize: NSSize(width: 1040, height: 680)
        )

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The guide's goodbye: the window shrinks and flies up into the
    /// notch, then `completion` runs.
    func flyIntoNotch(completion: @escaping () -> Void) {
        guard let window, let contentView = window.contentView,
              let screen = window.screen ?? NSScreen.screens.first,
              let snapshot = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
            close()
            completion()
            return
        }
        contentView.cacheDisplay(in: contentView.bounds, to: snapshot)
        let image = NSImage(size: contentView.bounds.size)
        image.addRepresentation(snapshot)

        // A borderless copy of the window that can shrink smoothly.
        let ghost = NSWindow(contentRect: window.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        ghost.isOpaque = false
        ghost.backgroundColor = .clear
        ghost.hasShadow = true
        ghost.level = .floating
        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 12
        imageView.layer?.masksToBounds = true
        ghost.contentView = imageView
        ghost.orderFront(nil)
        window.orderOut(nil)

        // Frame by frame: the window animator doesn't move borderless
        // windows reliably.
        let start = ghost.frame
        let target = NSRect(x: screen.frame.midX - 60, y: screen.frame.maxY - 22, width: 120, height: 16)
        let duration = 0.68
        let began = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            let linear = min((CACurrentMediaTime() - began) / duration, 1)
            // Ease in: slow start, quick finish into the notch.
            let eased = linear * linear * (2.2 - 1.2 * linear)
            func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * eased }
            ghost.setFrame(NSRect(
                x: mix(start.minX, target.minX),
                y: mix(start.minY, target.minY),
                width: mix(start.width, target.width),
                height: mix(start.height, target.height)
            ), display: true)
            ghost.alphaValue = linear < 0.55 ? 1 : max(0, 1 - (linear - 0.55) / 0.45)
            guard linear >= 1 else { return }
            timer.invalidate()
            ghost.orderOut(nil)
            self?.close()
            completion()
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    func present() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)


        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else { return }
            centerOnPrimaryDisplay(
                window,
                contentSize: NSSize(width: 1040, height: 680)
            )
            window.makeKeyAndOrderFront(nil)
        }
    }
}

@MainActor
private func centerOnPrimaryDisplay(
    _ window: NSWindow,
    contentSize: NSSize
) {
    guard let screen = NSScreen.screens.first ?? NSScreen.main else {
        window.center()
        return
    }

    window.setContentSize(contentSize)
    let visibleFrame = screen.visibleFrame
    let windowSize = window.frame.size
    window.setFrameOrigin(
        NSPoint(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.midY - windowSize.height / 2
        )
    )
}

extension SettingsWindowController: NSWindowDelegate {
    /// The window is only hidden on close, so its views keep running;
    /// this stops their once-a-second permission checks.
    func windowWillClose(_ notification: Notification) {
        router.isWindowVisible = false
    }
}
