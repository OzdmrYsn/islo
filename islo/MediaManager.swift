import AppKit
import Combine
import Foundation

enum MediaSource: String, Sendable {
    case none
    case appleMusic
    case spotify
    /// Plays in a browser tab or a web app, so it has no bundle of its own.
    case youtubeMusic

    var displayName: String {
        switch self {
        case .none: "No Media"
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        case .youtubeMusic: "YouTube Music"
        }
    }

    var bundleIdentifier: String? {
        switch self {
        case .none, .youtubeMusic: nil
        case .appleMusic: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    /// YouTube Music has no shuffle or repeat that can be reached from outside.
    var supportsShuffleAndRepeat: Bool {
        self == .appleMusic || self == .spotify
    }

    fileprivate static let players: [MediaSource] = [
        .appleMusic,
        .spotify
    ]
}

enum PlaybackRepeatMode: String, Sendable {
    case off
    case all
    case one
}

private struct MediaSnapshot: Sendable {
    let source: MediaSource
    let trackName: String
    let artistName: String
    let albumName: String
    let isPlaying: Bool
    let position: TimeInterval
    let duration: TimeInterval
    let artworkURL: URL?
    let trackIdentifier: String
    let isShuffleEnabled: Bool
    let repeatMode: PlaybackRepeatMode
}

private enum PlayerCommand: Sendable {
    case togglePlayPause
    case next
    case previous
    case seek(TimeInterval)
    case setShuffle(Bool)
    case setRepeat(PlaybackRepeatMode)
}

private enum AppleScriptBridgeError: LocalizedError {
    case couldNotCreateScript
    case executionFailed(message: String, number: Int?)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .couldNotCreateScript:
            "AppleScript could not be created."
        case let .executionFailed(message, number):
            if number == -1743 {
                "Automation access was denied. Enable islo. for Music/Spotify "
                    + "in System Settings > Privacy & Security > Automation."
            } else if number == -1742 {
                "The App Sandbox blocked media automation. Verify the Music and "
                    + "Spotify scripting-target entitlements."
            } else if let number {
                "AppleScript error \(number): \(message)"
            } else {
                "AppleScript error: \(message)"
            }
        case .invalidResponse:
            "The media player returned an invalid AppleScript response."
        }
    }
}

/// Serializes AppleScript work away from the main actor. Only Sendable value
/// types leave this actor; NSAppleScript and NSAppleEventDescriptor stay inside.
private actor AppleScriptBridge {
    /// The scripts that run on every poll, compiled once. Compiling is most
    /// of what a poll costs.
    private var compiledScripts: [String: NSAppleScript] = [:]

    func snapshot(for source: MediaSource) throws -> MediaSnapshot {
        let descriptor = try execute(scriptForSnapshot(source), reusable: true)
        guard descriptor.numberOfItems >= 10 else {
            throw AppleScriptBridgeError.invalidResponse
        }

        let state = string(in: descriptor, at: 4).lowercased()
        let rawIdentifier = string(in: descriptor, at: 8)
        let trackName = string(in: descriptor, at: 1)
        let artistName = string(in: descriptor, at: 2)
        let albumName = string(in: descriptor, at: 3)
        let fallbackIdentifier = [trackName, artistName, albumName]
            .joined(separator: "|")

        let artworkURLString = string(in: descriptor, at: 7)
        let artworkURL: URL?
        if let candidate = URL(string: artworkURLString),
           let scheme = candidate.scheme?.lowercased(),
           scheme == "https" || scheme == "http" {
            artworkURL = candidate
        } else {
            artworkURL = nil
        }

        let repeatMode = PlaybackRepeatMode(
            rawValue: string(in: descriptor, at: 10).lowercased()
        ) ?? .off

        return MediaSnapshot(
            source: source,
            trackName: trackName,
            artistName: artistName,
            albumName: albumName,
            isPlaying: state == "playing",
            position: max(0, number(in: descriptor, at: 5)),
            duration: max(0, number(in: descriptor, at: 6)),
            artworkURL: artworkURL,
            trackIdentifier: rawIdentifier.isEmpty
                ? fallbackIdentifier
                : rawIdentifier,
            isShuffleEnabled: descriptor.atIndex(9)?.booleanValue ?? false,
            repeatMode: repeatMode
        )
    }

    func perform(_ command: PlayerCommand, on source: MediaSource) throws {
        guard source != .none else { return }
        if source == .youtubeMusic {
            switch command {
            case .togglePlayPause: SystemMediaRemote.send(.togglePlayPause)
            case .next: SystemMediaRemote.send(.nextTrack)
            case .previous: SystemMediaRemote.send(.previousTrack)
            case let .seek(value): SystemMediaRemote.seek(to: value)
            case .setShuffle, .setRepeat: break
            }
            return
        }

        let applicationIdentifier = source == .appleMusic
            ? "com.apple.Music"
            : "com.spotify.client"
        let commandText: String

        switch command {
        case .togglePlayPause:
            commandText = "playpause"
        case .next:
            commandText = "next track"
        case .previous:
            commandText = "previous track"
        case let .seek(value):
            let safeValue = value.isFinite ? max(0, value) : 0
            let literal = String(
                format: "%.3f",
                locale: Locale(identifier: "en_US_POSIX"),
                safeValue
            )
            commandText = "set player position to \(literal)"
        case let .setShuffle(enabled):
            if source == .appleMusic {
                commandText = """
                if \(enabled) then set shuffle mode to songs
                set shuffle enabled to \(enabled)
                """
            } else {
                commandText = "set shuffling to \(enabled)"
            }
        case let .setRepeat(mode):
            if source == .appleMusic {
                commandText = "set song repeat to \(mode.rawValue)"
            } else {
                commandText = "set repeating to \(mode != .off)"
            }
        }

        _ = try execute(
            """
            if not (application id "\(applicationIdentifier)" is running) then return
            tell application id "\(applicationIdentifier)"
                \(commandText)
            end tell
            """
        )
    }

    /// Whether one of the browser's tabs is on YouTube Music. Chromium
    /// browsers and Safari answer this the same way.
    func hasYouTubeMusicTab(browser bundleIdentifier: String) throws -> Bool {
        let descriptor = try execute(
            """
            if not (application id "\(bundleIdentifier)" is running) then return false
            tell application id "\(bundleIdentifier)"
                set windowCount to count of windows
                repeat with windowIndex from 1 to windowCount
                    try
                        set addresses to URL of tabs of window windowIndex
                        repeat with anAddress in addresses
                            try
                                if (anAddress as text) contains "music.youtube.com" then return true
                            end try
                        end repeat
                    end try
                end repeat
            end tell
            return false
            """,
            reusable: true
        )
        return descriptor.booleanValue
    }

    func systemVolume() throws -> Double {
        let descriptor = try execute(
            """
            use scripting additions
            return output volume of (get volume settings)
            """,
            reusable: true
        )
        return min(max(descriptor.doubleValue / 100, 0), 1)
    }

    func setSystemVolume(_ normalizedValue: Double) throws -> Double {
        let value = normalizedValue.isFinite ? normalizedValue : 0
        let percentage = Int((min(max(value, 0), 1) * 100).rounded())
        let descriptor = try execute(
            """
            use scripting additions
            set volume output volume \(percentage)
            if \(percentage) > 0 then set volume output muted false
            return output volume of (get volume settings)
            """
        )
        return min(max(descriptor.doubleValue / 100, 0), 1)
    }

    func appleMusicArtworkData() throws -> Data? {
        let descriptor = try execute(
            """
            if not (application id "com.apple.Music" is running) then ¬
                return {false, ""}
            tell application id "com.apple.Music"
                try
                    if (count of artworks of current track) > 0 then
                        return {true, raw data of artwork 1 of current track}
                    end if
                    return {false, ""}
                on error
                    return {false, ""}
                end try
            end tell
            """
        )

        guard
            descriptor.numberOfItems >= 2,
            descriptor.atIndex(1)?.booleanValue == true,
            let data = descriptor.atIndex(2)?.data,
            !data.isEmpty
        else {
            return nil
        }
        return data
    }

    private func execute(_ source: String, reusable: Bool = false) throws -> NSAppleEventDescriptor {
        let script: NSAppleScript
        if reusable, let compiled = compiledScripts[source] {
            script = compiled
        } else {
            guard let created = NSAppleScript(source: source) else {
                throw AppleScriptBridgeError.couldNotCreateScript
            }
            script = created
            if reusable { compiledScripts[source] = created }
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String
                ?? errorInfo.description
            let number = errorInfo[NSAppleScript.errorNumber] as? Int
            throw AppleScriptBridgeError.executionFailed(
                message: message,
                number: number
            )
        }

        return result
    }

    private func string(
        in descriptor: NSAppleEventDescriptor,
        at index: Int
    ) -> String {
        descriptor.atIndex(index)?.stringValue ?? ""
    }

    private func number(
        in descriptor: NSAppleEventDescriptor,
        at index: Int
    ) -> Double {
        descriptor.atIndex(index)?.doubleValue ?? 0
    }

    private func scriptForSnapshot(_ source: MediaSource) -> String {
        switch source {
        case .appleMusic:
            return """
            if not (application id "com.apple.Music" is running) then ¬
                return {"", "", "", "stopped", 0, 0, "", "", false, "off"}
            tell application id "com.apple.Music"
                set stateText to (player state as text)
                try
                    set currentTrack to current track
                on error
                    return {"", "", "", stateText, 0, 0, "", "", false, "off"}
                end try

                set trackName to ""
                set artistName to ""
                set albumName to ""
                set playerPosition to 0
                set trackDuration to 0
                set trackID to ""
                set shuffleState to false
                set repeatState to "off"

                try
                    set trackName to name of currentTrack as text
                end try
                try
                    set artistName to artist of currentTrack as text
                end try
                try
                    set albumName to album of currentTrack as text
                end try
                try
                    set playerPosition to player position
                end try
                try
                    set trackDuration to duration of currentTrack
                end try
                try
                    set trackID to persistent ID of currentTrack as text
                end try
                try
                    set shuffleState to shuffle enabled
                end try
                try
                    set repeatState to song repeat as text
                end try

                return {trackName, artistName, albumName, stateText, ¬
                    playerPosition, trackDuration, "", trackID, ¬
                    shuffleState, repeatState}
            end tell
            """

        case .spotify:
            return """
            if not (application id "com.spotify.client" is running) then ¬
                return {"", "", "", "stopped", 0, 0, "", "", false, "off"}
            tell application id "com.spotify.client"
                set stateText to (player state as text)
                try
                    set currentTrack to current track
                on error
                    return {"", "", "", stateText, 0, 0, "", "", false, "off"}
                end try

                set trackName to ""
                set artistName to ""
                set albumName to ""
                set playerPosition to 0
                set trackDuration to 0
                set artworkURL to ""
                set trackID to ""
                set shuffleState to false
                set repeatState to "off"

                try
                    set trackName to name of currentTrack as text
                end try
                try
                    set artistName to artist of currentTrack as text
                end try
                try
                    set albumName to album of currentTrack as text
                end try
                try
                    set playerPosition to player position
                end try
                try
                    set trackDuration to (duration of currentTrack) / 1000
                end try
                try
                    set artworkURL to artwork url of currentTrack as text
                end try
                try
                    set trackID to spotify url of currentTrack as text
                end try
                try
                    set shuffleState to shuffling
                end try
                try
                    if repeating then set repeatState to "all"
                end try

                return {trackName, artistName, albumName, stateText, ¬
                    playerPosition, trackDuration, artworkURL, trackID, ¬
                    shuffleState, repeatState}
            end tell
            """

        case .none, .youtubeMusic:
            return "return {\"\", \"\", \"\", \"stopped\", 0, 0, \"\", \"\", false, \"off\"}"
        }
    }
}

/// What macOS itself lists as playing right now, whichever app it is.
private struct SystemNowPlayingInfo: Decodable, Sendable {
    var bundle = ""
    var parent = ""
    var title = ""
    var artist = ""
    var album = ""
    var duration = 0.0
    var elapsed = 0.0
    /// When `elapsed` was true, in seconds since 1970.
    var timestamp = 0.0
    var rate = 0.0
    var playing = false

    private enum CodingKeys: String, CodingKey {
        case bundle, parent, title, artist, album, duration, elapsed, timestamp, rate, playing
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        bundle = (try? values.decode(String.self, forKey: .bundle)) ?? ""
        parent = (try? values.decode(String.self, forKey: .parent)) ?? ""
        title = (try? values.decode(String.self, forKey: .title)) ?? ""
        artist = (try? values.decode(String.self, forKey: .artist)) ?? ""
        album = (try? values.decode(String.self, forKey: .album)) ?? ""
        duration = (try? values.decode(Double.self, forKey: .duration)) ?? 0
        elapsed = (try? values.decode(Double.self, forKey: .elapsed)) ?? 0
        timestamp = (try? values.decode(Double.self, forKey: .timestamp)) ?? 0
        rate = (try? values.decode(Double.self, forKey: .rate)) ?? 0
        playing = (try? values.decode(Bool.self, forKey: .playing)) ?? false
    }

    /// The app the sound belongs to: a browser's helper reports its browser.
    var owner: String { parent.isEmpty ? bundle : parent }
}

/// Reads the system's now-playing entry. macOS only tells Apple's own
/// processes, so the question is asked through `osascript`, kept running as
/// one small helper that answers a line at a time.
private final class SystemNowPlayingReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.ozdmrysn.islo.now-playing")
    private var process: Process?
    private var requestPipe: FileHandle?
    private var responseDescriptor: Int32 = -1
    private var retryAfter = Date.distantPast

    private static let helperScript = """
    ObjC.import('Foundation');
    function run() {
      $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/').load;
      const Request = $.NSClassFromString('MRNowPlayingRequest');
      const input = $.NSFileHandle.fileHandleWithStandardInput;
      const output = $.NSFileHandle.fileHandleWithStandardOutput;
      const prefix = 'kMRMediaRemoteNowPlayingInfo';
      const value = (info, key) => {
        try { const v = info.objectForKey(prefix + key); return (v === undefined || v.isNil()) ? null : v; }
        catch (e) { return null; }
      };
      const text = (info, key) => { const v = value(info, key); return v ? ObjC.unwrap(v.description) : ''; };
      const number = (info, key) => { const v = value(info, key); return v ? (parseFloat(ObjC.unwrap(v.description)) || 0) : 0; };
      while (true) {
        const data = input.availableData;
        if (data.length === 0) break;
        const command = ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding)).trim();
        const out = {};
        try {
          const info = Request.localNowPlayingItem.nowPlayingInfo;
          try {
            const client = Request.localNowPlayingPlayerPath.client;
            out.bundle = ObjC.unwrap(client.bundleIdentifier) || '';
            out.parent = ObjC.unwrap(client.parentApplicationBundleIdentifier) || '';
          } catch (e) {}
          out.title = text(info, 'Title');
          out.artist = text(info, 'Artist');
          out.album = text(info, 'Album');
          out.duration = number(info, 'Duration');
          out.elapsed = number(info, 'ElapsedTime');
          out.rate = number(info, 'PlaybackRate');
          const stamp = value(info, 'Timestamp');
          out.timestamp = stamp ? stamp.timeIntervalSince1970 : 0;
          out.playing = Request.localIsPlaying ? true : false;
        } catch (e) {}
        output.writeData($(JSON.stringify(out) + '\\n').dataUsingEncoding($.NSUTF8StringEncoding));
      }
    }
    """

    func info() async -> SystemNowPlayingInfo? {
        guard let data = await request("info") else { return nil }
        return try? JSONDecoder().decode(SystemNowPlayingInfo.self, from: data)
    }

    func stop() {
        queue.async { self.tearDown() }
    }

    private func request(_ command: String, timeout: TimeInterval = 2) async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.exchange(command, timeout: timeout))
            }
        }
    }

    private func exchange(_ command: String, timeout: TimeInterval) -> Data? {
        guard launchIfNeeded(), let requestPipe else { return nil }
        do {
            try requestPipe.write(contentsOf: Data((command + "\n").utf8))
        } catch {
            fail()
            return nil
        }

        var line = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { fail(); return nil }
            var descriptor = pollfd(fd: responseDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, Int32(remaining * 1000))
            if ready < 0, errno == EINTR { continue }
            guard ready > 0 else { fail(); return nil }
            let count = read(responseDescriptor, &buffer, buffer.count)
            guard count > 0 else { fail(); return nil }
            line.append(contentsOf: buffer[0..<count])
            if buffer[count - 1] == 0x0A { return line }
        }
    }

    private func launchIfNeeded() -> Bool {
        if let process, process.isRunning { return true }
        tearDown()
        guard retryAfter <= Date() else { return false }

        // Writing to a helper that has gone away must not take the app down.
        signal(SIGPIPE, SIG_IGN)

        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        helper.arguments = ["-l", "JavaScript", "-e", Self.helperScript]
        let requests = Pipe()
        let responses = Pipe()
        helper.standardInput = requests
        helper.standardOutput = responses
        helper.standardError = FileHandle.nullDevice
        do {
            try helper.run()
        } catch {
            retryAfter = Date().addingTimeInterval(60)
            return false
        }
        process = helper
        requestPipe = requests.fileHandleForWriting
        responsePipe = responses
        responseDescriptor = responses.fileHandleForReading.fileDescriptor
        return true
    }

    /// Kept so the reading end stays open for as long as the helper lives.
    private var responsePipe: Pipe?

    private func fail() {
        tearDown()
        retryAfter = Date().addingTimeInterval(20)
    }

    private func tearDown() {
        if let process, process.isRunning { process.terminate() }
        try? requestPipe?.close()
        process = nil
        requestPipe = nil
        responsePipe = nil
        responseDescriptor = -1
    }
}

/// The system-wide media keys: whatever is playing answers them.
private enum SystemMediaRemote {
    enum Command: UInt32 {
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    private typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool
    private typealias SetElapsedTime = @convention(c) (Double) -> Void

    private static let library = dlopen(
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
        RTLD_NOW
    )

    static func send(_ command: Command) {
        guard let library, let symbol = dlsym(library, "MRMediaRemoteSendCommand") else {
            return
        }
        _ = unsafeBitCast(symbol, to: SendCommand.self)(command.rawValue, nil)
    }

    static func seek(to time: TimeInterval) {
        guard let library, let symbol = dlsym(library, "MRMediaRemoteSetElapsedTime") else {
            return
        }
        unsafeBitCast(symbol, to: SetElapsedTime.self)(time.isFinite ? max(0, time) : 0)
    }
}

/// The system keeps a browser's cover to itself, so a song playing in
/// YouTube Music gets its cover looked up by name. A song that can't be
/// matched with confidence keeps the plain tile rather than a wrong cover.
private enum CoverLookup {
    private struct Response: Decodable {
        struct Song: Decodable {
            let trackName: String?
            let artistName: String?
            let artworkUrl100: String?
        }
        let results: [Song]
    }

    static func cover(title: String, artist: String) async throws -> Data? {
        let wantedTitle = simplified(title)
        let wantedArtists = artist
            .components(separatedBy: CharacterSet(charactersIn: ",&"))
            .map(simplified)
            .filter { !$0.isEmpty }
        guard !wantedTitle.isEmpty, let firstArtist = wantedArtists.first else { return nil }

        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: "\(wantedTitle) \(firstArtist)"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "8")
        ]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let (body, _) = try await URLSession.shared.data(for: request)
        let songs = (try? JSONDecoder().decode(Response.self, from: body))?.results ?? []

        let match = songs.first { song in
            let foundTitle = simplified(song.trackName ?? "")
            let foundArtist = simplified(song.artistName ?? "")
            guard !foundTitle.isEmpty, !foundArtist.isEmpty else { return false }
            let titleMatches = foundTitle == wantedTitle
                || foundTitle.hasPrefix(wantedTitle) || wantedTitle.hasPrefix(foundTitle)
            let artistMatches = wantedArtists.contains {
                foundArtist.contains($0) || $0.contains(foundArtist)
            }
            return titleMatches && artistMatches
        }
        guard
            let small = match?.artworkUrl100,
            let coverURL = URL(string: small.replacingOccurrences(of: "100x100", with: "600x600"))
        else {
            return nil
        }
        let (image, response) = try await URLSession.shared.data(from: coverURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return nil
        }
        return image.count <= 10_000_000 ? image : nil
    }

    /// Lowercase, without accents, brackets ("(Remastered)") or punctuation.
    private static func simplified(_ text: String) -> String {
        var result = text.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        for pattern in ["\\([^)]*\\)", "\\[[^\\]]*\\]", "[^\\p{L}\\p{N} ]"] {
            result = result.replacingOccurrences(
                of: pattern, with: " ", options: .regularExpression
            )
        }
        return result.split(separator: " ").joined(separator: " ")
    }
}

/// Decides whether the system's now-playing entry is YouTube Music.
private enum YouTubeMusicClient {
    /// Browsers that can be asked which pages they have open.
    static let scriptableBrowsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "com.brave.Browser", "com.microsoft.edgemac", "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi", "company.thebrowser.Browser", "org.chromium.Chromium",
        "com.apple.Safari"
    ]

    /// Installed as its own app: the web app every Chromium browser offers,
    /// a Safari web app, or one of the desktop wrappers.
    static func isDedicatedApp(_ bundleIdentifier: String) -> Bool {
        if bundleIdentifier.hasSuffix(".app.cinhimbnkkaeohfgghhklpknlkffjgod") { return true }
        #if DEBUG
        if bundleIdentifier == debugBundleIdentifier { return true }
        #endif
        let name = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first?.localizedName?.lowercased() ?? ""
        return name.contains("youtube music") || name.contains("youtube müzik")
            || name == "yt music"
    }

    #if DEBUG
    /// Lets a test treat any app's playback as YouTube Music.
    nonisolated(unsafe) static var debugBundleIdentifier: String?
    #endif
}

@MainActor
final class MediaManager: ObservableObject {
    @Published private(set) var source: MediaSource = .none
    @Published private(set) var trackName = ""
    @Published private(set) var artistName = ""
    @Published private(set) var albumName = ""
    @Published private(set) var artwork: NSImage?
    @Published private(set) var isPlaying = false
    @Published private(set) var playbackPosition: TimeInterval = 0 {
        didSet { positionUpdatedAt = Date() }
    }
    /// When `playbackPosition` was last read, to estimate it in between.
    private(set) var positionUpdatedAt = Date()
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var volume: Double = 0
    @Published private(set) var isShuffleEnabled = false
    @Published private(set) var repeatMode: PlaybackRepeatMode = .off
    @Published private(set) var trackChangeRevision = 0
    @Published private(set) var lastError: String?

    private let bridge = AppleScriptBridge()
    private let systemNowPlaying = SystemNowPlayingReader()
    /// The browser or web app YouTube Music is playing in.
    private var youTubeMusicOwner: String?
    /// Which track the tab check was last made for, and what it found.
    private var youTubeMusicCheck: (key: String, isMatch: Bool, at: Date)?
    private var browserRetryAfter: [String: Date] = [:]
    private var monitorTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var volumeWriteTask: Task<Void, Never>?
    private var isRefreshing = false
    private var needsAnotherRefresh = false
    private var playerObservers: [NSObjectProtocol] = []
    private var artworkKey: String?
    private var trackIdentifier = ""
    private var volumeRevision = 0
    private var permissionRetryAfter: [MediaSource: Date] = [:]

    var hasActiveTrack: Bool {
        source != .none && !trackName.isEmpty
    }

    /// The position between the once-a-second reads, for lyrics.
    func estimatedPosition(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return playbackPosition }
        let estimate = playbackPosition + date.timeIntervalSince(positionUpdatedAt)
        return duration > 0 ? min(estimate, duration) : estimate
    }

    func startMonitoring() {
        guard monitorTask == nil else { return }
        observePlayerNotifications()

        monitorTask = Task { [weak self] in
            var ticksSinceSnapshot = 0
            while !Task.isCancelled {
                guard let self else { return }
                // A paused or absent player announces when it starts again
                // (see observePlayerNotifications), so it only needs an
                // occasional look; the volume is cheap and read every tick.
                ticksSinceSnapshot += 1
                if self.isPlaying || ticksSinceSnapshot >= 5 {
                    ticksSinceSnapshot = 0
                    await self.refresh()
                } else {
                    await self.refreshVolume()
                }

                do {
                    try await Task<Never, Never>.sleep(
                        nanoseconds: 1_000_000_000
                    )
                } catch {
                    return
                }
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        artworkTask?.cancel()
        volumeWriteTask?.cancel()
        monitorTask = nil
        artworkTask = nil
        volumeWriteTask = nil
        systemNowPlaying.stop()
        let center = DistributedNotificationCenter.default()
        playerObservers.forEach(center.removeObserver)
        playerObservers.removeAll()
    }

    /// Music and Spotify announce every play/pause and track change. Reacting
    /// to those makes the notch respond at once instead of on the next poll.
    private func observePlayerNotifications() {
        guard playerObservers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        let players: [(String, MediaSource)] = [
            ("com.spotify.client.PlaybackStateChanged", .spotify),
            ("com.apple.Music.playerInfo", .appleMusic)
        ]
        playerObservers = players.map { name, player in
            center.addObserver(
                forName: Notification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let state = (notification.userInfo?["Player State"] as? String)?
                    .lowercased()
                Task { @MainActor in
                    self?.handlePlayerNotification(state: state, from: player)
                }
            }
        }
    }

    private func handlePlayerNotification(state: String?, from player: MediaSource) {
        // Trust the announced state right away; the snapshot that follows
        // fills in the track. A pause from a player islo. isn't showing
        // doesn't change anything.
        if state == "playing" {
            isPlaying = true
        } else if state != nil, player == source {
            isPlaying = false
        }
        Task { await refresh() }
    }

    func refresh() async {
        guard !isRefreshing else {
            needsAnotherRefresh = true
            return
        }
        isRefreshing = true
        defer {
            isRefreshing = false
            if needsAnotherRefresh {
                needsAnotherRefresh = false
                Task { await refresh() }
            }
        }

        await refreshVolume()

        let runningPlayers = runningMediaSources()
        if runningPlayers.isEmpty { permissionRetryAfter.removeAll() }

        // A denied TCC request returns -1743 immediately. Backing off keeps the
        // monitor from sending the same rejected Apple Event every second while
        // still allowing access granted in System Settings to recover at runtime.
        let now = Date()
        let eligiblePlayers = runningPlayers.filter { player in
            guard let retryDate = permissionRetryAfter[player] else {
                return true
            }
            return retryDate <= now
        }

        let orderedPlayers: [MediaSource]
        if eligiblePlayers.contains(source) {
            orderedPlayers = [source] + eligiblePlayers.filter { $0 != source }
        } else {
            orderedPlayers = eligiblePlayers
        }

        var snapshots: [MediaSnapshot] = []
        var selectedSnapshot: MediaSnapshot?
        var latestError: Error?

        for player in orderedPlayers {
            do {
                let snapshot = try await bridge.snapshot(for: player)
                permissionRetryAfter[player] = nil
                snapshots.append(snapshot)

                if snapshot.isPlaying {
                    selectedSnapshot = snapshot
                    break
                }
            } catch {
                latestError = error
                if isAutomationPermissionDenied(error) {
                    permissionRetryAfter[player] = now.addingTimeInterval(30)
                }
            }
        }

        // Nothing playing in Music or Spotify: see whether YouTube Music is.
        if selectedSnapshot == nil, let snapshot = await youTubeMusicSnapshot() {
            if snapshot.isPlaying {
                selectedSnapshot = snapshot
            } else if source == .youtubeMusic {
                snapshots.insert(snapshot, at: 0)
            } else {
                snapshots.append(snapshot)
            }
        }

        // Otherwise stay with a paused player, preferring one that has a track.
        let fallbackSnapshot = snapshots.first { !$0.trackName.isEmpty } ?? snapshots.first

        if let snapshot = selectedSnapshot ?? fallbackSnapshot {
            lastError = nil
            apply(snapshot)
        } else {
            resetMediaState()
            lastError = latestError.map(readableMessage(for:))
        }
    }

    /// The system's now-playing entry, if it turns out to be YouTube Music.
    private func youTubeMusicSnapshot() async -> MediaSnapshot? {
        guard let info = await systemNowPlaying.info(), !info.title.isEmpty else {
            youTubeMusicOwner = nil
            return nil
        }
        let owner = info.owner
        let identifier = [info.title, info.artist, info.album].joined(separator: "|")
        guard await isYouTubeMusic(owner: owner, trackKey: owner + "|" + identifier) else {
            return nil
        }
        youTubeMusicOwner = owner

        var position = info.elapsed
        if info.playing, info.timestamp > 0 {
            let rate = info.rate > 0 ? info.rate : 1
            position += max(0, Date().timeIntervalSince1970 - info.timestamp) * rate
        }

        return MediaSnapshot(
            source: .youtubeMusic,
            trackName: info.title,
            artistName: info.artist,
            albumName: info.album,
            isPlaying: info.playing,
            position: max(0, position),
            duration: max(0, info.duration),
            artworkURL: nil,
            trackIdentifier: identifier,
            isShuffleEnabled: false,
            repeatMode: .off
        )
    }

    private func isYouTubeMusic(owner: String, trackKey: String) async -> Bool {
        guard !owner.isEmpty else { return false }
        if YouTubeMusicClient.isDedicatedApp(owner) { return true }
        guard YouTubeMusicClient.scriptableBrowsers.contains(owner) else { return false }

        // The browser is asked once per track, and now and then while the
        // same one keeps playing, not on every poll.
        if let check = youTubeMusicCheck, check.key == trackKey,
           Date().timeIntervalSince(check.at) < (check.isMatch ? 60 : 15) {
            return check.isMatch
        }
        if let retryDate = browserRetryAfter[owner], retryDate > Date() { return false }

        do {
            let isMatch = try await bridge.hasYouTubeMusicTab(browser: owner)
            browserRetryAfter[owner] = nil
            youTubeMusicCheck = (trackKey, isMatch, Date())
            return isMatch
        } catch {
            browserRetryAfter[owner] = Date().addingTimeInterval(30)
            return false
        }
    }

    /// The output volume, straight from CoreAudio; AppleScript only for
    /// outputs CoreAudio can't read.
    private func refreshVolume() async {
        guard volumeWriteTask == nil else { return }
        if let current = SystemAudioOutput.volume() {
            if abs(current - volume) > 0.004 { volume = current }
            return
        }
        do {
            let current = try await bridge.systemVolume()
            if current != volume { volume = current }
        } catch {
            lastError = readableMessage(for: error)
        }
    }

    func togglePlayPause() {
        perform(.togglePlayPause)
    }

    func nextTrack() {
        perform(.next)
    }

    func previousTrack() {
        perform(.previous)
    }

    func seek(to time: TimeInterval) {
        playbackPosition = min(max(time, 0), max(duration, 0))
        perform(.seek(playbackPosition))
    }

    func toggleShuffle() {
        guard source.supportsShuffleAndRepeat else { return }
        perform(.setShuffle(!isShuffleEnabled))
    }

    func cycleRepeatMode() {
        guard source.supportsShuffleAndRepeat else { return }
        let nextMode: PlaybackRepeatMode

        switch (source, repeatMode) {
        case (.appleMusic, .off):
            nextMode = .all
        case (.appleMusic, .all):
            nextMode = .one
        case (.appleMusic, .one):
            nextMode = .off
        case (_, .off):
            nextMode = .all
        case (_, .all), (_, .one):
            nextMode = .off
        }

        perform(.setRepeat(nextMode))
    }

    func openSourceApplication() {
        guard source != .none,
              let bundleIdentifier = source.bundleIdentifier ?? youTubeMusicOwner else {
            return
        }

        if source == .spotify,
           let trackURL = URL(string: trackIdentifier),
           trackURL.scheme?.lowercased() == "spotify" {
            NSWorkspace.shared.open(trackURL)
            activateRunningApplication(bundleIdentifier: bundleIdentifier)
            return
        }

        if activateRunningApplication(bundleIdentifier: bundleIdentifier) {
            return
        }

        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration
        )
    }

    @discardableResult
    private func activateRunningApplication(
        bundleIdentifier: String
    ) -> Bool {
        guard let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).first else {
            return false
        }

        application.activate(options: [
            .activateAllWindows,
            .activateIgnoringOtherApps
        ])
        return true
    }

    /// Changes the system output volume, not merely the Music/Spotify app volume.
    /// Rapid slider updates are coalesced to avoid flooding AppleScript.
    func setVolume(_ normalizedValue: Double) {
        let value = normalizedValue.isFinite ? normalizedValue : 0
        let clampedValue = min(max(value, 0), 1)
        volume = clampedValue

        volumeRevision += 1
        let revision = volumeRevision
        volumeWriteTask?.cancel()

        volumeWriteTask = Task { [weak self, bridge] in
            do {
                try await Task<Never, Never>.sleep(nanoseconds: 60_000_000)
                guard !Task.isCancelled else { return }
                let actualVolume = try await bridge.setSystemVolume(clampedValue)

                guard let self, self.volumeRevision == revision else { return }
                self.volume = actualVolume
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                self.lastError = self.readableMessage(for: error)
            }

            guard let self, self.volumeRevision == revision else { return }
            self.volumeWriteTask = nil
        }
    }

    private func perform(_ command: PlayerCommand) {
        let target = source != .none ? source : runningMediaSources().first
        guard let target, target != .none else { return }

        Task { [weak self, bridge] in
            do {
                try await bridge.perform(command, on: target)
                self?.permissionRetryAfter[target] = nil
                try await Task<Never, Never>.sleep(nanoseconds: 120_000_000)
                await self?.refresh()
            } catch {
                if self?.isAutomationPermissionDenied(error) == true {
                    self?.permissionRetryAfter[target] = Date()
                        .addingTimeInterval(30)
                }
                self?.lastError = self?.readableMessage(for: error)
            }
        }
    }

    private func apply(_ snapshot: MediaSnapshot) {
        let nextArtworkKey = [
            snapshot.source.rawValue,
            snapshot.trackIdentifier
        ].joined(separator: "|")

        // Only what changed is published: an unchanged poll must not make
        // every view that watches the player draw again.
        if source != snapshot.source { source = snapshot.source }
        if trackName != snapshot.trackName { trackName = snapshot.trackName }
        if artistName != snapshot.artistName { artistName = snapshot.artistName }
        if albumName != snapshot.albumName { albumName = snapshot.albumName }
        trackIdentifier = snapshot.trackIdentifier
        if isPlaying != snapshot.isPlaying { isPlaying = snapshot.isPlaying }
        let position = min(snapshot.position, max(snapshot.duration, 0))
        if playbackPosition != position { playbackPosition = position }
        if duration != snapshot.duration { duration = snapshot.duration }
        if isShuffleEnabled != snapshot.isShuffleEnabled { isShuffleEnabled = snapshot.isShuffleEnabled }
        if repeatMode != snapshot.repeatMode { repeatMode = snapshot.repeatMode }

        if !snapshot.trackName.isEmpty, artworkKey != nextArtworkKey {
            trackChangeRevision &+= 1
        }

        guard artworkKey != nextArtworkKey else { return }
        artworkKey = nextArtworkKey
        artwork = nil
        loadArtwork(for: snapshot, key: nextArtworkKey)
    }

    private func loadArtwork(for snapshot: MediaSnapshot, key: String) {
        artworkTask?.cancel()

        artworkTask = Task { [weak self, bridge] in
            let data: Data?

            do {
                switch snapshot.source {
                case .appleMusic:
                    data = try await bridge.appleMusicArtworkData()
                case .spotify:
                    guard let url = snapshot.artworkURL else { return }
                    let (downloadedData, response) = try await URLSession.shared
                        .data(from: url)

                    if let httpResponse = response as? HTTPURLResponse,
                       !(200..<300).contains(httpResponse.statusCode) {
                        return
                    }
                    data = downloadedData.count <= 10_000_000
                        ? downloadedData
                        : nil
                case .youtubeMusic:
                    data = try await CoverLookup.cover(
                        title: snapshot.trackName,
                        artist: snapshot.artistName
                    )
                case .none:
                    data = nil
                }
            } catch {
                return
            }

            guard
                !Task.isCancelled,
                let self,
                self.artworkKey == key,
                let data,
                let image = NSImage(data: data)
            else {
                return
            }

            self.artwork = image
        }
    }

    private func runningMediaSources() -> [MediaSource] {
        MediaSource.players.filter { source in
            guard let bundleIdentifier = source.bundleIdentifier else {
                return false
            }
            return !NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            ).isEmpty
        }
    }

    private func resetMediaState() {
        source = .none
        trackName = ""
        artistName = ""
        albumName = ""
        artwork = nil
        isPlaying = false
        playbackPosition = 0
        duration = 0
        isShuffleEnabled = false
        repeatMode = .off
        artworkKey = nil
        trackIdentifier = ""
        youTubeMusicOwner = nil
    }

    #if DEBUG
    /// Treats this app's playback as YouTube Music, for tests.
    func debugSetYouTubeMusicClient(_ bundleIdentifier: String?) {
        YouTubeMusicClient.debugBundleIdentifier = bundleIdentifier
        Task { await refresh() }
    }
    #endif

    private func readableMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let message = localizedError.errorDescription {
            return message
        }
        return error.localizedDescription
    }

    private func isAutomationPermissionDenied(_ error: Error) -> Bool {
        guard case let AppleScriptBridgeError.executionFailed(_, number) = error
        else {
            return false
        }
        return number == -1743 || number == -1742
    }
}
