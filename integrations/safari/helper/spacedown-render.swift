//
//  spacedown-render.swift
//  Unsandboxed, launch-on-demand XPC helper for the Safari drag-drop extension.
//
//  Why this exists: a Safari Web Extension MUST be App-Sandboxed to load, and a
//  sandboxed handler cannot `Process`-spawn pandoc. So the spawn moved here, into
//  an unsandboxed helper that launchd starts on demand (user LaunchAgent +
//  MachServices) when the sandboxed appex opens an XPC connection.
//
//  Build: swiftc -O spacedown-render.swift -o spacedown-render   (Foundation only)
//  The render logic is the exact spacedown-open spawn moved verbatim from the old
//  SafariWebExtensionHandler.

import Foundation

// Protocol is duplicated (not shared via a file) in the appex handler so the
// Xcode project needs zero edits; they match by the @objc name.
@objc(SpacedownRenderService)
protocol SpacedownRenderService {
    func render(name: String, content: String, withReply reply: @escaping (Bool, String) -> Void)
}

final class RenderImpl: NSObject, SpacedownRenderService {
    func render(name rawName: String, content: String, withReply reply: @escaping (Bool, String) -> Void) {
        // Keep only the basename; ensure a .md/.markdown extension.
        var name = (rawName as NSString).lastPathComponent
        if name.isEmpty { name = "dropped.md" }
        let lower = name.lowercased()
        if !(lower.hasSuffix(".md") || lower.hasSuffix(".markdown")) { name += ".md" }

        let tmpDir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("spacedown-drop-" + UUID().uuidString)
        let srcPath = (tmpDir as NSString).appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
            try content.write(toFile: srcPath, atomically: true, encoding: .utf8)
        } catch {
            reply(false, "could not write temp file: \(error.localizedDescription)")
            return
        }

        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        var env = ProcessInfo.processInfo.environment
        // launchd gives a minimal PATH; add Homebrew + ~/.local/bin so spacedown-open,
        // spacedown, and pandoc resolve.
        env["PATH"] = "/opt/homebrew/bin:\(home)/.local/bin:/usr/local/bin:/usr/bin:/bin"
        env["SPACEDOWN_BROWSER"] = "Safari"   // drop happened in Safari -> open in Safari

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["spacedown-open", srcPath]
        proc.environment = env
        let outPipe = Pipe(), errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        do {
            try proc.run()
        } catch {
            reply(false, "could not launch spacedown-open: \(error.localizedDescription)")
            return
        }
        proc.waitUntilExit()

        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if proc.terminationStatus != 0 {
            let tail = String(err.suffix(600))
            reply(false, tail.isEmpty ? "render failed (exit \(proc.terminationStatus))" : tail)
            return
        }
        let html = out.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
        reply(true, html)
    }
}

// Idle-exit so the helper is truly transient: launchd relaunches it on the next
// connection. Rearmed on every connection; fires when nothing has connected for
// the grace period.
final class IdleExit {
    static let shared = IdleExit()
    private let q = DispatchQueue(label: "dfoundation.spacedown.render.idle")
    private var timer: DispatchSourceTimer?
    private let grace: TimeInterval = 30
    func bump() {
        q.async {
            self.timer?.cancel()
            let t = DispatchSource.makeTimerSource(queue: self.q)
            t.schedule(deadline: .now() + self.grace)
            t.setEventHandler { exit(0) }
            t.resume()
            self.timer = t
        }
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        IdleExit.shared.bump()
        newConnection.exportedInterface = NSXPCInterface(with: SpacedownRenderService.self)
        newConnection.exportedObject = RenderImpl()
        newConnection.invalidationHandler = { IdleExit.shared.bump() }
        newConnection.resume()
        return true
    }
}

// MachService name must match the LaunchAgent plist's MachServices key and the
// extension's mach-lookup temporary-exception entitlement.
let serviceName = "dfoundation.spacedown.render"
let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: serviceName)
listener.delegate = delegate
listener.resume()
IdleExit.shared.bump()   // exit even if launched but never connected
RunLoop.main.run()
