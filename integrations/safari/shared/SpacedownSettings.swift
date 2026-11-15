//
//  SpacedownSettings.swift
//  Shared by the app (writes) and the Quick Look extension (reads).
//
//  One store: the App Group defaults suite below. Keys, types and defaults mirror
//  SD.DEFAULTS in quick-look/Resources/ql-render.js; test-contract.js fails when the
//  two drift. Contract: docs/contract-r1.md.
//

import Foundation

enum SpacedownSettings {
    /// App Group id in the macOS team-prefixed form, so no provisioning profile entry is
    /// needed. Also named in both targets' entitlements and in scripts/sd-settings.
    static let suiteName = "W777S7V8TN.dfoundation.spacedown"

    /// Every key with its default. The render core validates values and fills gaps, so
    /// the extension passes only what the user set (see `stored`).
    static let defaults: [String: Any] = [
        "theme": "ia",
        "appearance": "system",
        "textSize": 18,
        "outlineDefault": "auto",
        "xrayEnabled": false,
        "xrayDashes": true,
        "xrayLongSentences": true,
        "xraySentenceWords": 25,
        "xrayFillers": true,
        "xrayFillerWords": ["very", "really", "just", "actually", "basically", "simply", "quite", "rather", "somewhat", "literally", "obviously", "clearly", "of course", "in order to"],
        "xrayTicketIds": true,
    ]

    /// The shared suite. Falls back to the process's own defaults when the App Group is
    /// not granted (an adhoc build), so a reader then sees no stored values.
    static var store: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// The known keys that hold a value in `store`, unvalidated.
    static func stored(in store: UserDefaults = store) -> [String: Any] {
        var out: [String: Any] = [:]
        for key in defaults.keys {
            if let value = store.object(forKey: key) { out[key] = value }
        }
        return out
    }
}
