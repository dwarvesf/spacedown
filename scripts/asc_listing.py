# Fill Spacedown's App Store listing through the App Store Connect API, idempotently:
# categories, subtitle + privacy URL, version copyright + description/keywords/URLs,
# age rating (all none), content rights, free price, all territories, review details
# (contact copied from Hacker Bar), screenshots (APP_DESKTOP), and the build once processed.
# Never submits for review. Prints only non-secret facts.
# Usage: uv run --with pyjwt --with cryptography python asc_listing.py <metadata.json> <screenshot.png>...
import hashlib, json, os, subprocess, sys, time, urllib.error, urllib.request
import jwt

VAULT = "dfoundation-prod"
BUNDLE = "dfoundation.spacedown"
VERSION = "1.0.3"
HACKER_BAR = "dfoundation.hacker-bar"

meta = json.load(open(sys.argv[1]))
shots = sys.argv[2:]

items = json.loads(subprocess.check_output(["op", "item", "list", "--vault", VAULT, "--format", "json"]))
kid_item = next(i["id"] for i in items if i["title"].endswith("Hacker Bar Release"))
f = {x["label"]: x.get("value") for x in json.loads(subprocess.check_output(
    ["op", "item", "get", kid_item, "--vault", VAULT, "--format", "json"]))["fields"]}
KID, ISS, P8 = f["Key ID"], f["Issuer ID"], f["Private Key (.p8 PEM)"]


def call(method, path, body=None, raw_url=None):
    now = int(time.time())
    tok = jwt.encode({"iss": ISS, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
                     P8, algorithm="ES256", headers={"kid": KID, "typ": "JWT"})
    url = raw_url or "https://api.appstoreconnect.apple.com" + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            txt = r.read()
            return r.status, (json.loads(txt) if txt else {})
    except urllib.error.HTTPError as e:
        errs = json.loads(e.read() or b"{}").get("errors", [])
        return e.code, {"errors": [(x.get("code"), x.get("detail")) for x in errs]}


def ok(label, s, d):
    print(f"{label}: {s}" + (f" {d.get('errors')}" if s >= 300 else ""))
    return s < 300


def app_id(bundle):
    s, d = call("GET", f"/v1/apps?filter[bundleId]={bundle}")
    return d["data"][0]["id"]


APP = app_id(BUNDLE)
print("app", APP)

# app-level: content rights
ok("contentRights", *call("PATCH", f"/v1/apps/{APP}", {"data": {"type": "apps", "id": APP,
   "attributes": {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}}))

# appInfo (the editable one), categories, localization, age rating
s, d = call("GET", f"/v1/apps/{APP}/appInfos")
info = next(i for i in d["data"] if i["attributes"].get("appStoreState") not in ("READY_FOR_SALE",))
INFO = info["id"]
rel = {"primaryCategory": {"data": {"type": "appCategories", "id": meta["primaryCategory"]}}}
if meta.get("secondaryCategory"):
    rel["secondaryCategory"] = {"data": {"type": "appCategories", "id": meta["secondaryCategory"]}}
ok("categories", *call("PATCH", f"/v1/appInfos/{INFO}", {"data": {"type": "appInfos", "id": INFO, "relationships": rel}}))
s, d = call("GET", f"/v1/appInfos/{INFO}/appInfoLocalizations")
loc = next(l for l in d["data"] if l["attributes"]["locale"] == meta["locale"])
ok("appInfoLocalization", *call("PATCH", f"/v1/appInfoLocalizations/{loc['id']}", {"data": {
   "type": "appInfoLocalizations", "id": loc["id"],
   "attributes": {"name": meta["name"], "subtitle": meta["subtitle"], "privacyPolicyUrl": meta["privacyPolicyUrl"]}}}))
s, d = call("GET", f"/v1/appInfos/{INFO}/ageRatingDeclaration")
AGE = d["data"]["id"]
age_attrs = {k: "NONE" for k in ["alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated",
             "horrorOrFearThemes", "matureOrSuggestiveThemes", "medicalOrTreatmentInformation",
             "profanityOrCrudeHumor", "sexualContentGraphicAndNudity", "sexualContentOrNudity",
             "violenceCartoonOrFantasy", "violenceRealistic", "violenceRealisticProlongedGraphicOrSadistic",
             "gunsOrOtherWeapons"]}
age_attrs.update({"gambling": False, "unrestrictedWebAccess": False, "lootBox": False,
                  "messagingAndChat": False, "parentalControls": False, "ageAssurance": False,
                  "userGeneratedContent": False, "advertising": False, "healthOrWellnessTopics": False})
s, d = call("PATCH", f"/v1/ageRatingDeclarations/{AGE}", {"data": {"type": "ageRatingDeclarations", "id": AGE, "attributes": age_attrs}})
if s >= 300:  # drop attributes this API version does not know, then retry once
    bad = {e[1].split("'")[1] for e in d["errors"] if e[1] and "'" in e[1]}
    for k in bad: age_attrs.pop(k, None)
    s, d = call("PATCH", f"/v1/ageRatingDeclarations/{AGE}", {"data": {"type": "ageRatingDeclarations", "id": AGE, "attributes": age_attrs}})
ok("ageRating", s, d)

# version: copyright, localization
s, d = call("GET", f"/v1/apps/{APP}/appStoreVersions?filter[platform]=MAC_OS")
ver = next((v for v in d["data"] if v["attributes"]["versionString"] == VERSION), None)
if not ver:  # the draft version made with the record: rename it to match the build
    ver = next(v for v in d["data"] if v["attributes"].get("appStoreState") == "PREPARE_FOR_SUBMISSION")
    ok(f"versionString {ver['attributes']['versionString']} -> {VERSION}", *call("PATCH", f"/v1/appStoreVersions/{ver['id']}",
       {"data": {"type": "appStoreVersions", "id": ver["id"], "attributes": {"versionString": VERSION}}}))
VER = ver["id"]
ok("copyright", *call("PATCH", f"/v1/appStoreVersions/{VER}", {"data": {"type": "appStoreVersions", "id": VER,
   "attributes": {"copyright": meta["copyright"]}}}))
s, d = call("GET", f"/v1/appStoreVersions/{VER}/appStoreVersionLocalizations")
vloc = next(l for l in d["data"] if l["attributes"]["locale"] == meta["locale"])
VLOC = vloc["id"]
ok("versionLocalization", *call("PATCH", f"/v1/appStoreVersionLocalizations/{VLOC}", {"data": {
   "type": "appStoreVersionLocalizations", "id": VLOC, "attributes": {
   "description": meta["description"], "keywords": meta["keywords"], "promotionalText": meta["promotionalText"],
   "supportUrl": meta["supportUrl"], "marketingUrl": meta["marketingUrl"]}}}))

# review details: contact copied from Hacker Bar's latest version
HB = app_id(HACKER_BAR)
s, d = call("GET", f"/v1/apps/{HB}/appStoreVersions?limit=5")
contact = None
for v in d.get("data", []):
    s2, d2 = call("GET", f"/v1/appStoreVersions/{v['id']}/appStoreReviewDetail")
    if s2 == 200 and d2.get("data"):
        a = d2["data"]["attributes"]
        contact = {k: a.get(k) for k in ["contactFirstName", "contactLastName", "contactPhone", "contactEmail"]}
        break
attrs = {"demoAccountRequired": False, "notes": meta["reviewNotes"]}
if contact and all(contact.values()):
    attrs.update(contact)
print("review contact from Hacker Bar:", "yes" if contact and all(contact.values()) else "no")
s, d = call("GET", f"/v1/appStoreVersions/{VER}/appStoreReviewDetail")
if s == 200 and d.get("data"):
    RD = d["data"]["id"]
    ok("reviewDetail", *call("PATCH", f"/v1/appStoreReviewDetails/{RD}", {"data": {"type": "appStoreReviewDetails", "id": RD, "attributes": attrs}}))
else:
    ok("reviewDetail", *call("POST", "/v1/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": attrs,
       "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": VER}}}}}))

# price: free, base territory USA
s, d = call("GET", f"/v1/apps/{APP}/appPricePoints?filter[territory]=USA&limit=200")
free = next(p for p in d["data"] if float(p["attributes"]["customerPrice"]) == 0.0)
ok("price", *call("POST", "/v1/appPriceSchedules", {
    "data": {"type": "appPriceSchedules", "relationships": {
        "app": {"data": {"type": "apps", "id": APP}},
        "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
        "manualPrices": {"data": [{"type": "appPrices", "id": "${price1}"}]}}},
    "included": [{"type": "appPrices", "id": "${price1}", "attributes": {"startDate": None},
                  "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": free["id"]}}}}]}))

# availability: every territory, new ones included
terr = []
url = "/v1/territories?limit=200"
while url:
    s, d = call("GET", url)
    terr += [t["id"] for t in d["data"]]
    nxt = d.get("links", {}).get("next")
    url = nxt.replace("https://api.appstoreconnect.apple.com", "") if nxt else None
s, d = call("POST", "/v2/appAvailabilities", {
    "data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": True},
             "relationships": {"app": {"data": {"type": "apps", "id": APP}},
                               "territoryAvailabilities": {"data": [{"type": "territoryAvailabilities", "id": f"${{t{t}}}"} for t in terr]}}},
    "included": [{"type": "territoryAvailabilities", "id": f"${{t{t}}}", "attributes": {"available": True},
                  "relationships": {"territory": {"data": {"type": "territories", "id": t}}}} for t in terr]})
print(f"availability ({len(terr)} territories): {s}" + (f" {d.get('errors')}" if s >= 300 else ""))

# screenshots
if shots:
    s, d = call("GET", f"/v1/appStoreVersionLocalizations/{VLOC}/appScreenshotSets")
    sset = next((x for x in d.get("data", []) if x["attributes"]["screenshotDisplayType"] == "APP_DESKTOP"), None)
    if not sset:
        s, d = call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets",
                    "attributes": {"screenshotDisplayType": "APP_DESKTOP"},
                    "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": VLOC}}}}})
        sset = d["data"]
    SSET = sset["id"]
    s, d = call("GET", f"/v1/appScreenshotSets/{SSET}/appScreenshots")
    have = {x["attributes"]["fileName"] for x in d.get("data", [])}
    for p in shots:
        name = os.path.basename(p)
        if name in have:
            print(f"screenshot {name}: exists"); continue
        blob = open(p, "rb").read()
        s, d = call("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots",
                    "attributes": {"fileName": name, "fileSize": len(blob)},
                    "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": SSET}}}}})
        if not ok(f"screenshot {name} reserve", s, d): continue
        sid = d["data"]["id"]
        for op in d["data"]["attributes"]["uploadOperations"]:
            chunk = blob[op["offset"]:op["offset"] + op["length"]]
            req = urllib.request.Request(op["url"], data=chunk, method=op["method"],
                                         headers={h["name"]: h["value"] for h in op["requestHeaders"]})
            urllib.request.urlopen(req, timeout=120).read()
        ok(f"screenshot {name} commit", *call("PATCH", f"/v1/appScreenshots/{sid}", {"data": {"type": "appScreenshots", "id": sid,
           "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(blob).hexdigest()}}}))

# build: attach the newest processed 1.0.3 build
s, d = call("GET", f"/v1/builds?filter[app]={APP}&filter[preReleaseVersion.version]={VERSION}&sort=-uploadedDate&limit=5")
builds = [(b["id"], b["attributes"]["version"], b["attributes"]["processingState"]) for b in d.get("data", [])]
print("builds:", [(v, st) for _, v, st in builds])
valid = [b for b in builds if b[2] == "VALID"]
if valid:
    ok("attach build " + valid[0][1], *call("PATCH", f"/v1/appStoreVersions/{VER}/relationships/build",
       {"data": {"type": "builds", "id": valid[0][0]}}))
