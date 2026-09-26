//
//  SafariWebExtensionHandler.swift
//  SpacedownDrop Extension
//
//  Receives {filename, content} from the dropzone page via
//  browser.runtime.sendNativeMessage and forwards it over XPC to the
//  unsandboxed, launch-on-demand render helper (spacedown-render), which runs
//  the shared `md-open` wrapper (pandoc+KaTeX) and opens Safari. Replies
//  {ok, html} or {ok:false, error}.
//
//  This appex IS App-Sandboxed (required for Safari to load it). A sandboxed
//  handler cannot Process-spawn pandoc, so the spawn lives in the helper reached
//  via a per-user LaunchAgent Mach service; the sandbox carries a mach-lookup
//  temporary-exception for that service name.

import SafariServices
import os.log

// Duplicated (not shared via a file) so the Xcode project needs zero edits; the
// helper declares the identical @objc protocol and they match by name.
@objc(SpacedownRenderService)
protocol SpacedownRenderService {
    func render(name: String, content: String, withReply reply: @escaping (Bool, String) -> Void)
}

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    static let machServiceName = "foundation.d.spacedown.render"

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem

        let message: Any?
        if #available(macOS 11.0, *) {
            message = request?.userInfo?[SFExtensionMessageKey]
        } else {
            message = request?.userInfo?["message"]
        }

        let result = SafariWebExtensionHandler.render(message: message)

        let response = NSExtensionItem()
        if #available(macOS 11.0, *) {
            response.userInfo = [SFExtensionMessageKey: result]
        } else {
            response.userInfo = ["message": result]
        }
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }

    static func render(message: Any?) -> [String: Any] {
        guard let dict = message as? [String: Any],
              let content = dict["content"] as? String else {
            return ["ok": false, "error": "native host: message missing 'content'"]
        }
        let name = (dict["filename"] as? String) ?? "dropped.md"

        let conn = NSXPCConnection(machServiceName: machServiceName)
        conn.remoteObjectInterface = NSXPCInterface(with: SpacedownRenderService.self)
        conn.resume()
        defer { conn.invalidate() }

        let sem = DispatchSemaphore(value: 0)
        var result: [String: Any] = ["ok": false, "error": "render helper did not reply"]

        let proxy = conn.remoteObjectProxyWithErrorHandler { err in
            result = ["ok": false, "error": "render helper unreachable: \(err.localizedDescription)"]
            sem.signal()
        }
        guard let svc = proxy as? SpacedownRenderService else {
            return ["ok": false, "error": "could not obtain render service proxy"]
        }
        svc.render(name: name, content: content) { ok, payload in
            result = ok ? ["ok": true, "html": payload] : ["ok": false, "error": payload]
            sem.signal()
        }
        // pandoc render is fast; cap so a wedged helper can't hang the page.
        _ = sem.wait(timeout: .now() + 30)
        return result
    }
}
