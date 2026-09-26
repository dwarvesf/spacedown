//
//  ViewController.swift
//  SpacedownDrop
//

import Cocoa
import SafariServices
import WebKit

let extensionBundleIdentifier = "foundation.d.spacedown.Extension"

// Opens System Settings on the Quick Look extensions list; the base pane is the fallback.
let quickLookSettingsURL = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.quicklook.preview")!
let extensionsSettingsURL = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!

class ViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {

    @IBOutlet var webView: WKWebView!

    // A default build ships Quick Look alone; the Safari section shows only when the
    // Safari extension is inside the bundle (a --with-safari build).
    let hasSafariExtension: Bool = {
        guard let plugIns = Bundle.main.builtInPlugInsURL else { return false }
        let appex = plugIns.appendingPathComponent("SpacedownDrop Extension.appex")
        return FileManager.default.fileExists(atPath: appex.path)
    }()

    override func viewWillAppear() {
        super.viewWillAppear()
        // The storyboard window title defaults to the product name ("SpacedownDrop");
        // override with the display name, and size the window so the content fits
        // without the WKWebView scrolling.
        self.view.window?.title = "Spacedown"
        self.view.window?.setContentSize(NSSize(width: 460, height: hasSafariExtension ? 640 : 500))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.webView.navigationDelegate = self

        self.webView.configuration.userContentController.add(self, name: "controller")

        self.webView.loadFileURL(Bundle.main.url(forResource: "Main", withExtension: "html")!, allowingReadAccessTo: Bundle.main.resourceURL!)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("setup(\(hasSafariExtension))")
        guard hasSafariExtension else { return }

        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionBundleIdentifier) { (state, error) in
            guard let state = state, error == nil else {
                return
            }

            DispatchQueue.main.async {
                if #available(macOS 13, *) {
                    webView.evaluateJavaScript("show(\(state.isEnabled), true)")
                } else {
                    webView.evaluateJavaScript("show(\(state.isEnabled), false)")
                }
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? String else { return }

        switch body {
        case "open-extensions":
            if !NSWorkspace.shared.open(quickLookSettingsURL) {
                NSWorkspace.shared.open(extensionsSettingsURL)
            }
        case "open-preferences":
            SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionBundleIdentifier) { error in
                DispatchQueue.main.async {
                    NSApplication.shared.terminate(nil)
                }
            }
        default:
            return
        }
    }

}
