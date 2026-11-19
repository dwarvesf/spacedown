# App Store Connect setup for Spacedown's Mac App Store build, idempotent.
#  1. register bundle ids (MAC_OS) for the app and the Quick Look extension
#  2. create an Apple Distribution + a Mac Installer Distribution certificate from a key
#     generated here, import both identities into the login keychain, back them up to
#     1Password (one item: p12 file + passphrase), then remove the local key material
#  3. create MAC_APP_STORE provisioning profiles and save them to PROFILE_DIR
# Prints only non-secret facts. The API key and the private key never reach stdout.
# Usage: uv run --with pyjwt --with cryptography python asc_setup.py [--dry-run]
#   --dry-run  check the settings below and look up the keychain identities, then stop:
#              no 1Password read, no App Store Connect call, nothing created.
# Env (required, no defaults):
#   OP_VAULT          the 1Password vault for the API key item and the p12 backup
#   ASC_OP_ITEM       the API key item's title, or the end of it ("Key ID", "Issuer ID",
#                     "Private Key (.p8 PEM)" fields)
#   MAS_P12_OP_TITLE  the title of the 1Password item the new p12 backup is saved as
#   CSR_SUBJECT       the openssl subject for the certificate request, e.g. /emailAddress=<you>/CN=<team name>/C=<country>
# Optional: TEAM_ID (default W777S7V8TN).
import base64, json, os, re, secrets, subprocess, sys, tempfile, time, urllib.request, urllib.error


def need(name, what):
    v = os.environ.get(name, "")
    if not v:
        sys.exit(f"asc_setup: {name} unset: {what}")
    return v


DRY_RUN = sys.argv[1:] == ["--dry-run"]
if sys.argv[1:] and not DRY_RUN:
    sys.exit("usage: asc_setup.py [--dry-run]")
VAULT = need("OP_VAULT", "name the 1Password vault that holds the App Store Connect API key")
ASC_ITEM = need("ASC_OP_ITEM", "name the 1Password item (title or its end) that holds the API key")
BACKUP_TITLE = need("MAS_P12_OP_TITLE", "name the 1Password item to save the p12 backup as")
CSR_SUBJECT = need("CSR_SUBJECT", "give the certificate request subject, e.g. /emailAddress=<you>/CN=<team name>/C=<country>")
TEAM = os.environ.get("TEAM_ID", "W777S7V8TN")
IDS = {"dfoundation.spacedown": "Spacedown", "dfoundation.spacedown.quicklook": "Spacedown Quick Look"}
PROFILE_DIR = os.path.expanduser("~/.local/share/spacedown-signing")
OPENSSL = "/opt/homebrew/bin/openssl"

# The identities this script needs, found in the keychain by kind and team, so no legal
# name is hardcoded here. A kind with no identity yet gets a new certificate below.
KINDS = {"DISTRIBUTION": "Apple Distribution", "MAC_INSTALLER_DISTRIBUTION": "3rd Party Mac Developer Installer"}
idents = subprocess.run(["security", "find-identity", "-v"], capture_output=True, text=True).stdout
def keychain_identity(kind):
    m = re.search(r'"(' + re.escape(kind) + r': [^"]+ \(' + re.escape(TEAM) + r'\))"', idents)
    return m.group(1) if m else None
want = {ctype: keychain_identity(kind) for ctype, kind in KINDS.items()}

if DRY_RUN:
    for ctype, name in want.items():
        print(f"dry run: {ctype}: {name or 'not in the keychain, would create a certificate'}")
    print(f"dry run: API key item ending {ASC_ITEM!r} in vault {VAULT!r}; p12 backup title {BACKUP_TITLE!r}")
    print("dry run: stopping; nothing read, created or uploaded")
    sys.exit(0)

import jwt

items = json.loads(subprocess.check_output(["op", "item", "list", "--vault", VAULT, "--format", "json"]))
key_item = next((i["id"] for i in items if i["title"].endswith(ASC_ITEM)), None)
if not key_item:
    sys.exit(f"asc_setup: no item ending {ASC_ITEM!r} in vault {VAULT!r}")
f = {x["label"]: x.get("value") for x in json.loads(subprocess.check_output(
    ["op", "item", "get", key_item, "--vault", VAULT, "--format", "json"]))["fields"]}
KID, ISS, P8 = f["Key ID"], f["Issuer ID"], f["Private Key (.p8 PEM)"]

def call(method, path, body=None):
    now = int(time.time())
    tok = jwt.encode({"iss": ISS, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
                     P8, algorithm="ES256", headers={"kid": KID, "typ": "JWT"})
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request("https://api.appstoreconnect.apple.com" + path, data=data, method=method,
                                 headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        detail = json.loads(e.read() or b"{}").get("errors", [{}])[0].get("detail", "")
        return e.code, {"error": detail}

# 1. bundle ids
bundle = {}
for ident, name in IDS.items():
    s, d = call("GET", f"/v1/bundleIds?filter[identifier]={ident}&filter[platform]=MAC_OS")
    hit = [b for b in d.get("data", []) if b["attributes"]["identifier"] == ident]
    if hit:
        bundle[ident] = hit[0]["id"]; print(f"bundleId {ident}: exists")
    else:
        s, d = call("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes":
                    {"identifier": ident, "name": name, "platform": "MAC_OS"}}})
        if s != 201: sys.exit(f"bundleId {ident}: create failed {s} {d.get('error')}")
        bundle[ident] = d["data"]["id"]; print(f"bundleId {ident}: created")

# 2. certificates: reuse ones whose identity is already in this keychain
cert_ids = {}
s, d = call("GET", "/v1/certificates?limit=200&fields[certificates]=certificateType,serialNumber,displayName")
existing = d.get("data", [])
missing = []
for ctype, cname in want.items():
    if cname:
        serials = subprocess.run(["security", "find-certificate", "-a", "-c", cname, "-Z", "-p"],
                                 capture_output=True, text=True).stdout
        cert_ids[ctype] = next((c["id"] for c in existing if c["attributes"]["certificateType"] == ctype), None)
        print(f"certificate {ctype}: identity already in keychain")
    else:
        missing.append(ctype)

if missing:
    work = tempfile.mkdtemp(); os.chmod(work, 0o700)
    try:
        key = os.path.join(work, "key.pem"); csr = os.path.join(work, "req.csr")
        subprocess.check_call([OPENSSL, "genrsa", "-out", key, "2048"], stderr=subprocess.DEVNULL)
        subprocess.check_call([OPENSSL, "req", "-new", "-key", key, "-out", csr, "-subj",
                               CSR_SUBJECT])
        csr_body = "".join(l for l in open(csr).read().splitlines() if "CERTIFICATE REQUEST" not in l)
        passphrase = secrets.token_urlsafe(24)
        p12s = []
        for ctype in missing:
            s, d = call("POST", "/v1/certificates", {"data": {"type": "certificates", "attributes":
                        {"certificateType": ctype, "csrContent": csr_body}}})
            if s != 201: sys.exit(f"certificate {ctype}: create failed {s} {d.get('error')}")
            cert_ids[ctype] = d["data"]["id"]
            der = os.path.join(work, f"{ctype}.cer"); pem = os.path.join(work, f"{ctype}.pem")
            open(der, "wb").write(base64.b64decode(d["data"]["attributes"]["certificateContent"]))
            subprocess.check_call([OPENSSL, "x509", "-inform", "DER", "-in", der, "-out", pem])
            subj = subprocess.check_output([OPENSSL, "x509", "-noout", "-subject", "-nameopt", "RFC2253", "-in", pem], text=True)
            m = re.search(r"CN=((?:[^,\\]|\\.)*)", subj)
            want[ctype] = m.group(1).replace("\\", "") if m else f"{KINDS[ctype]} ({TEAM})"
            p12 = os.path.join(work, f"{ctype}.p12")
            subprocess.check_call([OPENSSL, "pkcs12", "-export", "-legacy", "-in", pem, "-inkey", key,
                                   "-name", want[ctype], "-passout", "pass:" + passphrase, "-out", p12])
            subprocess.check_call(["security", "import", p12, "-k",
                                   os.path.expanduser("~/Library/Keychains/login.keychain-db"),
                                   "-P", passphrase, "-T", "/usr/bin/codesign", "-T", "/usr/bin/productbuild",
                                   "-T", "/usr/bin/security"], stdout=subprocess.DEVNULL)
            p12s.append(p12)
            print(f"certificate {ctype}: created and imported")
        args = ["op", "item", "create", "--category=password", "--vault", VAULT, "--title", BACKUP_TITLE,
                "password=" + passphrase] + [f"{os.path.basename(p)}[file]={p}" for p in p12s]
        ok = subprocess.run(args, capture_output=True).returncode == 0
        print("1Password backup:", "created" if ok else "FAILED (keychain import still stands)")
    finally:
        subprocess.run(["rm", "-rf", work])

# 3. MAC_APP_STORE profiles bound to the distribution certificate
os.makedirs(PROFILE_DIR, exist_ok=True)
dist_id = cert_ids.get("DISTRIBUTION")
if not dist_id: sys.exit("no DISTRIBUTION certificate id; cannot create profiles")
for ident, bid in bundle.items():
    name = f"Spacedown MAS {ident}"
    s, d = call("GET", f"/v1/profiles?filter[name]={urllib.request.quote(name)}&filter[profileType]=MAC_APP_STORE")
    prof = next((p for p in d.get("data", []) if p["attributes"]["profileState"] == "ACTIVE"), None)
    if not prof:
        s, d = call("POST", "/v1/profiles", {"data": {"type": "profiles",
                    "attributes": {"name": name, "profileType": "MAC_APP_STORE"},
                    "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}},
                                      "certificates": {"data": [{"type": "certificates", "id": dist_id}]}}}})
        if s != 201: sys.exit(f"profile {ident}: create failed {s} {d.get('error')}")
        prof = d["data"]; print(f"profile {ident}: created")
    else:
        print(f"profile {ident}: exists")
    out = os.path.join(PROFILE_DIR, f"{ident}.provisionprofile")
    open(out, "wb").write(base64.b64decode(prof["attributes"]["profileContent"]))
    print(f"  saved {out}")
