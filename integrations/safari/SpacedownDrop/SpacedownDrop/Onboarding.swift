//
//  Onboarding.swift
//  SpacedownDrop
//
//  First-run checklist window, "Preview a sample" (QLPreviewPanel on Resources/Sample.md)
//  and the Quick Look troubleshooter. Contract: docs/contract-r1.md.
//
//  The app is sandboxed, so it cannot ask Quick Look whether the extension is on. The
//  window never fakes that: it shows "Check with the sample", opens the real Quick Look
//  panel on Sample.md, and lets the person say whether it rendered.
//
//  Screenshot hooks (no input is ever sent; the window is only opened in a given state):
//    SPACEDOWN_ONBOARDING_STATE       start | tryit | off | fix | allset
//    SPACEDOWN_ONBOARDING_APPEARANCE  light | dark
//    SPACEDOWN_ONBOARDING_PANEL=1     also open the Quick Look panel on the sample
//  The same three work as launch arguments: --onboarding-state X, --onboarding-appearance X,
//  --onboarding-panel. The window and panel numbers print as "SD_ONBOARDING window=<n>" and
//  "SD_ONBOARDING panel=<n>", for `screencapture -l <n>`.
//

import Cocoa
import Combine
import QuickLookUI
import SafariServices
import SwiftUI

// MARK: - Entry point

enum Onboarding {
    /// Called once from AppDelegate.applicationDidFinishLaunching, after SettingsWindow.install().
    static func start() {
        OnboardingController.shared.start()
    }
}

// MARK: - Constants

private enum Links {
    static let quickLookSettings = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.quicklook.preview")!
    static let extensionsSettings = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!
    #if DEBUG
    static let safariExtensionID = "dfoundation.spacedown.dev.Extension"
    static let quickLookExtensionID = "dfoundation.spacedown.dev.quicklook"
    #else
    static let safariExtensionID = "dfoundation.spacedown.Extension"
    static let quickLookExtensionID = "dfoundation.spacedown.quicklook"
    #endif
    static let brewCommand = "brew install --cask consolelabs/tap/spacedown"
    static let resetCommand = "qlmanage -r && qlmanage -r cache"
    static let seenKey = "onboarding.seen"
    static let confirmedKey = "onboarding.quickLookConfirmed"
}

// MARK: - Model

enum QuickLookStatus {
    case unchecked   // never previewed: "Check with the sample"
    case asked       // panel opened, waiting for the person's answer
    case confirmed   // the person saw a rendered page
    case off         // the person saw plain text
}

enum OnboardingPage { case checklist, fix }

enum SafariStatus: Equatable {
    case notBundled, on, off, unknown
}

enum ClaimantScan: Equatable {
    case scanning
    case unreadable
    case done([String])
}

final class OnboardingModel: ObservableObject {
    @Published var page: OnboardingPage = .checklist
    @Published var quickLook: QuickLookStatus = .unchecked
    @Published var safari: SafariStatus = .notBundled
    @Published var claimants: ClaimantScan = .scanning
    @Published var cliPath: String?
    @Published var copiedID: String?
    /// Tallest the page may be, set from the screen's visible frame. Taller content scrolls.
    @Published var maxContentHeight: CGFloat = 600

    var onPreview: () -> Void = {}
    var onOpenQuickLookSettings: () -> Void = {}
    var onOpenSafariSettings: () -> Void = {}
    var onClose: () -> Void = {}

    func answer(rendered: Bool) {
        quickLook = rendered ? .confirmed : .off
        UserDefaults.standard.set(rendered, forKey: Links.confirmedKey)
    }

    func copy(_ text: String, id: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            if self?.copiedID == id { self?.copiedID = nil }
        }
    }
}

// MARK: - Quick Look panel plumbing

/// A window that takes control of the shared Quick Look panel while it is key.
final class OnboardingWindow: NSWindow {
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = SamplePreview.shared
        panel.delegate = SamplePreview.shared
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}

final class SamplePreview: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = SamplePreview()
    let url = Bundle.main.url(forResource: "Sample", withExtension: "md")

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        url as NSURL?
    }
}

// MARK: - Probes (read only, all tolerate a sandbox that refuses them)

private enum Probe {
    /// Apps in /Applications that ship a Quick Look preview extension declaring Markdown.
    /// A sandboxed app reads only the places it can see, so ~/Applications is not covered.
    static func markdownClaimants() -> ClaimantScan {
        let fm = FileManager.default
        var appURLs: [URL] = []
        var listed = false
        for root in ["/Applications", "/System/Applications"] {
            guard let items = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil) else { continue }
            listed = true
            for item in items {
                if item.pathExtension == "app" {
                    appURLs.append(item)
                } else if let nested = try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil) {
                    appURLs.append(contentsOf: nested.filter { $0.pathExtension == "app" })
                }
            }
        }
        guard listed else { return .unreadable }

        var names = Set<String>()
        var readable = 0
        for app in appURLs {
            let plugIns = app.appendingPathComponent("Contents/PlugIns")
            guard let appexes = try? fm.contentsOfDirectory(at: plugIns, includingPropertiesForKeys: nil) else { continue }
            for appex in appexes where appex.pathExtension == "appex" {
                let info = appex.appendingPathComponent("Contents/Info.plist")
                guard let data = try? Data(contentsOf: info),
                      let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                      let ext = plist["NSExtension"] as? [String: Any],
                      ext["NSExtensionPointIdentifier"] as? String == "com.apple.quicklook.preview"
                else { continue }
                readable += 1
                guard let attrs = ext["NSExtensionAttributes"] as? [String: Any],
                      let types = attrs["QLSupportedContentTypes"] as? [String],
                      types.contains(where: { $0.lowercased().contains("markdown") }),
                      (plist["CFBundleIdentifier"] as? String ?? "").hasPrefix("dfoundation.spacedown") == false
                else { continue }
                names.insert(app.deletingPathExtension().lastPathComponent)
            }
        }
        // Zero readable Quick Look extensions means the sandbox hid them: say so, never "none found".
        return readable == 0 ? .unreadable : .done(names.sorted())
    }

    static func safariStatus(_ done: @escaping (SafariStatus) -> Void) {
        guard let plugIns = Bundle.main.builtInPlugInsURL,
              FileManager.default.fileExists(atPath: plugIns.appendingPathComponent("SpacedownDrop Extension.appex").path) else {
            done(.notBundled)
            return
        }
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: Links.safariExtensionID) { state, error in
            DispatchQueue.main.async {
                guard let state = state, error == nil else { return done(.unknown) }
                done(state.isEnabled ? .on : .off)
            }
        }
    }

    static func cliPath() -> String? {
        ["/opt/homebrew/bin/spacedown", "/usr/local/bin/spacedown"].first {
            FileManager.default.fileExists(atPath: $0)
        }
    }
}

// MARK: - Controller

final class OnboardingController: NSObject {
    static let shared = OnboardingController()

    private let model = OnboardingModel()
    private var window: OnboardingWindow?
    private var hook = Hook()
    private var resizeObserver: NSObjectProtocol?
    private var recenter = false

    /// Screenshot hooks from the environment or launch arguments.
    private struct Hook {
        var state: String?
        var appearance: String?
        var panel = false

        init() {
            let env = ProcessInfo.processInfo.environment
            let args = CommandLine.arguments
            func arg(_ name: String) -> String? {
                guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
                return args[i + 1]
            }
            state = env["SPACEDOWN_ONBOARDING_STATE"] ?? arg("--onboarding-state")
            appearance = env["SPACEDOWN_ONBOARDING_APPEARANCE"] ?? arg("--onboarding-appearance")
            panel = env["SPACEDOWN_ONBOARDING_PANEL"] == "1" || args.contains("--onboarding-panel")
        }
    }

    func start() {
        installMenuItem()
        model.onPreview = { [weak self] in self?.previewSample() }
        model.onOpenQuickLookSettings = { [weak self] in self?.openQuickLookSettings() }
        model.onOpenSafariSettings = { [weak self] in self?.openSafariSettings() }
        model.onClose = { [weak self] in self?.window?.close() }

        if let state = hook.state {
            showForScreenshot(state: state)
            return
        }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Links.seenKey) else { return }
        defaults.set(true, forKey: Links.seenKey)
        showWindow(activate: true)
    }

    @objc func showWelcome(_ sender: Any?) {
        showWindow(activate: true)
    }

    // MARK: Window

    private func showWindow(activate: Bool, center: Bool = true) {
        refreshProbes()
        if model.quickLook == .unchecked, UserDefaults.standard.bool(forKey: Links.confirmedKey) {
            model.quickLook = .confirmed
        }
        if window == nil {
            let hosting = NSHostingController(rootView: OnboardingView(model: model))
            hosting.sizingOptions = [.preferredContentSize]
            let win = OnboardingWindow(contentViewController: hosting)
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.title = "Welcome to Spacedown"
            win.isReleasedWhenClosed = false
            window = win
            // SwiftUI sets the final height after the window exists, and a resize grows the
            // window downward from its top-left corner. Keep it on screen after every resize.
            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification, object: win, queue: .main
            ) { [weak self] _ in self?.fitOnScreen() }
        }
        guard let window = window else { return }
        let shouldCenter = center && !window.isVisible
        recenter = shouldCenter
        updateHeightCap()
        model.page = .checklist
        if activate {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            window.orderFrontRegardless()
        }
        fitOnScreen()
        if shouldCenter {
            // Center once the layout has settled, not on the size the window had at creation.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.fitOnScreen()
                self?.recenter = false
            }
        }
    }

    private func visibleFrame() -> NSRect {
        (window?.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
    }

    /// The page may be as tall as the visible screen minus the title bar; taller content scrolls.
    private func updateHeightCap() {
        guard let window = window else { return }
        let chrome = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 560, height: 100)).height - 100
        model.maxContentHeight = max(240, visibleFrame().height - chrome - 16)
    }

    /// Keep the whole window inside the visible frame (below the menu bar, above the Dock);
    /// while `recenter` is set, put it in the middle instead.
    private func fitOnScreen() {
        guard let window = window else { return }
        let visible = visibleFrame()
        var frame = window.frame
        frame.size.height = min(frame.height, visible.height)
        frame.size.width = min(frame.width, visible.width)
        if recenter {
            frame.origin = NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2)
        } else {
            frame.origin.y = max(visible.minY, min(frame.origin.y, visible.maxY - frame.height))
            frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
        }
        if !NSEqualRects(frame, window.frame) { window.setFrame(frame, display: true) }
    }

    private func showForScreenshot(state: String) {
        switch state {
        case "tryit": model.quickLook = .asked
        case "off": model.quickLook = .off
        case "fix": model.quickLook = .off; model.page = .fix
        case "allset": model.quickLook = .confirmed
        default: model.quickLook = .unchecked
        }
        let wanted = model.page
        let wantedStatus = model.quickLook
        showWindow(activate: false, center: false)
        model.page = wanted
        model.quickLook = wantedStatus
        guard let window = window else { return }
        switch hook.appearance {
        case "dark": window.appearance = NSAppearance(named: .darkAqua)
        case "light": window.appearance = NSAppearance(named: .aqua)
        default: break
        }
        // Only the onboarding window and its panel should be on screen for the capture.
        for other in NSApp.windows where other !== window { other.orderOut(nil) }
        window.setFrameTopLeftPoint(NSPoint(x: 120, y: (NSScreen.main?.visibleFrame.maxY ?? 900) - 80))
        fitOnScreen()
        // SwiftUI sizes the window on its first layout pass; report the number after it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self = self, let window = self.window else { return }
            print("SD_ONBOARDING window=\(window.windowNumber) frame=\(NSStringFromRect(window.frame)) claimants=\(self.model.claimants) safari=\(self.model.safari) cli=\(self.model.cliPath ?? "none") help=\(NSApp.helpMenu?.items.first?.title ?? "none")")
            fflush(stdout)
            if self.hook.panel { self.openPanel(report: true) }
        }
    }

    private func installMenuItem() {
        let item = NSMenuItem(title: "Welcome to Spacedown", action: #selector(showWelcome(_:)), keyEquivalent: "")
        item.target = self
        if let help = NSApp.helpMenu {
            help.insertItem(item, at: 0)
        } else if let app = NSApp.mainMenu?.items.first?.submenu {
            app.insertItem(item, at: min(1, app.items.count))
        }
    }

    private func refreshProbes() {
        model.cliPath = Probe.cliPath()
        Probe.safariStatus { [weak self] in self?.model.safari = $0 }
        model.claimants = .scanning
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let claimants = Probe.markdownClaimants()
            DispatchQueue.main.async { self?.model.claimants = claimants }
        }
    }

    // MARK: Actions

    private func previewSample() {
        if model.quickLook == .unchecked || model.quickLook == .off { model.quickLook = .asked }
        model.page = .checklist
        openPanel(report: false)
    }

    private func openPanel(report: Bool) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if window?.isKeyWindow == true {
            panel.makeKeyAndOrderFront(nil)
        } else {
            // Hook runs keep the app in the background: set the sources directly.
            panel.dataSource = SamplePreview.shared
            panel.delegate = SamplePreview.shared
            panel.orderFrontRegardless()
        }
        panel.reloadData()
        if report {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                print("SD_ONBOARDING panel=\(panel.windowNumber) visible=\(panel.isVisible) frame=\(NSStringFromRect(panel.frame))")
                fflush(stdout)
            }
        }
    }

    private func openQuickLookSettings() {
        if !NSWorkspace.shared.open(Links.quickLookSettings) {
            NSWorkspace.shared.open(Links.extensionsSettings)
        }
    }

    private func openSafariSettings() {
        SFSafariApplication.showPreferencesForExtension(withIdentifier: Links.safariExtensionID) { _ in }
    }
}

// MARK: - Views

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView(.vertical) {
            page.background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                }
            )
        }
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        .frame(width: 560, height: min(max(contentHeight, 120), model.maxContentHeight))
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder private var page: some View {
        switch model.page {
        case .checklist: ChecklistView(model: model)
        case .fix: FixView(model: model)
        }
    }
}

private enum Mark { case todo, done, warn }

private struct StepCard<Content: View>: View {
    let number: Int
    let mark: Mark
    let title: String
    var optional = false
    let detail: String
    var emphasized = false
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            badge
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(title).font(.headline)
                    if optional {
                        Text("Optional")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                }
                Text(detail).font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                content
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(emphasized ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: emphasized ? 1.5 : 1))
        )
    }

    @ViewBuilder private var badge: some View {
        switch mark {
        case .done:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundColor(.green)
                .accessibilityLabel("Done")
        case .warn:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 20)).foregroundColor(.orange)
                .accessibilityLabel("Needs attention")
        case .todo:
            Text("\(number)")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.secondary.opacity(0.18)))
        }
    }
}

private struct CommandBox: View {
    @ObservedObject var model: OnboardingModel
    let id: String
    let command: String

    var body: some View {
        HStack(spacing: 8) {
            Text(command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Button(model.copiedID == id ? "Copied" : "Copy") { model.copy(command, id: id) }
                .controlSize(.small)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
    }
}

private struct StatusLine: View {
    let symbol: String
    let color: Color
    let text: String

    var body: some View {
        Label { Text(text).font(.callout.weight(.medium)) } icon: { Image(systemName: symbol).foregroundColor(color) }
    }
}

private struct Header: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.weight(.bold))
                Text(subtitle).font(.body).foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ChecklistView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Header(title: "Welcome to Spacedown", subtitle: "Three steps and Markdown opens on Space.")
                .padding(.bottom, 4)
            quickLookCard
            safariCard
            cliCard
            HStack {
                Text("Reopen this from the Help menu.").font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("Done") { model.onClose() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
        .padding(24)
    }

    private var quickLookMark: Mark {
        switch model.quickLook {
        case .confirmed: return .done
        case .off: return .warn
        default: return .todo
        }
    }

    private var quickLookCard: some View {
        StepCard(
            number: 1, mark: quickLookMark, title: "Quick Look extension",
            detail: "Turn Spacedown on under Quick Look in System Settings. The app cannot read that switch, so the sample is the check.",
            emphasized: model.quickLook == .asked
        ) {
            VStack(alignment: .leading, spacing: 10) {
                switch model.quickLook {
                case .unchecked:
                    StatusLine(symbol: "questionmark.circle", color: .secondary, text: "Check with the sample")
                    HStack {
                        Button("Preview a sample") { model.onPreview() }.buttonStyle(.borderedProminent)
                        Button("Open System Settings") { model.onOpenQuickLookSettings() }
                    }
                case .asked:
                    StatusLine(symbol: "eye", color: .accentColor, text: "Try it now")
                    Text("The preview panel is open. Does it show a rendered page, with a table and typeset math?")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Yes, it is rendered") { model.answer(rendered: true) }.buttonStyle(.borderedProminent)
                        Button("It shows plain text instead") { model.answer(rendered: false) }
                    }
                    Button("Preview a sample again") { model.onPreview() }.buttonStyle(.link).font(.caption)
                case .confirmed:
                    StatusLine(symbol: "checkmark.circle.fill", color: .green, text: "All set. The sample rendered.")
                    HStack {
                        Button("Preview a sample") { model.onPreview() }
                        Button("Open System Settings") { model.onOpenQuickLookSettings() }
                    }
                case .off:
                    StatusLine(symbol: "xmark.circle.fill", color: .orange, text: "Quick Look still off: the sample showed plain text")
                    HStack {
                        Button("Fix it") { model.page = .fix }.buttonStyle(.borderedProminent)
                        Button("Preview a sample") { model.onPreview() }
                    }
                }
            }
        }
    }

    private var safariCard: some View {
        StepCard(
            number: 2, mark: model.safari == .on ? .done : .todo, title: "Safari drop extension", optional: true,
            detail: "Click its toolbar button in Safari, then drop a .md file on the page to read it there."
        ) {
            switch model.safari {
            case .notBundled:
                StatusLine(symbol: "minus.circle", color: .secondary, text: "Not included in this build")
            case .on:
                StatusLine(symbol: "checkmark.circle.fill", color: .green, text: "On in Safari")
            case .off, .unknown:
                VStack(alignment: .leading, spacing: 8) {
                    StatusLine(symbol: "questionmark.circle", color: .secondary,
                               text: model.safari == .off ? "Off in Safari" : "Turn it on in Safari Settings")
                    Button("Open Safari Settings") { model.onOpenSafariSettings() }
                }
            }
        }
    }

    private var cliCard: some View {
        StepCard(
            number: 3, mark: model.cliPath == nil ? .todo : .done, title: "Command line tool", optional: true,
            detail: "Adds the spacedown command: render a file to HTML or Word from Terminal."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if let path = model.cliPath {
                    StatusLine(symbol: "checkmark.circle.fill", color: .green, text: "Found at \(path)")
                }
                CommandBox(model: model, id: "brew", command: Links.brewCommand)
            }
        }
    }
}

private struct FixView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { model.page = .checklist } label: { Label("Checklist", systemImage: "chevron.left") }
                .buttonStyle(.link)
            Header(title: "Quick Look still off", subtitle: "Try these in order. Preview the sample after each one.")
                .padding(.bottom, 4)

            StepCard(
                number: 1, mark: .todo, title: "Turn it on in System Settings",
                detail: "Open Login Items & Extensions, then Quick Look, and switch Spacedown on."
            ) {
                Button("Open System Settings") { model.onOpenQuickLookSettings() }
            }

            StepCard(
                number: 2, mark: .todo, title: "Another app may claim .md files",
                detail: "Quick Look shows one preview per file type. If another app's Markdown extension is on in the same list, it can win. Switch that one off."
            ) {
                claimantsView
            }

            StepCard(
                number: 3, mark: .todo, title: "Reset Quick Look",
                detail: "A sandboxed app may not run this for you. Paste it into Terminal, then press Return. Finder may need a relaunch."
            ) {
                CommandBox(model: model, id: "reset", command: Links.resetCommand)
            }

            HStack {
                Button("Back to checklist") { model.page = .checklist }
                Spacer()
                Button("Preview the sample again") { model.onPreview() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
        .padding(24)
    }

    @ViewBuilder private var claimantsView: some View {
        switch model.claimants {
        case .scanning:
            StatusLine(symbol: "hourglass", color: .secondary, text: "Looking in /Applications")
        case .unreadable:
            StatusLine(symbol: "lock", color: .secondary,
                       text: "This app is sandboxed and could not read the list of installed apps. Check the Quick Look list in System Settings by eye.")
        case .done(let names) where names.isEmpty:
            VStack(alignment: .leading, spacing: 4) {
                StatusLine(symbol: "checkmark.circle", color: .green, text: "No other Markdown preview found in /Applications")
                Text("Apps in your own Applications folder are not visible to a sandboxed app.")
                    .font(.caption).foregroundColor(.secondary)
            }
        case .done(let names):
            VStack(alignment: .leading, spacing: 4) {
                StatusLine(symbol: "exclamationmark.circle", color: .orange, text: "Found in /Applications:")
                ForEach(names, id: \.self) { name in
                    Text("\u{2022} \(name)").font(.callout)
                }
                Text("Apps in your own Applications folder are not visible to a sandboxed app.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }
}
