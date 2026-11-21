import AppKit
import SwiftUI

struct Snapshot: Decodable {
    let phase: String
    let prompt: String
    let typed: String
    let elapsed_ms: UInt64
    let remaining_ms: UInt64
    let wpm: Int
    let raw_wpm: Int
    let accuracy: Double
    let best_wpm: Int
    let previous_wpm: Int?
    let previous_accuracy: Double?
    let previous_mistakes: Int?
    let prior_average_wpm: Int?
    let prior_average_errors: Double?
    let mistakes: Int
    let pace_wpm: [Int]
    let consistency: Int?
    let targeted: Bool?
    let pattern_fallback: Bool?
}

@MainActor final class Engine: ObservableObject {
    @Published var snapshot: Snapshot?
    @Published var error: String?
    @Published var pending = false
    @Published var patternEnabled = false
    private var child: Process?
    private var retiring: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var nextID: UInt64 = 1
    private var requests = Set<UInt64>()
    private var queuedKeys: [[String: Any]] = []
    private var timer: Timer?
    private var generation = UUID()

    func start(mode: String, limit: Int, strict: Bool, punctuation: Bool, numbers: Bool) {
        stop()
        error = nil
        snapshot = nil
        let token = generation
        if let retiring {
            // waitUntilExit blocks only a background task. Stale restarts cannot launch.
            Task.detached { [weak self] in
                retiring.waitUntilExit()
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    // Only the latest waiter may release its matching retirement.
                    guard self.generation == token else { return }
                    guard self.retiring === retiring else { return }
                    self.retiring = nil
                    self.launch(mode: mode, limit: limit, strict: strict,
                                punctuation: punctuation, numbers: numbers)
                }
            }
        } else {
            launch(mode: mode, limit: limit, strict: strict,
                   punctuation: punctuation, numbers: numbers)
        }
    }

    private func launch(mode: String, limit: Int, strict: Bool, punctuation: Bool, numbers: Bool) {
        guard let path = Bundle.main.path(forResource: "keyritual-core", ofType: nil) else {
            error = "Missing bundled keyritual-core. Rebuild the app."
            return
        }
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Keyritual", isDirectory: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["serve"]
        var environment = ProcessInfo.processInfo.environment
        environment["XDG_STATE_HOME"] = root.appendingPathComponent("state").path
        environment["XDG_CONFIG_HOME"] = root.appendingPathComponent("config").path
        process.environment = environment
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        let token = generation
        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.fail("Engine exited (status \(process.terminationStatus)). Restart to retry.")
            }
        }
        do {
            try process.run()
            child = process
            input = stdin.fileHandleForWriting
            output = stdout.fileHandleForReading
            stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let bytes = handle.availableData
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    if bytes.isEmpty { self.fail("Engine output closed. Restart to retry.") }
                    else { self.receive(bytes) }
                }
            }
            // Keep the diagnostic pipe drained so a failing child cannot block on stderr.
            stderr.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
            send(["type": "start", "mode": mode, "limit": limit, "strict": strict,
                  "punctuation": punctuation, "numbers": numbers])
            send(["type": "get_pattern_practice"])
        } catch {
            fail("Could not launch engine: \(error.localizedDescription)")
        }
    }

    func send(_ command: [String: Any]) {
        guard let input, child?.isRunning == true, error == nil else { return }
        let id = nextID
        nextID += 1
        var message = command
        message["id"] = id
        do {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(0x0a)
            try input.write(contentsOf: data)
            requests.insert(id)
            pending = true
        } catch { fail("Engine write failed: \(error.localizedDescription)") }
    }

    private func receive(_ bytes: Data) {
        buffer.append(bytes)
        if buffer.count > 1_048_576 { fail("Engine response too large"); return }
        while let newline = buffer.firstIndex(of: 0x0a) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  let id = object["id"] as? NSNumber, requests.remove(id.uint64Value) != nil,
                  let type = object["type"] as? String else {
                fail("Invalid or unexpected engine response"); return
            }
            pending = !requests.isEmpty
            if type == "error" {
                error = object["message"] as? String ?? "Engine error"
                stopTicking()
            } else if type == "pattern_practice" {
                guard let enabled = object["enabled"] as? Bool else { fail("Invalid pattern settings"); return }
                patternEnabled = enabled
            } else if type == "state" {
                guard let state = try? JSONDecoder().decode(Snapshot.self, from: line) else {
                    fail("Invalid engine state"); return
                }
                snapshot = state
                if state.phase == "running" { startTicking() } else { stopTicking(); queuedKeys.removeAll() }
                if !pending && (state.phase == "ready" || state.phase == "running") && !queuedKeys.isEmpty {
                    send(queuedKeys.removeFirst())
                }
            } else { fail("Unexpected engine message: \(type)"); return }
        }
    }

    private func startTicking() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.pending, self.snapshot?.phase == "running" else { return }
                self.send(["type": "tick"])
            }
        }
    }
    private func stopTicking() { timer?.invalidate(); timer = nil }
    private func fail(_ message: String) {
        error = message
        stop()
    }
    func key(_ command: [String: Any]) {
        guard error == nil, snapshot.map({ $0.phase == "ready" || $0.phase == "running" }) == true else { return }
        if pending { queuedKeys.append(command) } else { send(command) }
    }
    func stop() {
        stopTicking()
        generation = UUID()
        output?.readabilityHandler = nil
        try? input?.close()
        input = nil
        output = nil
        if let child {
            if child.isRunning { child.terminate() }
            retiring = child
        }
        child = nil
        buffer.removeAll()
        requests.removeAll()
        queuedKeys.removeAll()
        pending = false
    }
}

final class TypingView: NSView {
    var onKey: ((String?, Bool) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        needsDisplay = true
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        needsDisplay = true
        return accepted
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            onKey?(nil, true)
        } else if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            super.keyDown(with: event)
        } else if let text = event.characters, !text.isEmpty {
            for scalar in text.unicodeScalars where scalar.isASCII && (scalar.value >= 32 && scalar.value <= 126) {
                onKey?(String(scalar), false)
            }
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        (window?.firstResponder === self ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        NSBezierPath.defaultLineWidth = window?.firstResponder === self ? 3 : 1
        NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2)).stroke()
    }
}

struct Keyboard: NSViewRepresentable {
    let onKey: (String?, Bool) -> Void
    func makeNSView(context: Context) -> TypingView { TypingView() }
    func updateNSView(_ view: TypingView, context: Context) {
        view.onKey = onKey
    }
}

struct ContentView: View {
    @ObservedObject var engine: Engine
    @State private var mode = "time"
    @State private var limit = 30
    @State private var strict = false
    @State private var punctuation = false
    @State private var numbers = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Keyritual").font(.title.bold())
            HStack {
                Picker("Mode", selection: $mode) {
                    Text("Time").tag("time"); Text("Words").tag("words")
                }.onChange(of: mode) { _ in limit = mode == "time" ? 30 : 25 }
                Picker("Limit", selection: $limit) {
                    ForEach(mode == "time" ? [15, 30, 60] : [10, 25, 50], id: \.self) { value in
                        Text("\(value) \(mode == "time" ? "s" : "words")").tag(value)
                    }
                }
            }
            HStack { Toggle("Strict", isOn: $strict); Toggle("Punctuation", isOn: $punctuation); Toggle("Numbers", isOn: $numbers) }
            Button(engine.snapshot == nil ? "Start" : "Restart") {
                engine.start(mode: mode, limit: limit, strict: strict, punctuation: punctuation, numbers: numbers)
            }.keyboardShortcut("r", modifiers: .command)
            Text("Optional coaching stores local counts of expected letters and pairs, not typed text. Start a session before changing these settings. \(engine.patternEnabled ? "Collection enabled." : "Collection disabled.")")
                .font(.caption)
            HStack {
                Button("Targeted practice") {
                    engine.send(["type": "start", "mode": mode, "limit": limit, "strict": strict, "punctuation": punctuation, "numbers": numbers, "targeted": true])
                }.disabled(!engine.patternEnabled || engine.snapshot == nil || engine.pending)
                Button(engine.patternEnabled ? "Disable pattern collection" : "Enable pattern collection") {
                    engine.send(["type": "set_pattern_practice", "enabled": !engine.patternEnabled])
                }.disabled(engine.snapshot == nil || engine.pending)
                Button("Clear pattern data") {
                    engine.send(["type": "clear_pattern_practice"])
                }.disabled(engine.snapshot == nil || engine.pending)
            }
            if engine.snapshot?.pattern_fallback == true { Text("More practice is needed; using ordinary words.").font(.caption) }
            if let error = engine.error { Text(error).foregroundColor(.red).accessibilityLabel("Engine error: \(error)") }
            if let state = engine.snapshot {
                Text("\(state.phase.capitalized) · \(state.typed.count)/\(state.prompt.count) characters")
                ScrollView {
                    Text(state.prompt).font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }.frame(height: 120)
                let correct = zip(state.typed, state.prompt).filter { $0 == $1 }.count
                Text("Typed: \(state.typed)").font(.system(.body, design: .monospaced))
                Text("Correct positions: \(correct)/\(state.typed.count) · Remaining: \(state.remaining_ms / 1000)s")
                Text("WPM \(state.wpm) · Raw \(state.raw_wpm) · Accuracy \(state.accuracy, specifier: "%.1f")% · Mistakes \(state.mistakes)")
                if state.phase == "finished" || state.phase == "failed" {
                    Text(state.phase == "failed" ? "Strict attempt failed — not saved" : "Completed · \(state.elapsed_ms / 1000)s")
                        .font(.headline)
                    Text("Best \(state.best_wpm) WPM · Previous \(state.previous_wpm.map(String.init) ?? "—") WPM · Previous accuracy \(state.previous_accuracy.map { String(format: "%.1f%%", $0) } ?? "—")")
                    Text("Prior average \(state.prior_average_wpm.map(String.init) ?? "—") WPM · Errors \(state.prior_average_errors.map { String(format: "%.1f", $0) } ?? "—") · Consistency \(state.consistency.map(String.init) ?? "—")")
                    Text("Pace: \(state.pace_wpm.map(String.init).joined(separator: ", "))")
                }
                Text("Click the outlined area to type (Backspace corrects).")
                Keyboard { text, backspace in
                    if backspace { engine.key(["type": "backspace"]) }
                    else if let text { engine.key(["type": "key", "text": text]) }
                }.frame(height: 45).accessibilityLabel("Typing input; click to focus")
            }
            Spacer(minLength: 0)
        }
        .padding(24).frame(minWidth: 660, minHeight: 510)
        .onDisappear { engine.stop() }
    }
}

@main struct KeyritualMac: App {
    @StateObject private var engine = Engine()
    // Keep the engine across window closure/reopening while the app is alive.
    var body: some Scene { Window("Keyritual", id: "main") { ContentView(engine: engine) } }
}
