# Sites

Sites let you save a named connection (e.g. "Home", "Office", "Parents'
house") and switch back to it later, instead of waiting for Bonjour to find
it again or retyping its address by hand every time.

## What a site remembers

- A name you choose.
- The base station's Bonjour-derived stable identity, when the connection
  you saved was to a device this app actually discovered on the local
  network. This lets a site self-heal against DHCP address changes: while
  you're on the same network, the app recognises the same physical device at
  whatever address it currently has.
- Its last-known address, used as a fallback when the device isn't currently
  visible via Bonjour — for example, a different physical network, or a
  remote address reached over a VPN.
- When it was last connected to.

**Passwords are never part of a site.** They continue to live only in the
macOS Keychain, keyed by host, exactly as they do today for any connection.

## Connecting to a site

Selecting **Sites…** (File menu) and choosing **Connect** does one of two
things:

- If the site's device is currently visible via Bonjour (matched by its
  stable identity, not its old address), the app connects to it at its
  current address and updates the saved address to match.
- Otherwise, the app falls back to the site's last-known address and
  attempts a normal connection.

A site that can't be reached surfaces exactly like any other failed
connection attempt today — there's no separate "site unreachable" state to
second-guess; the same status and log messages apply.

## Adding and managing sites

**Sites… → Add Current Connection…** saves whatever you're presently
connected to. Rename or remove a saved site from its context menu.

## Storage

Sites are stored at:

```text
~/Library/Application Support/AirPort Utility Powerhouse/Sites/sites.json
```

Local only; not included in support bundles, since it's connection metadata
rather than diagnostic data.
