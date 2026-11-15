//
//  SettingsWindow.swift
//  SpacedownDrop
//
//  The Settings window: theme, appearance, text size, outline default, X-ray rules.
//  Writes SpacedownSettings.store (shared/SpacedownSettings.swift); the Quick Look
//  extension reads it on the next preview. Contract: docs/contract-r1.md.
//
//  One file by contract: every type below lives here. Release 2 adds Inbox and License
//  tabs: add a case to `SettingsTab`, list it in `SettingsTab.shown`, and give it a view
//  in `SettingsWindowController.makeView(for:)`.
//
//  Screenshot hooks (read only from the environment, never written to the store):
//    SPACEDOWN_SETTINGS_TAB=general|xray        open Settings on launch, on that tab
//    SPACEDOWN_SETTINGS_APPEARANCE=light|dark   force the window's own appearance
//

import Cocoa
import Combine
import CoreText
import SwiftUI

// MARK: - Entry point

enum SettingsWindow {
    /// Called once from AppDelegate.applicationDidFinishLaunching.
    static func install() {
        registerBundledFonts()
        SettingsMenu.install()
        let env = ProcessInfo.processInfo.environment
        if let name = env["SPACEDOWN_SETTINGS_TAB"] {
            let tab = SettingsTab(rawValue: name) ?? .general
            DispatchQueue.main.async { show(tab: tab) }
        }
    }

    /// Open the window, on `tab` when given, and bring it forward.
    static func show(tab: SettingsTab? = nil) {
        SettingsWindowController.shared.present(tab: tab)
    }

    /// The preview shows the iA faces when the bundled CLI carries them. Best effort: a
    /// missing file leaves the system fallback in place.
    private static func registerBundledFonts() {
        guard let base = Bundle.main.resourceURL?.appendingPathComponent("cli/assets/fonts/ia") else { return }
        for name in ["iAWriterQuattroV.ttf", "iAWriterMonoV.ttf"] {
            let url = base.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}

// MARK: - Menu item

/// Adds "Settings..." (Cmd+,) to the application menu.
private final class SettingsMenu: NSObject {
    static let shared = SettingsMenu()

    static func install() {
        guard let menu = NSApp.mainMenu?.items.first?.submenu else { return }
        if menu.items.contains(where: { $0.keyEquivalent == "," }) { return }
        let item = NSMenuItem(title: "Settings\u{2026}", action: #selector(open(_:)), keyEquivalent: ",")
        item.target = shared
        // After "About" and its separator, where macOS apps keep it.
        let at = min(2, menu.items.count)
        menu.insertItem(item, at: at)
        menu.insertItem(.separator(), at: at + 1)
    }

    @objc func open(_ sender: Any?) { SettingsWindow.show() }
}

// MARK: - Tabs and window

enum SettingsTab: String, CaseIterable {
    case general, xray

    var title: String {
        switch self {
        case .general: return "General"
        case .xray: return "X-ray"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .xray: return "eye"
        }
    }

    /// Fixed content size per tab: NSTabViewController resizes the window to it.
    var contentSize: NSSize {
        switch self {
        case .general: return NSSize(width: 540, height: 478)
        case .xray: return NSSize(width: 540, height: 368)
        }
    }

    /// The tabs release 1 shows. Release 2 appends Inbox and License here.
    static var shown: [SettingsTab] { [.general, .xray] }
}

private final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private let model = SettingsModel()
    private let tabs = NSTabViewController()

    init() {
        tabs.tabStyle = .toolbar
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        super.init(window: window)

        for tab in SettingsTab.shown {
            let host = NSHostingController(rootView: Self.makeView(for: tab, model: model))
            host.title = tab.title
            host.preferredContentSize = tab.contentSize
            let item = NSTabViewItem(viewController: host)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            tabs.addTabViewItem(item)
        }

        let env = ProcessInfo.processInfo.environment
        switch env["SPACEDOWN_SETTINGS_APPEARANCE"] {
        case "dark": window.appearance = NSAppearance(named: .darkAqua)
        case "light": window.appearance = NSAppearance(named: .aqua)
        default: break
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static func makeView(for tab: SettingsTab, model: SettingsModel) -> AnyView {
        switch tab {
        case .general: return AnyView(GeneralSettingsView(model: model))
        case .xray: return AnyView(XraySettingsView(model: model))
        }
    }

    func present(tab: SettingsTab?) {
        if let tab = tab, let index = SettingsTab.shown.firstIndex(of: tab) {
            tabs.selectedTabViewItemIndex = index
        }
        model.reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(nil)
    }
}

// MARK: - Model

/// The window's state. Every property is one contract key in `SpacedownSettings.store`,
/// written on change. A stored value that is missing or invalid reads as the default.
final class SettingsModel: ObservableObject {
    private let store = SpacedownSettings.store
    private var loading = false

    /// Last explicit choice, for the "Follow system" switch to return to.
    private(set) var lastExplicitAppearance = "light"

    @Published var theme: String { didSet { save("theme", theme) } }
    @Published var appearance: String {
        didSet {
            if appearance != "system" { lastExplicitAppearance = appearance }
            save("appearance", appearance)
        }
    }
    @Published var textSize: Int { didSet { save("textSize", textSize) } }
    @Published var outlineDefault: String { didSet { save("outlineDefault", outlineDefault) } }
    @Published var xrayEnabled: Bool { didSet { save("xrayEnabled", xrayEnabled) } }
    @Published var xrayDashes: Bool { didSet { save("xrayDashes", xrayDashes) } }
    @Published var xrayLongSentences: Bool { didSet { save("xrayLongSentences", xrayLongSentences) } }
    @Published var xraySentenceWords: Int { didSet { save("xraySentenceWords", xraySentenceWords) } }
    @Published var xrayFillers: Bool { didSet { save("xrayFillers", xrayFillers) } }
    /// The comma list as typed. The store gets the trimmed, non-empty entries.
    @Published var fillerText: String { didSet { saveFillers() } }
    @Published var xrayTicketIds: Bool { didSet { save("xrayTicketIds", xrayTicketIds) } }

    static let generalKeys = ["theme", "appearance", "textSize", "outlineDefault"]
    static let xrayKeys = ["xrayEnabled", "xrayDashes", "xrayLongSentences", "xraySentenceWords",
                           "xrayFillers", "xrayFillerWords", "xrayTicketIds"]

    init() {
        let v = Snapshot(store: SpacedownSettings.store)
        theme = v.theme
        appearance = v.appearance
        textSize = v.textSize
        outlineDefault = v.outlineDefault
        xrayEnabled = v.xrayEnabled
        xrayDashes = v.xrayDashes
        xrayLongSentences = v.xrayLongSentences
        xraySentenceWords = v.xraySentenceWords
        xrayFillers = v.xrayFillers
        fillerText = v.fillers.joined(separator: ", ")
        xrayTicketIds = v.xrayTicketIds
        if v.appearance != "system" { lastExplicitAppearance = v.appearance }
    }

    /// Re-read the store, without writing anything back.
    func reload() {
        let v = Snapshot(store: store)
        loading = true
        defer { loading = false }
        theme = v.theme
        appearance = v.appearance
        textSize = v.textSize
        outlineDefault = v.outlineDefault
        xrayEnabled = v.xrayEnabled
        xrayDashes = v.xrayDashes
        xrayLongSentences = v.xrayLongSentences
        xraySentenceWords = v.xraySentenceWords
        xrayFillers = v.xrayFillers
        let current = Self.parseFillers(fillerText)
        if current != v.fillers { fillerText = v.fillers.joined(separator: ", ") }
        xrayTicketIds = v.xrayTicketIds
    }

    /// Back to the defaults for these keys: the key is removed, so every reader falls
    /// back to the render core's default, not to a copy of it.
    func restoreDefaults(keys: [String]) {
        for key in keys { store.removeObject(forKey: key) }
        reload()
    }

    private func save(_ key: String, _ value: Any) {
        guard !loading else { return }
        store.set(value, forKey: key)
    }

    /// The text field writes its binding back when it loses focus, even unchanged. An
    /// untouched list must not become a stored copy of the default, or a later release
    /// could not change that default for this user.
    private func saveFillers() {
        let list = Self.parseFillers(fillerText)
        let untouched = store.object(forKey: "xrayFillerWords") == nil
            && list == (SpacedownSettings.defaults["xrayFillerWords"] as? [String] ?? [])
        if untouched { return }
        save("xrayFillerWords", list)
    }

    static func parseFillers(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// One validated read of the store.
    private struct Snapshot {
        let theme: String
        let appearance: String
        let textSize: Int
        let outlineDefault: String
        let xrayEnabled: Bool
        let xrayDashes: Bool
        let xrayLongSentences: Bool
        let xraySentenceWords: Int
        let xrayFillers: Bool
        let fillers: [String]
        let xrayTicketIds: Bool

        init(store: UserDefaults) {
            func fallback<T>(_ key: String) -> T { SpacedownSettings.defaults[key] as! T }
            func choice(_ key: String, _ allowed: [String]) -> String {
                if let s = store.object(forKey: key) as? String, allowed.contains(s) { return s }
                return fallback(key)
            }
            func int(_ key: String, _ range: ClosedRange<Int>) -> Int {
                if let n = (store.object(forKey: key) as? NSNumber)?.intValue { return min(max(n, range.lowerBound), range.upperBound) }
                return fallback(key)
            }
            func flag(_ key: String) -> Bool {
                if let n = store.object(forKey: key) as? NSNumber { return n.boolValue }
                return fallback(key)
            }
            theme = choice("theme", ThemeOption.all.map { $0.id })
            appearance = choice("appearance", ["system", "light", "dark"])
            textSize = int("textSize", 12...32)
            outlineDefault = choice("outlineDefault", ["auto", "open", "closed"])
            xrayEnabled = flag("xrayEnabled")
            xrayDashes = flag("xrayDashes")
            xrayLongSentences = flag("xrayLongSentences")
            xraySentenceWords = int("xraySentenceWords", 8...80)
            xrayFillers = flag("xrayFillers")
            if let list = store.object(forKey: "xrayFillerWords") as? [String] {
                fillers = list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            } else {
                fillers = fallback("xrayFillerWords")
            }
            xrayTicketIds = flag("xrayTicketIds")
        }
    }
}

// MARK: - Themes (the preview's twin of ql-settings.css)

struct ThemeOption: Identifiable {
    let id: String
    let name: String
    let families: [String]
    let design: Font.Design
    /// Heading size relative to the body; iA keeps headings at body size, bold.
    let headingScale: CGFloat
    let leading: CGFloat
    let paper: (light: UInt32, dark: UInt32)
    let ink: (light: UInt32, dark: UInt32)
    let mono: [String]

    static let all: [ThemeOption] = [
        ThemeOption(id: "ia", name: "iA", families: ["iA Writer Quattro V", "iA Writer Quattro S"], design: .default,
                    headingScale: 1.0, leading: 0.64,
                    paper: (0xFCFCFC, 0x1A1A1A), ink: (0x1A1A1A, 0xCCCCCC), mono: ["iA Writer Mono V"]),
        ThemeOption(id: "tm", name: "Thinking Machines serif", families: ["Georgia"], design: .serif,
                    headingScale: 1.3, leading: 0.65,
                    paper: (0xFFFFFF, 0x1B1A19), ink: (0x282828, 0xE6E2DC), mono: ["SF Mono", "Menlo"]),
        ThemeOption(id: "paper", name: "Paper", families: ["iA Writer Quattro V", "iA Writer Quattro S"], design: .default,
                    headingScale: 1.3, leading: 0.6,
                    paper: (0xFBFAF7, 0x1F1E1C), ink: (0x242321, 0xE4E1DA), mono: ["iA Writer Mono V"]),
        ThemeOption(id: "read", name: "Read serif", families: ["Georgia"], design: .serif,
                    headingScale: 1.3, leading: 0.6,
                    paper: (0xFCFCFC, 0x1A1A1A), ink: (0x1F1F1F, 0xD6D6D6), mono: ["JetBrains Mono", "Menlo"]),
        ThemeOption(id: "mono", name: "Mono", families: ["iA Writer Mono V", "iA Writer Mono S"], design: .monospaced,
                    headingScale: 1.3, leading: 0.6,
                    paper: (0xFCFCFC, 0x1A1A1A), ink: (0x1A1A1A, 0xCCCCCC), mono: ["iA Writer Mono V"]),
    ]

    static func named(_ id: String) -> ThemeOption { all.first { $0.id == id } ?? all[0] }

    private static let installed = Set(NSFontManager.shared.availableFontFamilies)

    private func firstInstalled(_ names: [String]) -> String? { names.first { Self.installed.contains($0) } }

    func bodyFont(_ size: CGFloat) -> Font {
        if let family = firstInstalled(families) { return .custom(family, size: size) }
        return .system(size: size, design: design)
    }

    func codeFont(_ size: CGFloat) -> Font {
        if let family = firstInstalled(mono) { return .custom(family, size: size) }
        return .system(size: size, design: .monospaced)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - Views

private let labelWidth: CGFloat = 150

private struct SettingRow<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .frame(width: labelWidth, alignment: .trailing)
            VStack(alignment: .leading, spacing: 6) { content }
            Spacer(minLength: 0)
        }
    }
}

private struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

private struct RestoreBar: View {
    let action: () -> Void
    var body: some View {
        HStack {
            Spacer()
            Button("Restore defaults", action: action)
        }
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var model: SettingsModel
    @Environment(\.colorScheme) private var colorScheme

    private var followSystem: Binding<Bool> {
        Binding(get: { model.appearance == "system" },
                set: { model.appearance = $0 ? "system" : model.lastExplicitAppearance })
    }

    private var previewScheme: ColorScheme {
        switch model.appearance {
        case "dark": return .dark
        case "light": return .light
        default: return colorScheme
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingRow("Theme") {
                Picker("Theme", selection: $model.theme) {
                    ForEach(ThemeOption.all) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
                .frame(width: 240)
            }

            SettingRow("Appearance") {
                Toggle("Follow system light and dark", isOn: followSystem)
                if model.appearance != "system" {
                    Picker("Appearance", selection: $model.appearance) {
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
                }
            }

            SettingRow("Text size") {
                HStack(spacing: 8) {
                    Stepper(value: $model.textSize, in: 12...32) {
                        Text("\(model.textSize) px").monospacedDigit().frame(width: 52, alignment: .leading)
                    }
                }
            }

            SettingRow("Outline sidebar") {
                Picker("Outline sidebar", selection: $model.outlineDefault) {
                    Text("Auto").tag("auto")
                    Text("Open").tag("open")
                    Text("Closed").tag("closed")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                Caption("Auto lets the window width decide.")
            }

            Divider()

            TypePreview(theme: ThemeOption.named(model.theme), size: model.textSize, scheme: previewScheme)

            Spacer(minLength: 0)
            RestoreBar { model.restoreDefaults(keys: SettingsModel.generalKeys) }
        }
        .padding(EdgeInsets(top: 32, leading: 24, bottom: 24, trailing: 24))
        .frame(width: 540, height: 500, alignment: .topLeading)
    }
}

private struct TypePreview: View {
    let theme: ThemeOption
    let size: Int
    let scheme: ColorScheme

    private var paper: Color { Color(hex: scheme == .dark ? theme.paper.dark : theme.paper.light) }
    private var ink: Color { Color(hex: scheme == .dark ? theme.ink.dark : theme.ink.light) }

    var body: some View {
        let s = CGFloat(size)
        VStack(alignment: .leading, spacing: s * 0.6) {
            Text("Spacedown")
                .font(theme.bodyFont(s * theme.headingScale))
                .fontWeight(.bold)
            Text("Press the spacebar on a Markdown file in Finder and read it as a page.")
                .font(theme.bodyFont(s))
                .lineSpacing(s * theme.leading * 0.5)
            Text("render(file)")
                .font(theme.codeFont(s * 0.94))
        }
        .foregroundColor(ink)
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 190, maxHeight: 190, alignment: .topLeading)
        .background(paper)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.35), lineWidth: 1))
    }
}

struct XraySettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingRow("Default") {
                Toggle("X-ray on by default", isOn: $model.xrayEnabled)
                Caption("Opens each page with the marks showing. The toolbar switch still toggles them.")
            }

            Divider()

            SettingRow("Marks") {
                Toggle("Em and en dashes", isOn: $model.xrayDashes)
                Toggle("Long sentences", isOn: $model.xrayLongSentences)
                HStack(spacing: 8) {
                    Text("Longer than").foregroundColor(.secondary)
                    Stepper(value: $model.xraySentenceWords, in: 8...80) {
                        Text("\(model.xraySentenceWords) words").monospacedDigit().frame(width: 76, alignment: .leading)
                    }
                }
                .disabled(!model.xrayLongSentences)
                .padding(.leading, 20)
                Toggle("Filler words", isOn: $model.xrayFillers)
                VStack(alignment: .leading, spacing: 4) {
                    TextField("very, really, just", text: $model.fillerText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                    Caption("Separate words and phrases with commas.")
                }
                .disabled(!model.xrayFillers)
                .padding(.leading, 20)
                Toggle("Ticket and spec IDs", isOn: $model.xrayTicketIds)
            }

            Spacer(minLength: 0)
            RestoreBar { model.restoreDefaults(keys: SettingsModel.xrayKeys) }
        }
        .padding(EdgeInsets(top: 32, leading: 24, bottom: 24, trailing: 24))
        .frame(width: 540, height: 400, alignment: .topLeading)
    }
}
