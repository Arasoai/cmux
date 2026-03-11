import Foundation

/// Credential fetched from Bitwarden CLI.
struct BitwardenCredential {
    let name: String
    let username: String
    let password: String
    let uri: String?
}

/// Status of the Bitwarden CLI.
enum BitwardenStatus {
    case notInstalled
    case notLoggedIn
    case locked
    case unlocked(sessionToken: String)
}

/// Thin wrapper around the `bw` CLI for querying credentials.
final class BitwardenProvider {
    static let shared = BitwardenProvider()

    /// Cached session token (in-memory only, never persisted).
    private var sessionToken: String?
    private let queue = DispatchQueue(label: "com.cmuxterm.bitwarden", qos: .userInitiated)

    private init() {}

    // MARK: - Public API

    /// Check whether `bw` is installed and what state it's in.
    func checkStatus(completion: @escaping (BitwardenStatus) -> Void) {
        queue.async {
            guard self.findBW() != nil else {
                DispatchQueue.main.async { completion(.notInstalled) }
                return
            }
            if let token = self.sessionToken, !token.isEmpty {
                // Verify token is still valid
                let (statusOut, _) = self.runBW(["status"])
                if statusOut.contains("\"unlocked\"") {
                    DispatchQueue.main.async { completion(.unlocked(sessionToken: token)) }
                    return
                }
                self.sessionToken = nil
            }
            // Check if logged in
            let (output, _) = self.runBW(["status"])
            if output.contains("\"unauthenticated\"") {
                DispatchQueue.main.async { completion(.notLoggedIn) }
            } else if output.contains("\"locked\"") {
                // Try to resolve session from user's shell environment
                if let shellToken = self.resolveSessionTokenFromShell() {
                    self.sessionToken = shellToken
                    DispatchQueue.main.async { completion(.unlocked(sessionToken: shellToken)) }
                } else {
                    DispatchQueue.main.async { completion(.locked) }
                }
            } else if output.contains("\"unlocked\"") {
                DispatchQueue.main.async { completion(.unlocked(sessionToken: "")) }
            } else {
                DispatchQueue.main.async { completion(.locked) }
            }
        }
    }

    /// Unlock the vault. Returns the session token on success.
    func unlock(masterPassword: String, completion: @escaping (String?) -> Void) {
        queue.async {
            let (output, exitCode) = self.runBW(["unlock", "--raw", masterPassword])
            if exitCode == 0, !output.isEmpty {
                let token = output.trimmingCharacters(in: .whitespacesAndNewlines)
                self.sessionToken = token
                DispatchQueue.main.async { completion(token) }
            } else {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    /// Set session token directly (e.g. from env var or user input).
    func setSessionToken(_ token: String) {
        sessionToken = token
    }

    /// Search for credentials matching a domain.
    func searchCredentials(domain: String, completion: @escaping ([BitwardenCredential]) -> Void) {
        queue.async {
            // Try to resolve session token if we don't have one
            if self.sessionToken == nil {
                if let shellToken = self.resolveSessionTokenFromShell() {
                    self.sessionToken = shellToken
                }
            }
            let args = ["list", "items", "--url", domain]
            let (output, exitCode) = self.runBW(args)
            guard exitCode == 0 else {
                NSLog("BitwardenProvider: search failed for %@ exitCode=%d", domain, exitCode)
                DispatchQueue.main.async { completion([]) }
                return
            }
            let credentials = self.parseItems(json: output)
            NSLog("BitwardenProvider: found %d credentials for %@", credentials.count, domain)
            DispatchQueue.main.async { completion(credentials) }
        }
    }

    // MARK: - Private

    private func findBW() -> String? {
        let paths = [
            "/opt/homebrew/bin/bw",
            "/usr/local/bin/bw",
            "/usr/bin/bw"
        ]
        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // Try PATH via which
        let (output, exitCode) = shell("/usr/bin/which", ["bw"])
        if exitCode == 0 {
            let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty { return path }
        }
        return nil
    }

    private func runBW(_ arguments: [String]) -> (String, Int32) {
        guard let bwPath = findBW() else { return ("", 1) }
        // If we have a session token, inject it via --session flag
        if let token = sessionToken, !token.isEmpty,
           !arguments.contains("--session") {
            return shell(bwPath, arguments + ["--session", token])
        }
        return shell(bwPath, arguments)
    }

    private func shell(_ executablePath: String, _ arguments: [String]) -> (String, Int32) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        // Build environment: inherit app env + inject BW_SESSION if we have one
        var env = ProcessInfo.processInfo.environment
        env["BITWARDENCLI_APPDATA_DIR"] = nil // Use default
        env["BW_NOINTERACTION"] = "true" // Prevent CLI hangs
        if let token = sessionToken, !token.isEmpty {
            env["BW_SESSION"] = token
        }
        process.environment = env

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (output, process.terminationStatus)
        } catch {
            return ("", 1)
        }
    }

    /// Session token file path (~/.config/cmux/bw-session).
    /// Written by user or by `cmux bw-unlock`, read by the app at runtime.
    private static let sessionTokenFilePath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/cmux/bw-session"
    }()

    /// Try to resolve BW_SESSION from multiple sources:
    /// 1. App process environment (if launched from shell with BW_SESSION set)
    /// 2. Session token file (~/.config/cmux/bw-session)
    /// 3. User's login shell environment
    private func resolveSessionTokenFromShell() -> String? {
        // 1. Check app's own environment
        if let envToken = ProcessInfo.processInfo.environment["BW_SESSION"],
           !envToken.isEmpty {
            return envToken
        }
        // 2. Check session file
        if let fileToken = try? String(contentsOfFile: Self.sessionTokenFilePath, encoding: .utf8) {
            let token = fileToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty { return token }
        }
        // 3. Try user's login shell
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let (output, exitCode) = shell("/bin/sh", ["-c", "\(shellPath) -ilc 'echo $BW_SESSION' 2>/dev/null"])
        if exitCode == 0 {
            let token = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty { return token }
        }
        return nil
    }

    private func parseItems(json: String) -> [BitwardenCredential] {
        guard let data = json.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return items.compactMap { item -> BitwardenCredential? in
            guard let login = item["login"] as? [String: Any],
                  let username = login["username"] as? String,
                  let password = login["password"] as? String else {
                return nil
            }
            let name = item["name"] as? String ?? ""
            let uris = login["uris"] as? [[String: Any]]
            let uri = uris?.first?["uri"] as? String
            return BitwardenCredential(name: name, username: username, password: password, uri: uri)
        }
    }
}
