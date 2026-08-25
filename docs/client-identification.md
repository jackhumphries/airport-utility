# Client identification

The Dashboard's Connected Clients list adds a vendor name, a guessed device
type, and an optional local nickname to each wireless client, alongside the
existing hostname/IP/signal/rate/PHY columns.

## Vendor lookup

Each client's vendor is looked up from its MAC address's OUI
(Organizationally Unique Identifier — the first three bytes) against a
curated table built from the official IEEE MA-L registry
(`https://standards-oui.ieee.org/oui/oui.txt`), filtered down to vendors
common on a home network (Apple, Amazon, Google, Samsung, Sonos, Ubiquiti,
printer and TV manufacturers, and similar). It is not the full registry —
only real, verified entries for those vendors are included, and an
unmatched OUI is reported as no vendor, never a guess.

Two things intentionally prevent a wrong answer:

- **Locally-administered (randomized) addresses are detected and excluded.**
  Modern iOS, Android, and macOS devices commonly randomize their MAC
  address per network specifically to prevent this kind of tracking. The
  app checks the standard locally-administered bit and reports "Private
  address" rather than attempting — and potentially getting wrong — a
  vendor lookup on an address that was never assigned to a real
  manufacturer.
- **Ambiguous multi-category vendors are shown, not used to guess a device
  type.** Samsung, Canon, LG, and similar vendors make products across many
  categories; showing "Samsung" as the vendor is factual, but guessing a
  specific device type from that alone would not be (see below).

## Device-type guessing

A device type (iPhone, Mac, Printer, Speaker, etc.) is shown next to each
client, following the same "never estimate missing data" principle as
[hardware compatibility reporting](hardware-compatibility.md)'s
Recognised/Unrecognised/Unidentified states:

- A hostname that plainly names the device ("Grahams-iPhone") is trusted
  first — it's a much stronger signal than anything derived from the
  vendor.
- Failing that, only a short list of vendors that are, in practice,
  single-purpose on a home network (Sonos, Nintendo, Epson, Brother,
  Ubiquiti, eero) are used to guess a type at all.
- Everything else — including every OEM/chip vendor whose parts end up in
  many different rebranded products (Espressif, Broadcom, Realtek, Hon Hai,
  Murata) and every vendor that makes products across multiple categories —
  is reported as an unknown device type rather than a guess.

## Local network requirement

IP address and hostname discovery works by priming this Mac's ARP table with
local pings, which only works when this Mac shares a Layer-2 network segment
with the base station. When it doesn't — connecting over a VPN or other
remote access, or across a genuine double-NAT boundary — the app detects
this (by comparing the base station's address against this Mac's own local
interface subnets) and shows a note at the top of Connected Clients
explaining why, rather than silently showing "Not advertised" with no
explanation. Vendor names, device types, and nicknames are unaffected, since
those are derived from the MAC address alone.

## Local nicknames

Right-click (or Control-click) a client in the Connected Clients list to
rename it. The name is stored only on this Mac, keyed by MAC address, at
`~/Library/Application Support/AirPort Utility Powerhouse/ClientIdentity/client-names.json`.
It is never sent to the AirPort or to the device itself, and has no effect
on the device's actual advertised hostname — it only changes what this app
displays.

## What this does not do

- It does not fingerprint devices beyond their MAC address and advertised
  hostname — no traffic inspection, no additional network probing.
- It does not attempt to identify a device more precisely than the
  conservative rules above allow. An "Unknown" device type is the correct,
  honest answer whenever the signal isn't strong enough to be confident.
