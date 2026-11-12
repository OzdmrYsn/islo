import AppKit
import Combine
import Foundation

// MARK: - Model

/// A coding agent islo. can hear from.
enum AgentSource: String {
    case claude
    case codex

    var name: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }
}

enum AgentState: Equatable {
    /// Open, nothing asked of it yet.
    case idle
    case working
    /// Stopped for the user: a permission, a question.
    case waiting
    case finished
}

/// A tool call the agent may not run until someone says so.
struct AgentPermission: Identifiable, Equatable {
    let id: String
    let sessionID: String
    let source: AgentSource
    let project: String
    /// The tool's name, e.g. Bash or Edit.
    let tool: String
    /// What it would do: the command, the file.
    let detail: String
    let date: Date
    /// Questions the agent wants answered, each with its choices; empty
    /// for an ordinary permission.
    var questions: [AgentQuestion] = []
}

/// One question the agent asks, answered by picking a choice.
struct AgentQuestion: Equatable {
    let text: String
    let options: [String]
}

struct AgentSession: Identifiable, Equatable {
    let id: String
    let source: AgentSource
    var cwd: String
    var state: AgentState
    /// When it entered `state`.
    var since: Date
    /// The end of its last answer, or what it is waiting for.
    var note: String
    /// The app the session lives in (a terminal, an editor), to bring forward.
    var hostBundleID: String?

    var project: String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? source.name : name
    }
}

enum AgentEvent {
    case finished(AgentSession)
    case waiting(AgentSession)
    case permission(AgentPermission)
}

// MARK: - Hub

/// Keeps track of agent sessions from what their hooks report over a local
/// socket, and answers permission requests the user settles in the notch.
/// Nothing leaves this Mac: the socket is a file only this user can open.
@MainActor
final class AgentHub: ObservableObject {
    static let shared = AgentHub()

    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var pending: [AgentPermission] = []

    /// Told about everything worth a HUD.
    var onEvent: ((AgentEvent) -> Void)?
    /// Off: requests go straight back to the terminal's own prompt.
    var answersPermissions = true

    private var server: AgentSocketServer?
    private var responders: [String: AgentResponder] = [:]
    /// The question tool's own input, handed back with the answers added.
    private var questionInputs: [String: [String: Any]] = [:]

    /// Tools whose prompt only the terminal can show.
    private static let terminalOnlyTools: Set<String> = ["ExitPlanMode"]

    var workingCount: Int { sessions.filter { $0.state == .working }.count }
    var waitingCount: Int { sessions.filter { $0.state == .waiting }.count }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            guard server == nil else { return }
            let server = AgentSocketServer(path: AgentSocket.path)
            server.onMessage = { [weak self] message, responder in
                Task { @MainActor in self?.handle(message, responder: responder) }
            }
            server.onDisconnect = { [weak self] responder in
                Task { @MainActor in self?.disconnected(responder) }
            }
            if server.start() { self.server = server }
        } else {
            server?.stop()
            server = nil
            responders.values.forEach { $0.finish(nil) }
            responders.removeAll()
            sessions.removeAll()
            pending.removeAll()
        }
    }

    // MARK: Answers

    /// Answers the agent's questions, one picked choice per question.
    func answer(_ permission: AgentPermission, with choices: [String]) {
        guard var input = questionInputs[permission.id], choices.count == permission.questions.count else { return }
        var answers: [String: String] = [:]
        for (question, choice) in zip(permission.questions, choices) { answers[question.text] = choice }
        input["answers"] = answers
        guard let data = try? JSONSerialization.data(withJSONObject: input), let json = String(data: data, encoding: .utf8) else { return }
        finish(permission, reply: "answer " + json)
    }

    func resolve(_ permission: AgentPermission, allow: Bool) {
        finish(permission, reply: allow ? "allow" : "deny")
    }

    private func finish(_ permission: AgentPermission, reply: String) {
        questionInputs.removeValue(forKey: permission.id)
        responders.removeValue(forKey: permission.id)?.finish(reply)
        pending.removeAll { $0.id == permission.id }
        update(permission.sessionID) { session in
            session.state = .working
            session.since = Date()
            session.note = ""
        }
    }

    /// Brings the session's terminal or editor to the front.
    func focus(sessionID: String) {
        guard let bundleID = sessions.first(where: { $0.id == sessionID })?.hostBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func forget(_ session: AgentSession) {
        clearPending(for: session.id)
        sessions.removeAll { $0.id == session.id }
    }

    func clearFinished() {
        sessions.removeAll { $0.state == .finished || $0.state == .idle }
    }

    // MARK: Incoming

    private func handle(_ message: [String: Any], responder: AgentResponder) {
        guard let source = AgentSource(rawValue: message["source"] as? String ?? ""),
              let payload = message["payload"] as? [String: Any] else {
            responder.finish(nil)
            return
        }
        let environment = message["env"] as? [String: String] ?? [:]
        let host = Self.hostBundleID(environment)
        handleHook(payload, source: source, host: host, responder: responder)
    }

    /// Claude Code and Codex report in the same shape.
    private func handleHook(_ payload: [String: Any], source: AgentSource, host: String?, responder: AgentResponder) {
        guard let sessionID = payload["session_id"] as? String, !sessionID.isEmpty else {
            responder.finish(nil)
            return
        }
        let cwd = payload["cwd"] as? String ?? ""
        let event = payload["hook_event_name"] as? String ?? ""
        touch(sessionID, source: source, cwd: cwd, host: host)

        switch event {
        case "SessionStart":
            responder.finish(nil)
        case "SessionEnd":
            responder.finish(nil)
            clearPending(for: sessionID)
            sessions.removeAll { $0.id == sessionID }
        case "UserPromptSubmit":
            responder.finish(nil)
            clearPending(for: sessionID)
            update(sessionID) { $0.state = .working; $0.since = Date(); $0.note = "" }
        case "Stop":
            responder.finish(nil)
            clearPending(for: sessionID)
            let wasBusy = sessions.first { $0.id == sessionID }?.state != .finished
            update(sessionID) {
                $0.state = .finished
                $0.since = Date()
                $0.note = Self.oneLine(payload["last_assistant_message"] as? String ?? "")
            }
            if wasBusy, let session = sessions.first(where: { $0.id == sessionID }) { onEvent?(.finished(session)) }
        case "Notification":
            responder.finish(nil)
            let type = payload["notification_type"] as? String ?? ""
            // A permission the notch already shows needs no second alert, and
            // the idle reminder only repeats what "finished" said.
            guard type != "idle_prompt", !pending.contains(where: { $0.sessionID == sessionID }) else { return }
            guard ["permission_prompt", "elicitation_dialog", "agent_needs_input"].contains(type) else { return }
            markWaiting(sessionID, note: Self.oneLine(payload["message"] as? String ?? ""))
        case "PermissionRequest":
            let tool = payload["tool_name"] as? String ?? ""
            guard answersPermissions, !Self.terminalOnlyTools.contains(tool) else {
                responder.finish(nil)
                markWaiting(sessionID, note: tool)
                return
            }
            let input = payload["tool_input"] as? [String: Any] ?? [:]
            var questions: [AgentQuestion] = []
            if tool == "AskUserQuestion" {
                questions = Self.questions(in: input)
                // Several answers to one question, or nothing to pick from:
                // that needs the terminal's own prompt.
                guard !questions.isEmpty else {
                    responder.finish(nil)
                    markWaiting(sessionID, note: "")
                    return
                }
            }
            var permission = AgentPermission(
                id: UUID().uuidString,
                sessionID: sessionID,
                source: source,
                project: sessions.first { $0.id == sessionID }?.project ?? "",
                tool: tool,
                detail: Self.describe(tool: tool, input: payload["tool_input"] as? [String: Any] ?? [:]),
                date: Date()
            )
            permission.questions = questions
            if !questions.isEmpty { questionInputs[permission.id] = input }
            responder.permissionID = permission.id
            responders[permission.id] = responder
            pending.append(permission)
            update(sessionID) { $0.state = .waiting; $0.since = Date(); $0.note = tool }
            onEvent?(.permission(permission))
        default:
            responder.finish(nil)
        }
    }

    /// The hook went away before the notch answered: the request was settled
    /// in the terminal, or it timed out.
    private func disconnected(_ responder: AgentResponder) {
        guard let id = responder.permissionID, responders.removeValue(forKey: id) != nil else { return }
        guard let permission = pending.first(where: { $0.id == id }) else { return }
        questionInputs.removeValue(forKey: id)
        pending.removeAll { $0.id == id }
        update(permission.sessionID) { session in
            if session.state == .waiting { session.state = .working; session.since = Date(); session.note = "" }
        }
    }

    private func markWaiting(_ sessionID: String, note: String) {
        let already = sessions.first { $0.id == sessionID }?.state == .waiting
        update(sessionID) { $0.state = .waiting; $0.since = Date(); $0.note = note }
        if !already, let session = sessions.first(where: { $0.id == sessionID }) { onEvent?(.waiting(session)) }
    }

    private func clearPending(for sessionID: String) {
        for permission in pending where permission.sessionID == sessionID {
            questionInputs.removeValue(forKey: permission.id)
            responders.removeValue(forKey: permission.id)?.finish(nil)
        }
        pending.removeAll { $0.sessionID == sessionID }
    }

    private func touch(_ id: String, source: AgentSource, cwd: String, host: String?) {
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            if !cwd.isEmpty, sessions[index].cwd != cwd { sessions[index].cwd = cwd }
            if let host, sessions[index].hostBundleID != host { sessions[index].hostBundleID = host }
        } else {
            sessions.insert(
                AgentSession(id: id, source: source, cwd: cwd, state: .idle, since: Date(), note: "", hostBundleID: host),
                at: 0
            )
            if sessions.count > 12 { sessions = Array(sessions.prefix(12)) }
        }
    }

    private func update(_ id: String, _ change: (inout AgentSession) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        var session = sessions[index]
        change(&session)
        if session != sessions[index] { sessions[index] = session }
    }

    // MARK: Reading a request

    /// The questions of an AskUserQuestion call, when each is a single pick.
    private static func questions(in input: [String: Any]) -> [AgentQuestion] {
        guard let raw = input["questions"] as? [[String: Any]], !raw.isEmpty else { return [] }
        var result: [AgentQuestion] = []
        for item in raw {
            guard item["multiSelect"] as? Bool != true,
                  let text = item["question"] as? String,
                  let options = (item["options"] as? [[String: Any]])?.compactMap({ $0["label"] as? String }),
                  !options.isEmpty else { return [] }
            result.append(AgentQuestion(text: text, options: options))
        }
        return result
    }

    /// The one thing worth reading before saying yes.
    private static func describe(tool: String, input: [String: Any]) -> String {
        for key in ["command", "file_path", "path", "url", "pattern", "query", "prompt", "description"] {
            if let value = input[key] as? String, !value.isEmpty { return String(value.prefix(600)) }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8), text != "{}" else { return "" }
        return String(text.prefix(600))
    }

    private static func oneLine(_ text: String) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return String(flat.prefix(160))
    }

    private static func hostBundleID(_ environment: [String: String]) -> String? {
        if let bundle = environment["bundle"], !bundle.isEmpty { return bundle }
        switch environment["term"] ?? "" {
        case "Apple_Terminal": return "com.apple.Terminal"
        case "iTerm.app": return "com.googlecode.iterm2"
        case "vscode": return "com.microsoft.VSCode"
        case "ghostty": return "com.mitchellh.ghostty"
        case "WarpTerminal": return "dev.warp.Warp-Stable"
        case "WezTerm": return "com.github.wez.wezterm"
        default: return nil
        }
    }

    #if DEBUG
    /// Debug builds: a pretend session, to look at the notch without an agent.
    func debugSimulate(_ what: String) {
        let id = "debug-session"
        touch(id, source: .claude, cwd: "/Users/demo/Projeler/islo", host: "com.apple.Terminal")
        switch what {
        case "working":
            update(id) { $0.state = .working; $0.since = Date(); $0.note = "" }
        case "finished":
            update(id) { $0.state = .finished; $0.since = Date(); $0.note = "Testler geçti; değişiklikleri özetledim." }
            if let session = sessions.first(where: { $0.id == id }) { onEvent?(.finished(session)) }
        case "waiting":
            markWaiting(id, note: "Claude senden bir cevap bekliyor")
        case "permission":
            let permission = AgentPermission(
                id: UUID().uuidString, sessionID: id, source: .claude, project: "islo", tool: "Bash",
                detail: "xcodebuild -project islo.xcodeproj -scheme islo -configuration Release build", date: Date()
            )
            pending.append(permission)
            update(id) { $0.state = .waiting; $0.since = Date(); $0.note = "Bash" }
            onEvent?(.permission(permission))
        case "question":
            var permission = AgentPermission(
                id: UUID().uuidString, sessionID: id, source: .claude, project: "islo", tool: "AskUserQuestion", detail: "", date: Date()
            )
            permission.questions = [
                AgentQuestion(text: "Klasörün adı ne olsun?", options: ["islo", "İslo", "Aynı kalsın"]),
                AgentQuestion(text: "Ne zaman yapayım?", options: ["Yayından sonra", "Hemen şimdi"])
            ]
            pending.append(permission)
            update(id) { $0.state = .waiting; $0.since = Date(); $0.note = "" }
            onEvent?(.permission(permission))
        case "answer":
            if let permission = pending.first(where: { !$0.questions.isEmpty }) {
                answer(permission, with: permission.questions.map { $0.options[0] })
            }
        case "allow", "deny":
            if let permission = pending.first { resolve(permission, allow: what == "allow") }
        default:
            if let session = sessions.first(where: { $0.id == id }) { forget(session) }
        }
    }
    #endif
}

// MARK: - Socket

enum AgentSocket {
    /// A socket path has to fit in 104 bytes; a long home folder falls back
    /// to a per-user name in /tmp.
    static var path: String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let preferred = support.appendingPathComponent("islo/agent.sock").path
        return preferred.utf8.count < 100 ? preferred : "/tmp/islo-agent-\(getuid()).sock"
    }

    static func address(_ path: String) -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8.prefix(103))
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (index, byte) in bytes.enumerated() { buffer[index] = byte }
        }
        return address
    }
}

/// One hook process on the other end. Answering closes the connection.
final class AgentResponder: @unchecked Sendable {
    fileprivate let fd: Int32
    private let queue: DispatchQueue
    private var isDone = false
    fileprivate var source: DispatchSourceRead?
    /// Set on the main actor once the request is on screen.
    var permissionID: String?

    fileprivate init(fd: Int32, queue: DispatchQueue) {
        self.fd = fd
        self.queue = queue
    }

    /// Sends the decision, if any, and hangs up.
    func finish(_ reply: String?) {
        queue.async { [self] in
            guard !isDone else { return }
            isDone = true
            if let reply {
                let line = Array((reply + "\n").utf8)
                _ = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            }
            source?.cancel()
            source = nil
        }
    }

    fileprivate var done: Bool { isDone }
    fileprivate func markDone() { isDone = true }
}

/// Accepts hook connections and reads one JSON line from each.
final class AgentSocketServer: @unchecked Sendable {
    var onMessage: (([String: Any], AgentResponder) -> Void)?
    var onDisconnect: ((AgentResponder) -> Void)?

    private let path: String
    private let queue = DispatchQueue(label: "islo.agent.socket")
    private var listener: Int32 = -1
    private var acceptSource: DispatchSourceRead?

    init(path: String) {
        self.path = path
    }

    func start() -> Bool {
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        var address = AgentSocket.address(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        // Only this user may connect.
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 16) == 0 else {
            close(fd)
            return false
        }
        listener = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.accept() }
        source.setCancelHandler { close(fd) }
        source.resume()
        acceptSource = source
        return true
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        unlink(path)
    }

    private func accept() {
        let client = Darwin.accept(listener, nil, nil)
        guard client >= 0 else { return }
        var on: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let responder = AgentResponder(fd: client, queue: queue)
        var buffer = Data()
        var delivered = false
        let source = DispatchSource.makeReadSource(fileDescriptor: client, queue: queue)
        source.setEventHandler { [weak self] in
            var chunk = [UInt8](repeating: 0, count: 16_384)
            let count = read(client, &chunk, chunk.count)
            guard count > 0 else {
                // The hook hung up.
                if !responder.done {
                    responder.markDone()
                    source.cancel()
                    if delivered { self?.onDisconnect?(responder) }
                }
                return
            }
            guard !delivered else { return }
            buffer.append(contentsOf: chunk[0..<count])
            // A megabyte without a newline is not a hook talking.
            guard buffer.count < 1_048_576 else {
                responder.markDone()
                source.cancel()
                return
            }
            guard let newline = buffer.firstIndex(of: 0x0A) else { return }
            delivered = true
            guard let message = try? JSONSerialization.jsonObject(with: buffer[..<newline]) as? [String: Any] else {
                responder.markDone()
                source.cancel()
                return
            }
            self?.onMessage?(message, responder)
        }
        source.setCancelHandler { close(client) }
        responder.source = source
        source.resume()
    }
}

// MARK: - The hook itself

/// What `islo --agent-hook <agent>` does when an agent runs it: pass the
/// event to the running app and, for a permission request, wait for the
/// notch's answer. Silent and harmless when islo. isn't running.
enum AgentHookCLI {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--agent-hook"), flag + 1 < arguments.count else { return }
        run(source: arguments[flag + 1])
        exit(0)
    }

    private static func run(source: String) {
        let raw = FileHandle.standardInput.readDataToEndOfFile()
        guard let payload = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else { return }

        let environment = ProcessInfo.processInfo.environment
        let message: [String: Any] = [
            "source": source,
            "payload": payload,
            "env": ["bundle": environment["__CFBundleIdentifier"] ?? "", "term": environment["TERM_PROGRAM"] ?? ""]
        ]
        guard var line = try? JSONSerialization.data(withJSONObject: message) else { return }
        line.append(0x0A)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var address = AgentSocket.address(AgentSocket.path)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { return }
        let sent = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard sent == line.count else { return }

        guard payload["hook_event_name"] as? String == "PermissionRequest" else { return }

        // Wait for the notch, a little less long than the agent waits for
        // the hook; no answer leaves the terminal's own prompt in charge.
        // Codex holds its prompt back meanwhile, so it gets a shorter wait.
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        guard poll(&descriptor, 1, source == "codex" ? 85_000 : 285_000) > 0 else { return }
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while !received.contains(0x0A), received.count < 1_048_576 {
            let count = read(fd, &buffer, buffer.count)
            guard count > 0 else { break }
            received.append(contentsOf: buffer[0..<count])
        }
        let reply = String(decoding: received, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let decision: [String: Any]
        if reply == "allow" {
            decision = ["behavior": "allow"]
        } else if reply == "deny" {
            decision = ["behavior": "deny", "message": "Denied from the islo. notch", "interrupt": false]
        } else if reply.hasPrefix("answer "),
                  let input = try? JSONSerialization.jsonObject(with: Data(reply.dropFirst("answer ".count).utf8)) as? [String: Any] {
            // A question answered in the notch: the tool's input comes back
            // with the answers filled in.
            decision = ["behavior": "allow", "updatedInput": input]
        } else {
            return
        }
        let output: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        if let data = try? JSONSerialization.data(withJSONObject: output) {
            FileHandle.standardOutput.write(data)
        }
    }
}

// MARK: - Connecting the agents

/// Adds islo.'s hook to an agent's own settings, next to whatever is there,
/// and takes it out again. Only ever on the user's click.
enum AgentIntegration {
    enum Status: Equatable {
        case connected
        /// Hooked to an islo. somewhere else on disk (an older copy).
        case elsewhere
        case notConnected
        /// The agent has never been set up on this Mac.
        case notInstalled
    }

    private static var executable: String { Bundle.main.executablePath ?? "/Applications/islo.app/Contents/MacOS/islo" }
    private static let marker = "--agent-hook"

    /// Claude Code keeps hooks in its settings file; Codex in a file of
    /// their own, in the same shape.
    #if DEBUG
    /// Debug builds: try connecting against a copy of the settings.
    nonisolated(unsafe) static var homeOverride: URL?
    #endif

    private static func file(_ source: AgentSource) -> URL {
        var home = FileManager.default.homeDirectoryForCurrentUser
        #if DEBUG
        if let homeOverride { home = homeOverride }
        #endif
        switch source {
        case .claude: return home.appendingPathComponent(".claude/settings.json")
        case .codex: return home.appendingPathComponent(".codex/hooks.json")
        }
    }

    /// Runs only while the app is where it was; a moved or deleted islo.
    /// must never make a hook fail.
    private static func command(_ source: AgentSource) -> String {
        "[ -x \"\(executable)\" ] && \"\(executable)\" \(marker) \(source.rawValue) || true"
    }

    private static func events(_ source: AgentSource) -> [(name: String, matcher: String?, timeout: Int?)] {
        switch source {
        case .claude:
            [("SessionStart", nil, nil), ("SessionEnd", nil, nil), ("UserPromptSubmit", nil, nil), ("Stop", nil, nil),
             ("Notification", "permission_prompt|elicitation_dialog|agent_needs_input", nil),
             ("PermissionRequest", "*", 300)]
        case .codex:
            [("SessionStart", nil, nil), ("SessionEnd", nil, nil), ("UserPromptSubmit", nil, nil), ("Stop", nil, nil),
             ("PermissionRequest", ".*", 90)]
        }
    }

    static func status(_ source: AgentSource) -> Status {
        let url = file(source)
        guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) else { return .notInstalled }
        guard let text = try? String(contentsOf: url, encoding: .utf8), text.contains("\(marker) \(source.rawValue)") else {
            return .notConnected
        }
        return text.contains(executable) ? .connected : .elsewhere
    }

    static func connect(_ source: AgentSource) throws {
        var root = try read(source)
        var hooks = strippingIslo(root["hooks"] as? [String: Any] ?? [:], source: source)
        for event in events(source) {
            var handler: [String: Any] = ["type": "command", "command": command(source)]
            if let timeout = event.timeout { handler["timeout"] = timeout }
            var group: [String: Any] = ["hooks": [handler]]
            if let matcher = event.matcher { group["matcher"] = matcher }
            hooks[event.name] = (hooks[event.name] as? [Any] ?? []) + [group]
        }
        root["hooks"] = hooks
        try write(root, source: source)
    }

    static func disconnect(_ source: AgentSource) throws {
        var root = try read(source)
        let hooks = strippingIslo(root["hooks"] as? [String: Any] ?? [:], source: source)
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        try write(root, source: source)
    }

    private static func read(_ source: AgentSource) throws -> [String: Any] {
        let url = file(source)
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return root
    }

    private static func write(_ root: [String: Any], source: AgentSource) throws {
        let url = file(source), fileManager = FileManager.default
        // The first change keeps the file as it was beside it.
        let backup = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".islo-yedek")
        if fileManager.fileExists(atPath: url.path), !fileManager.fileExists(atPath: backup.path) {
            try? fileManager.copyItem(at: url, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    /// Every hook group that isn't islo.'s, untouched.
    private static func strippingIslo(_ hooks: [String: Any], source: AgentSource) -> [String: Any] {
        var result: [String: Any] = [:]
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else {
                result[event] = value
                continue
            }
            let kept = groups.compactMap { group -> [String: Any]? in
                guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
                let others = handlers.filter { !(($0["command"] as? String) ?? "").contains("\(marker) \(source.rawValue)") }
                guard !others.isEmpty else { return nil }
                var copy = group
                copy["hooks"] = others
                return copy
            }
            if !kept.isEmpty { result[event] = kept }
        }
        return result
    }
}
