# AirPort Utility Powerhouse roadmap

## Direction

Build a safe, modern macOS management and monitoring suite for Apple AirPort
base stations and Time Capsules while retaining compatibility with the
reverse-engineered backend.

## Product rules

1. Monitoring is read-only by default.
2. Configuration changes are previewed before application.
3. Destructive operations require explicit confirmation.
4. Credentials and client identity data do not belong in logs or health history.
5. Missing device data is reported as unknown, never estimated.
6. Failures produce actionable, exportable diagnostics.

## Delivered in 0.1.0 beta 4

- Standalone macOS packaging and continuous integration
- AirPort discovery, topology, startup selection, and configuration workflows
- Network, Internet, wireless, firmware, client, and warning dashboards
- Time Capsule capacity, SMART, SMB, and Time Machine backup health
- Local health notifications and bounded historical trend charts
- Structured redacted logging and diagnostics support bundles
- Gateway, DNS, public-Internet, and likely double-NAT diagnostics
- Removed the packaged app's external `python3` dependency — see
  [ADR-0001](../architecture/ADR-0001-self-contained-backend-runtime.md);
  `build-app.sh` now ships a self-contained backend and CI validates it on
  every push
- Client identification: a real, curated OUI vendor lookup, conservative
  device-type guessing, and local-only nicknames — see
  [client-identification.md](../client-identification.md)
- Per-client SNR and Wi-Fi band in the Connected Clients details, alongside
  the existing Wi-Fi congestion analysis and weak-client detection
- Detection of a base station outside this Mac's local network (VPN/remote
  access or a genuine double-NAT), with a clear Dashboard explanation
  instead of a silent "Not advertised" fallback
- Automatic configuration backups: a standing daily snapshot independent of
  any change made through the app — see
  [automatic-backups.md](../automatic-backups.md)
- Sites: save a named connection and switch back to it later, with
  self-healing against DHCP address changes on the same network — see
  [sites.md](../sites.md)
- Recovery mode: guided next steps (restore known-good settings, or the
  honest physical hard-reset procedure) when a restart, firmware install, or
  configuration write doesn't come back cleanly — see
  [recovery-mode.md](../recovery-mode.md)
- Compare to Current: field-by-field diff between a Configuration History or
  Automatic Backup snapshot and the live settings — or any two visible
  entries from either store compared to each other — before deciding
  whether to restore — see [settings-diff.md](../settings-diff.md)

## Next

Every feature from the original project vision has shipped. What's left is
maintenance-driven rather than a fixed list:

- Expand real-hardware and legacy-model coverage. This is gated on real
  captured behavior, not something to advance by guessing — see
  [hardware-compatibility.md](../hardware-compatibility.md#adding-hardware-coverage).
  GitHub Issues is enabled specifically so reports can come in; use the
  "Hardware compatibility report" issue template.

## Not currently planned

- **Notarised distribution.** Requires a paid Apple Developer Program
  membership; decided against for a hobby-scale project (see
  [apple-credentials-needed.md](../release/apple-credentials-needed.md)).
  The app stays ad-hoc signed — Control-click → Open on first launch is the
  expected steady-state experience, not a temporary gap. Revisit only if
  that calculus changes (e.g. a co-maintainer covers the fee).
- **Concurrent multi-site monitoring.** Sites lets you switch between saved
  connections one at a time; a combined dashboard polling every saved site
  at once would be a real architectural change (background polling per
  device, aggregated state across the app's single-connection model) not
  currently justified by how the app is used. Revisit if that changes.

Features move into a release only after their data source, safety boundary,
failure behavior, privacy impact, and test coverage are documented.
