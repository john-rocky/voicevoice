import Foundation

// MARK: - Config

let defaultHost = "http://127.0.0.1:50021"
let defaultSpeaker = 3  // ずんだもん ノーマル
let defaultSpeed: Float = 1.0
let sessionsDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("voicevoice_sessions")
let globalFlagFile = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".voicevoice_enabled")
let hookScriptPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".claude/hooks/voicevoice-hook.sh")
let settingsPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".claude/settings.json")
let configPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".voicevoice.json")

// MARK: - Config File

struct VoiceConfig: Codable {
    var speaker: Int
    var speed: Float
    var host: String

    static let `default` = VoiceConfig(speaker: defaultSpeaker, speed: defaultSpeed, host: defaultHost)

    static func load() -> VoiceConfig {
        guard let data = try? Data(contentsOf: configPath),
              let config = try? JSONDecoder().decode(VoiceConfig.self, from: data) else {
            return .default
        }
        return config
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        // Pretty print
        if let json = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
            try? pretty.write(to: configPath)
        } else {
            try? data.write(to: configPath)
        }
    }
}

func configSet(key: String, value: String) {
    var config = VoiceConfig.load()
    switch key {
    case "speaker":
        guard let id = Int(value) else { stderr("Error: speaker must be an integer"); exit(1) }
        config.speaker = id
    case "speed":
        guard let spd = Float(value), spd >= 0.5, spd <= 2.0 else {
            stderr("Error: speed must be 0.5-2.0"); exit(1)
        }
        config.speed = spd
    case "host":
        config.host = value
    default:
        stderr("Unknown config key: \(key). Available: speaker, speed, host")
        exit(1)
    }
    config.save()
    print("Set \(key) = \(value)")
}

func configShow() {
    let c = VoiceConfig.load()
    print("voicevoice config (\(configPath.path)):")
    print("  speaker: \(c.speaker)")
    print("  speed:   \(c.speed)")
    print("  host:    \(c.host)")
}

// MARK: - Usage

func printUsage() {
    let usage = """
    voicevoice - Read aloud with VOICEVOX

    Usage:
      voicevoice "text to speak"
      echo "text" | voicevoice
      voicevoice on              Enable auto-speak for Claude Code
      voicevoice off             Disable auto-speak
      voicevoice setup           Set up Claude Code integration
      voicevoice uninstall       Remove completely (clean environment)
      voicevoice status          Check current status
      voicevoice config          Show current config
      voicevoice config KEY VAL  Set config (speaker, speed, host)

    Options:
      -s, --speaker ID    Speaker/style ID (default: \(defaultSpeaker))
      --speed SPEED       Speech speed 0.5-2.0 (default: \(defaultSpeed))
      -H, --host URL      VOICEVOX engine URL (default: \(defaultHost))
      -l, --list          List available speakers
      -h, --help          Show this help

    Popular speakers:
      0  四国めたん (あまあま)    1  ずんだもん (あまあま)
      2  四国めたん (ノーマル)    3  ずんだもん (ノーマル)
      8  春日部つむぎ            13 青山龍星

    Quick start:
      1. Install VOICEVOX and launch it
      2. voicevoice setup
      3. voicevoice on
      4. Start claude and enjoy!
    """
    FileHandle.standardError.write(Data(usage.utf8))
}

func stderr(_ msg: String) {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
}

// MARK: - Session ID Detection

/// Find the Claude Code process PID by walking up the process tree.
/// Both `! voicevoice on` and the hook script are children of the same Claude process.
func findClaudePID() -> String? {
    var pid = getppid()
    for _ in 0..<10 {
        if pid <= 1 { break }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-o", "comm=", "-p", String(pid)]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        let name = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if name.contains("claude") {
            return String(pid)
        }
        // Go up to parent
        let task2 = Process()
        task2.executableURL = URL(fileURLWithPath: "/bin/ps")
        task2.arguments = ["-o", "ppid=", "-p", String(pid)]
        let pipe2 = Pipe()
        task2.standardOutput = pipe2
        task2.standardError = FileHandle.nullDevice
        try? task2.run()
        task2.waitUntilExit()
        let ppidStr = String(data: pipe2.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let ppid = Int32(ppidStr), ppid > 1 else { break }
        pid = ppid
    }
    return nil
}

// MARK: - on / off / status

func turnOn() {
    let fm = FileManager.default
    if let claudePID = findClaudePID() {
        // Per-session: enable only this Claude Code instance
        try? fm.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        let flag = sessionsDir.appendingPathComponent(claudePID)
        fm.createFile(atPath: flag.path, contents: nil)
        print("voicevoice: ON (this session, pid=\(claudePID))")
    } else {
        // Global: not inside Claude Code
        fm.createFile(atPath: globalFlagFile.path, contents: nil)
        print("voicevoice: ON (all sessions)")
    }
}

func turnOff() {
    let fm = FileManager.default
    if let claudePID = findClaudePID() {
        // Remove per-session flag
        let flag = sessionsDir.appendingPathComponent(claudePID)
        try? fm.removeItem(at: flag)
        // Also remove global flag so the hook actually stops
        if fm.fileExists(atPath: globalFlagFile.path) {
            try? fm.removeItem(at: globalFlagFile)
            print("voicevoice: OFF (this session + global)")
        } else {
            print("voicevoice: OFF (this session)")
        }
    } else {
        // Global off: remove global flag + all session flags
        try? fm.removeItem(at: globalFlagFile)
        try? fm.removeItem(at: sessionsDir)
        print("voicevoice: OFF (all sessions)")
    }
}

func isEnabled() -> Bool {
    let fm = FileManager.default
    if fm.fileExists(atPath: globalFlagFile.path) { return true }
    // Check per-session flags
    if let sessions = try? fm.contentsOfDirectory(atPath: sessionsDir.path), !sessions.isEmpty {
        return true
    }
    return false
}

func showStatus() {
    let fm = FileManager.default
    let globalOn = fm.fileExists(atPath: globalFlagFile.path)
    let sessionFiles = (try? fm.contentsOfDirectory(atPath: sessionsDir.path)) ?? []
    print("voicevoice status:")
    if globalOn {
        print("  Auto-speak: ON (all sessions)")
    } else if !sessionFiles.isEmpty {
        print("  Auto-speak: ON (\(sessionFiles.count) session(s))")
    } else {
        print("  Auto-speak: OFF")
    }

    // Check VOICEVOX engine
    let engineOK: Bool
    do {
        _ = try voicevoxRequest(path: "/version", method: "GET")
        engineOK = true
    } catch {
        engineOK = false
    }
    print("  VOICEVOX engine: \(engineOK ? "Running" : "Not running")")

    // Check hook installed
    let hookInstalled = FileManager.default.fileExists(atPath: hookScriptPath.path)
    print("  Claude Code hook: \(hookInstalled ? "Installed" : "Not installed (run: voicevoice setup)")")
}

// MARK: - VOICEVOX Install

let voicevoxAppPath = "/Applications/VOICEVOX.app"
let voicevoxVersion = "0.25.1"
let voicevoxDMGURL = "https://github.com/VOICEVOX/voicevox/releases/download/\(voicevoxVersion)/VOICEVOX.\(voicevoxVersion)-arm64.dmg"

func isVoicevoxInstalled() -> Bool {
    FileManager.default.fileExists(atPath: voicevoxAppPath)
}

func isVoicevoxRunning() -> Bool {
    (try? voicevoxRequest(path: "/version", method: "GET")) != nil
}

func installVoicevox() {
    print("VOICEVOX is not installed.")
    print("Download and install? (~1.9GB)")
    print("  Source: github.com/VOICEVOX/voicevox/releases")
    print("  License: LGPL v3 (https://voicevox.hiroshiba.jp/term/)")
    print("")
    print("(y/n): ", terminator: "")

    guard let answer = readLine()?.lowercased(), answer == "y" || answer == "yes" else {
        print("Skipped. Install VOICEVOX manually from: https://voicevox.hiroshiba.jp/")
        return
    }

    let dmgPath = FileManager.default.temporaryDirectory.appendingPathComponent("VOICEVOX.dmg")

    // Download
    print("Downloading VOICEVOX \(voicevoxVersion)...")
    let dl = Process()
    dl.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
    dl.arguments = ["-L", "-o", dmgPath.path, "--progress-bar", voicevoxDMGURL]
    try? dl.run()
    dl.waitUntilExit()
    guard dl.terminationStatus == 0 else {
        stderr("Download failed.")
        return
    }

    // Mount
    print("Installing...")
    let mount = Process()
    mount.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
    mount.arguments = ["attach", dmgPath.path, "-nobrowse", "-quiet"]
    let mountPipe = Pipe()
    mount.standardOutput = mountPipe
    try? mount.run()
    mount.waitUntilExit()

    let mountOutput = String(data: mountPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard let volumePath = mountOutput.split(separator: "\t").last?.trimmingCharacters(in: .whitespacesAndNewlines),
          !volumePath.isEmpty else {
        // Try to find mounted volume
        let fallback = "/Volumes/VOICEVOX \(voicevoxVersion)-arm64"
        guard FileManager.default.fileExists(atPath: fallback) else {
            stderr("Failed to mount DMG.")
            return
        }
        copyAndCleanup(volumePath: fallback, dmgPath: dmgPath)
        return
    }
    copyAndCleanup(volumePath: volumePath, dmgPath: dmgPath)
}

private func copyAndCleanup(volumePath: String, dmgPath: URL) {
    let srcApp = "\(volumePath)/VOICEVOX.app"
    guard FileManager.default.fileExists(atPath: srcApp) else {
        stderr("VOICEVOX.app not found in DMG.")
        return
    }

    // Copy to Applications
    let cp = Process()
    cp.executableURL = URL(fileURLWithPath: "/bin/cp")
    cp.arguments = ["-R", srcApp, "/Applications/"]
    try? cp.run()
    cp.waitUntilExit()

    // Unmount
    let unmount = Process()
    unmount.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
    unmount.arguments = ["detach", volumePath, "-quiet"]
    try? unmount.run()
    unmount.waitUntilExit()

    // Remove DMG
    try? FileManager.default.removeItem(at: dmgPath)

    if FileManager.default.fileExists(atPath: voicevoxAppPath) {
        print("[OK] VOICEVOX installed to /Applications/")
    } else {
        stderr("Installation failed. Install manually from: https://voicevox.hiroshiba.jp/")
    }
}

func launchVoicevox() {
    print("Starting VOICEVOX...")
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = ["-a", "VOICEVOX"]
    try? open.run()
    open.waitUntilExit()

    // Wait for engine to be ready
    for i in 1...24 {
        if isVoicevoxRunning() {
            print("[OK] VOICEVOX engine ready")
            return
        }
        if i % 4 == 0 { print("  Waiting for engine... (\(i * 5)s)") }
        Thread.sleep(forTimeInterval: 5)
    }
    stderr("Warning: VOICEVOX engine not responding. Launch VOICEVOX manually.")
}

// MARK: - setup

func setup() {
    let fm = FileManager.default

    // 0. Check/install VOICEVOX
    if !isVoicevoxInstalled() {
        installVoicevox()
    }
    if isVoicevoxInstalled() && !isVoicevoxRunning() {
        launchVoicevox()
    }

    // 1. Create hook script
    let hookDir = hookScriptPath.deletingLastPathComponent()
    try? fm.createDirectory(at: hookDir, withIntermediateDirectories: true)

    let hookScript = """
    #!/bin/bash
    # voicevoice - Claude Code auto-speak hook
    # Reads assistant responses aloud via VOICEVOX

    # Find voicevoice binary
    for p in /opt/homebrew/bin/voicevoice /usr/local/bin/voicevoice "$HOME/bin/voicevoice"; do
      [ -x "$p" ] && VOICEVOICE="$p" && break
    done
    [ -z "$VOICEVOICE" ] && exit 0

    # Check if enabled (global flag or per-session flag)
    ENABLED=0
    [ -f "$HOME/.voicevoice_enabled" ] && ENABLED=1
    if [ "$ENABLED" -eq 0 ]; then
      SESSION_DIR="${TMPDIR:-/tmp}voicevoice_sessions"
      if [ -d "$SESSION_DIR" ]; then
        PID=$$
        for _ in 1 2 3 4 5 6 7 8 9 10; do
          PID=$(ps -o ppid= -p "$PID" 2>/dev/null | tr -d ' ')
          [ -z "$PID" ] || [ "$PID" -le 1 ] 2>/dev/null && break
          [ -f "$SESSION_DIR/$PID" ] && ENABLED=1 && break
        done
      fi
    fi
    [ "$ENABLED" -eq 0 ] && exit 0

    # Find jq
    JQ=$(command -v jq 2>/dev/null || echo "")
    [ -z "$JQ" ] && exit 0

    # Extract assistant's last message (handle both string and array content)
    TEXT=$("$JQ" -r '
      .messages[-1].content |
      if type == "array" then
        [.[] | select(.type == "text") | .text] | join("\\n")
      else
        . // empty
      end
    ' 2>/dev/null)

    # Skip empty
    [ -z "$TEXT" ] && exit 0

    # Truncate long responses
    if [ ${#TEXT} -gt 500 ]; then
      TEXT="${TEXT:0:500}。以下省略。"
    fi

    # Speak in background
    "$VOICEVOICE" "$TEXT" &
    exit 0
    """

    do {
        try hookScript.write(to: hookScriptPath, atomically: true, encoding: .utf8)
        // Make executable
        let attrs = try fm.attributesOfItem(atPath: hookScriptPath.path)
        let perms = (attrs[.posixPermissions] as? Int) ?? 0o644
        try fm.setAttributes([.posixPermissions: perms | 0o111], ofItemAtPath: hookScriptPath.path)
        print("[OK] Hook script created: \(hookScriptPath.path)")
    } catch {
        stderr("[ERROR] Failed to create hook script: \(error.localizedDescription)")
        exit(1)
    }

    // 2. Update settings.json
    var settings: [String: Any] = [:]
    if fm.fileExists(atPath: settingsPath.path),
       let data = try? Data(contentsOf: settingsPath),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        settings = json
    }

    let hookEntry: [String: Any] = [
        "matcher": "",
        "hooks": [
            [
                "type": "command",
                "command": hookScriptPath.path,
                "timeout": 30000
            ] as [String: Any]
        ]
    ]

    var hooks = settings["hooks"] as? [String: Any] ?? [:]
    var stopHooks = hooks["Stop"] as? [[String: Any]] ?? []

    // Remove existing voicevoice hook if any
    stopHooks.removeAll { entry in
        if let entryHooks = entry["hooks"] as? [[String: Any]] {
            return entryHooks.contains { h in
                (h["command"] as? String)?.contains("voicevoice") == true
            }
        }
        return false
    }

    stopHooks.append(hookEntry)
    hooks["Stop"] = stopHooks
    settings["hooks"] = hooks

    do {
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try? fm.createDirectory(at: settingsPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: settingsPath)
        print("[OK] Claude Code settings updated: \(settingsPath.path)")
    } catch {
        stderr("[ERROR] Failed to update settings: \(error.localizedDescription)")
        exit(1)
    }

    print("")
    print("Setup complete! Usage:")
    print("  voicevoice on     Enable auto-speak")
    print("  voicevoice off    Disable auto-speak")
    print("  Then start claude as usual.")
    print("")
    print("During a conversation, toggle with:")
    print("  ! voicevoice on")
    print("  ! voicevoice off")
}

// MARK: - uninstall

func uninstall() {
    let fm = FileManager.default

    // 1. Remove hook from settings.json
    if fm.fileExists(atPath: settingsPath.path),
       let data = try? Data(contentsOf: settingsPath),
       var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

        if var hooks = settings["hooks"] as? [String: Any],
           var stopHooks = hooks["Stop"] as? [[String: Any]] {
            stopHooks.removeAll { entry in
                if let entryHooks = entry["hooks"] as? [[String: Any]] {
                    return entryHooks.contains { h in
                        (h["command"] as? String)?.contains("voicevoice") == true
                    }
                }
                return false
            }
            if stopHooks.isEmpty {
                hooks.removeValue(forKey: "Stop")
            } else {
                hooks["Stop"] = stopHooks
            }
            if hooks.isEmpty {
                settings.removeValue(forKey: "hooks")
            } else {
                settings["hooks"] = hooks
            }
        }

        if let newData = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
            try? newData.write(to: settingsPath)
        }
        print("[OK] Claude Code hook removed from settings")
    }

    // 2. Remove hook script
    if fm.fileExists(atPath: hookScriptPath.path) {
        try? fm.removeItem(at: hookScriptPath)
        print("[OK] Hook script deleted")
    }

    // 3. Remove all flag/config files
    try? fm.removeItem(at: globalFlagFile)
    try? fm.removeItem(at: sessionsDir)
    try? fm.removeItem(at: configPath)
    let lockFile = fm.temporaryDirectory.appendingPathComponent("voicevoice.lock")
    try? fm.removeItem(at: lockFile)
    print("[OK] All flag/config/temp files cleaned up")

    print("")
    print("voicevoice completely removed from Claude Code.")
    print("Your environment is exactly as it was before setup.")
}

// MARK: - VOICEVOX API

func voicevoxRequest(path: String, method: String, queryItems: [URLQueryItem] = [], body: Data? = nil) throws -> Data {
    var components = URLComponents(string: host + path)!
    if !queryItems.isEmpty { components.queryItems = queryItems }
    var request = URLRequest(url: components.url!)
    request.httpMethod = method
    request.timeoutInterval = 30
    if let body {
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    var result: Data?
    var resultError: (any Error)?
    let sem = DispatchSemaphore(value: 0)

    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error { resultError = error }
        else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            resultError = NSError(domain: "VOICEVOX", code: http.statusCode,
                                  userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
        } else {
            result = data
        }
        sem.signal()
    }.resume()

    sem.wait()
    if let resultError { throw resultError }
    return result ?? Data()
}

func listSpeakers() throws {
    let data = try voicevoxRequest(path: "/speakers", method: "GET")
    guard let speakers = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }

    for speaker in speakers {
        let name = speaker["name"] as? String ?? "?"
        let styles = speaker["styles"] as? [[String: Any]] ?? []
        let styleStrs = styles.map { s -> String in
            let sName = s["name"] as? String ?? "?"
            let sId = s["id"] as? Int ?? 0
            return "\(sName)(id=\(sId))"
        }
        print("  \(name): \(styleStrs.joined(separator: ", "))")
    }
}

func speak(_ text: String, speaker: Int, speed: Float) throws {
    // Acquire file lock so multiple instances don't overlap
    let lockPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("voicevoice.lock").path
    let lockFD = open(lockPath, O_CREAT | O_WRONLY, 0o644)
    guard lockFD >= 0 else { throw NSError(domain: "voicevoice", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Failed to create lock file"]) }
    defer { close(lockFD) }
    flock(lockFD, LOCK_EX)  // Wait for exclusive lock
    defer { flock(lockFD, LOCK_UN) }

    var queryData = try voicevoxRequest(
        path: "/audio_query", method: "POST",
        queryItems: [URLQueryItem(name: "text", value: text),
                     URLQueryItem(name: "speaker", value: String(speaker))]
    )

    // Apply speed setting
    if speed != 1.0, var query = try? JSONSerialization.jsonObject(with: queryData) as? [String: Any] {
        query["speedScale"] = speed
        queryData = try JSONSerialization.data(withJSONObject: query)
    }

    let wavData = try voicevoxRequest(
        path: "/synthesis", method: "POST",
        queryItems: [URLQueryItem(name: "speaker", value: String(speaker))],
        body: queryData
    )

    let tmpFile = FileManager.default.temporaryDirectory
        .appendingPathComponent("vv_\(ProcessInfo.processInfo.processIdentifier).wav")
    try wavData.write(to: tmpFile)
    defer { try? FileManager.default.removeItem(at: tmpFile) }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
    process.arguments = [tmpFile.path]
    try process.run()
    process.waitUntilExit()
}

// MARK: - Parse Args

var args = Array(CommandLine.arguments.dropFirst())
let savedConfig = VoiceConfig.load()
var speakerID = savedConfig.speaker
var speedScale = savedConfig.speed
var host = savedConfig.host
var shouldList = false
var textParts: [String] = []

// Handle subcommands first
if let first = args.first {
    switch first {
    case "on":
        turnOn()
        exit(0)
    case "off":
        turnOff()
        exit(0)
    case "setup":
        setup()
        exit(0)
    case "status":
        showStatus()
        exit(0)
    case "uninstall":
        uninstall()
        exit(0)
    case "config":
        if args.count >= 3 {
            configSet(key: args[1], value: args[2])
        } else {
            configShow()
        }
        exit(0)
    case "help":
        printUsage()
        exit(0)
    default:
        break
    }
}

var i = 0
while i < args.count {
    switch args[i] {
    case "-h", "--help":
        printUsage()
        exit(0)
    case "-l", "--list":
        shouldList = true
    case "-s", "--speaker":
        i += 1
        guard i < args.count, let id = Int(args[i]) else {
            stderr("Error: --speaker requires an integer ID")
            exit(1)
        }
        speakerID = id
    case "--speed":
        i += 1
        guard i < args.count, let spd = Float(args[i]), spd >= 0.5, spd <= 2.0 else {
            stderr("Error: --speed requires a number between 0.5 and 2.0")
            exit(1)
        }
        speedScale = spd
    case "-H", "--host":
        i += 1
        guard i < args.count else {
            stderr("Error: --host requires a URL")
            exit(1)
        }
        host = args[i]
    default:
        textParts.append(args[i])
    }
    i += 1
}

// MARK: - Main

do {
    if shouldList {
        try listSpeakers()
        exit(0)
    }

    var text = textParts.joined(separator: " ")

    // Read from pipe if no text argument
    if text.isEmpty && isatty(STDIN_FILENO) == 0 {
        if let stdinData = FileHandle.standardInput.readDataToEndOfFile() as Data?,
           let stdinText = String(data: stdinData, encoding: .utf8) {
            text = stdinText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    if text.isEmpty {
        printUsage()
        exit(1)
    }

    try speak(text, speaker: speakerID, speed: speedScale)
} catch {
    stderr("Error: \(error.localizedDescription)")
    exit(1)
}
