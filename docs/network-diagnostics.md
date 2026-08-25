# Network diagnostics

The Diagnostics pane runs four read-only checks from the Mac. Results describe
the Mac's current path through the selected AirPort; they do not change base
station or network settings.

## Checks

- **Gateway** sends one ICMP echo request to the default gateway reported by
  macOS. Some gateways block ICMP, so a failed result is not proof that the
  gateway is offline.
- **DNS** asks the macOS resolver for `captive.apple.com` and requires an address
  in the response. A successful process with an empty response does not pass.
- **Public Internet** attempts a TCP connection to `1.1.1.1` on port 443. This
  tests a public route without relying on DNS; it does not prove that every site
  or protocol is available.
- **Double NAT** is an assessment rather than an active probe. When the AirPort
  is routing and reports a private or carrier-grade NAT WAN address, upstream
  NAT is likely. Bridge Mode is reported as not applicable. Missing WAN data
  remains unknown.

Checks run only when requested. They may be affected by firewalls, VPNs,
content filters, captive portals, and temporary packet loss. The app does not
present a failed probe as a configuration diagnosis without supporting data.

The latest results and check time are included in redacted diagnostic support
bundles. No packet contents, browsing history, or credentials are collected.
