#!/usr/bin/env bash
# check-model.sh: drive the Settings window's model (SettingsModel in SettingsWindow.swift)
# the way the controls do and read the saved values back from the shared store with the
# contract's key names and types. No window opens and nothing is clicked.
#   bash docs/verification/r1-settings/check-model.sh
# It writes the real settings domain (W777S7V8TN.dfoundation.spacedown) and puts back what
# it found there. Needs swiftc.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
APP="${ROOT}/integrations/safari/SpacedownDrop/SpacedownDrop"
WORK="$(mktemp -d)"
cat > "${WORK}/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) { print(ok ? "ok   \(what)" : "FAIL \(what)"); if !ok { failures += 1 } }

let store = SpacedownSettings.store
let before = SpacedownSettings.stored()
defer { for k in SpacedownSettings.defaults.keys { if let v = before[k] { store.set(v, forKey: k) } else { store.removeObject(forKey: k) } } }
let allKeys = SettingsModel.generalKeys + SettingsModel.xrayKeys
for k in allKeys { store.removeObject(forKey: k) }

let m = SettingsModel()
check(m.theme == "ia" && m.appearance == "system" && m.textSize == 18 && m.outlineDefault == "auto", "an empty store reads as the contract defaults")
check(m.xrayEnabled == false && m.xrayDashes && m.xrayLongSentences && m.xraySentenceWords == 25 && m.xrayFillers && m.xrayTicketIds, "X-ray defaults")

m.fillerText = m.fillerText
check(SpacedownSettings.stored()["xrayFillerWords"] == nil, "the text field writing back an untouched list stores nothing")

m.theme = "tm"; m.appearance = "dark"; m.textSize = 24; m.outlineDefault = "closed"
m.xrayEnabled = true; m.xrayDashes = false; m.xrayLongSentences = false; m.xraySentenceWords = 40
m.xrayFillers = false; m.fillerText = "very,  really , ,of course"; m.xrayTicketIds = false
let s = SpacedownSettings.stored()
check(s["theme"] as? String == "tm", "theme saved as string")
check(s["appearance"] as? String == "dark", "appearance saved as string")
check(s["textSize"] as? Int == 24, "textSize saved as int")
check(s["outlineDefault"] as? String == "closed", "outlineDefault saved as string")
check(s["xrayEnabled"] as? Bool == true, "xrayEnabled saved as bool")
check(s["xrayDashes"] as? Bool == false, "xrayDashes saved as bool")
check(s["xrayLongSentences"] as? Bool == false, "xrayLongSentences saved as bool")
check(s["xraySentenceWords"] as? Int == 40, "xraySentenceWords saved as int")
check(s["xrayFillers"] as? Bool == false, "xrayFillers saved as bool")
check(s["xrayFillerWords"] as? [String] == ["very", "really", "of course"], "xrayFillerWords saved as trimmed list, empty entries dropped")
check(s["xrayTicketIds"] as? Bool == false, "xrayTicketIds saved as bool")

let again = SettingsModel()
check(again.theme == "tm" && again.textSize == 24 && again.fillerText == "very, really, of course", "a new window reads back what was saved")

store.set(99, forKey: "textSize"); store.set("neon", forKey: "theme"); store.set(1, forKey: "xraySentenceWords")
let bad = SettingsModel()
check(bad.textSize == 32 && bad.theme == "ia" && bad.xraySentenceWords == 8, "out-of-range int clamps, unknown enum falls back to the default")

m.reload()
m.restoreDefaults(keys: SettingsModel.generalKeys)
let afterGeneral = SpacedownSettings.stored()
check(afterGeneral["theme"] == nil && afterGeneral["textSize"] == nil && m.theme == "ia" && m.textSize == 18, "Restore defaults on General clears General keys")
check(afterGeneral["xrayFillerWords"] != nil, "Restore defaults on General leaves X-ray keys alone")
m.restoreDefaults(keys: SettingsModel.xrayKeys)
check(SpacedownSettings.stored().isEmpty && m.fillerText.contains("very, really"), "Restore defaults on X-ray clears the rest")

print(failures == 0 ? "check-model: all passed" : "check-model: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT
swiftc -O -o "${WORK}/check" "${WORK}/main.swift" "${APP}/SettingsWindow.swift" "${ROOT}/integrations/safari/shared/SpacedownSettings.swift" 2>&1 | grep -E "error" && exit 2
"${WORK}/check"
