# Packaging

Assets shared by `make-app.sh` and `AirPortUtility.xcodeproj`.

| File | Purpose |
| --- | --- |
| `Info.plist` | Bundle metadata. Uses `$(VAR)` placeholders that Xcode substitutes natively and `make-app.sh` substitutes with `sed`, so one file serves both build paths. |
| `AirPortUtility.entitlements` | Intentionally an empty dict — see below. |
| `AppIcon.png` | 1254×1254 icon source, transparent outside the squircle. |
| `AppIcon.icns` | Generated from `AppIcon.png`. Regenerate with the command below. |

## Why the entitlements file is empty

The app is **not sandboxed**, so it needs none of the sandbox-gated entitlements
(`com.apple.security.network.*`, `files.user-selected`, keychain). Those only
constrain sandboxed processes.

Hardened Runtime *is* required for notarization, but it is enabled by
`codesign --options runtime`, not by an entitlement. No Hardened Runtime
exception is needed here: the app loads no third-party libraries into its own
process, and spawning the bundled Python backend as a child process needs no
`com.apple.security.cs.*` key.

The file is kept, rather than omitted, so there is one obvious place to add a
key later — but note that **AMFI's parser rejects XML comments inside an
entitlements plist** (`AMFIUnserializeXML: syntax error`), which is why this
explanation lives here instead of in the file.

## Info.plist keys that are load-bearing

- `NSLocalNetworkUsageDescription` + `NSBonjourServices` — on macOS 15+ the app
  is its own TCC principal. Without these, Bonjour discovery silently returns
  nothing and ACP connections to port 5009 fail. Running from Terminal masks
  this, because there the permission belongs to Terminal.
- `LSEnvironment/PATH` — Finder-launched apps inherit a minimal PATH, so the
  backend's `#!/usr/bin/env python3` would resolve to `/usr/bin/python3`
  (a Command Line Tools stub, Python 3.9.6). The backend's full test suite does
  pass on 3.9.6, but this prefers a real interpreter when one is installed.
- `LSEnvironment/PYTHONDONTWRITEBYTECODE` — the backend ships inside the signed
  bundle. Without this, Python writes `__pycache__` beside it on import,
  mutating a sealed resource and invalidating the code signature.

## Regenerating the icon

```sh
SET=$(mktemp -d)/AppIcon.iconset && mkdir -p "$SET"
for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
            "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" \
            "512 icon_256x256@2x" "512 icon_512x512" "1024 icon_512x512@2x"; do
  sips -s format png -z "${spec%% *}" "${spec%% *}" Packaging/AppIcon.png \
    --out "$SET/${spec#* }.png" >/dev/null
done
iconutil -c icns "$SET" -o Packaging/AppIcon.icns
```
