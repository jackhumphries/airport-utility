# Licensing notice

This project is **dual-licensed**:

- **MIT** (see [`LICENSE`](LICENSE)) — the default license, covering the
  original codebase and everything derived from it. Most of this project was
  first written by Jack Humphries, whose copyright interest in that original
  work remains under the MIT terms; files that started as his work stay MIT
  even where they've since been modified.
- **GPLv3** (see [`COPYING`](COPYING)) — covers a specific list of files that
  are entirely or almost entirely new work by Graham Barber, with no
  meaningful amount of Jack Humphries' original code in them. Each such file
  carries an `SPDX-License-Identifier: GPL-3.0-only` header at the top
  identifying it as GPLv3.

## Why a split rather than one license for everything

MIT permits sublicensing a combined/derivative work, so relicensing the
*whole* project to GPLv3 unilaterally would have been technically legal.
It would not have been honest, though: the current codebase is still
overwhelmingly Jack Humphries' original work by any reasonable measure (a
`git blame` line-count across all Swift and Python source, done when this
split was decided, attributed roughly 89% of lines to him and 11% to Graham
Barber), including in many files Graham has since edited. Declaring the
entire project GPLv3 would have overstated Graham's authorship of code he
didn't write. The split below keeps Jack's original contribution correctly
attributed and under the terms it was always available under, while letting
Graham choose GPLv3 for the parts that are genuinely his.

## How the file list was determined (2026-08-22)

A file was assigned to GPLv3 only if `git blame -w -M -C` line attribution
across its current content showed more lines credited to Graham Barber (or
his `pepperstm` git identity — the same person) than to Jack Humphries. In
practice, essentially every qualifying file was either 100% Graham's or
within a line or two of it — there was no close call that needed a
judgment call beyond that threshold.

## Files under GPLv3

```
Sources/AirPortUtilityCore/AirportAppModelNotifications.swift
Sources/AirPortUtilityCore/AirportAppModelStorageHealth.swift
Sources/AirPortUtilityCore/AutomaticConfigurationBackup.swift
Sources/AirPortUtilityCore/ClientIdentity.swift
Sources/AirPortUtilityCore/ConfigurationHistory.swift
Sources/AirPortUtilityCore/Dashboard/DashboardNetworkSummary.swift
Sources/AirPortUtilityCore/Dashboard/DashboardPane.swift
Sources/AirPortUtilityCore/Diagnostics/DefaultDiagnosticsService.swift
Sources/AirPortUtilityCore/Diagnostics/DiagnosticsBundle.swift
Sources/AirPortUtilityCore/Diagnostics/DiagnosticsPane.swift
Sources/AirPortUtilityCore/Diagnostics/DiagnosticsService.swift
Sources/AirPortUtilityCore/HardwareCompatibility.swift
Sources/AirPortUtilityCore/HealthHistory.swift
Sources/AirPortUtilityCore/Logging/AppLogCategory.swift
Sources/AirPortUtilityCore/Logging/AppLogger.swift
Sources/AirPortUtilityCore/Logging/LogEntry.swift
Sources/AirPortUtilityCore/Logging/LogRedactor.swift
Sources/AirPortUtilityCore/Logging/PersistentLogStore.swift
Sources/AirPortUtilityCore/NetworkDiagnostics.swift
Sources/AirPortUtilityCore/RecoveryGuidance.swift
Sources/AirPortUtilityCore/SettingsDiff.swift
Sources/AirPortUtilityCore/SettingsDiffSheet.swift
Sources/AirPortUtilityCore/Sites.swift
Sources/AirPortUtilityCore/SitesSheet.swift
Sources/AirPortUtilityCore/StorageHealth.swift
Sources/AirPortUtilityCore/StorageNotifications.swift
Sources/AirPortUtilityCore/TimeMachineBackup.swift
Sources/AirPortUtilityCore/WiFiCongestion.swift
Tests/AirPortUtilityAppTests/ClientIdentityTests.swift
Tests/AirPortUtilityAppTests/ConfigurationHistoryTests.swift
Tests/AirPortUtilityAppTests/DashboardNetworkSummaryTests.swift
Tests/AirPortUtilityAppTests/DiagnosticsBundleTests.swift
Tests/AirPortUtilityAppTests/HealthHistoryTests.swift
Tests/AirPortUtilityAppTests/LogRedactorTests.swift
Tests/AirPortUtilityAppTests/NetworkDiagnosticsTests.swift
Tests/AirPortUtilityAppTests/PersistentLogStoreTests.swift
Tests/AirPortUtilityAppTests/SettingsDiffTests.swift
Tests/AirPortUtilityAppTests/SitesTests.swift
Tests/AirPortUtilityAppTests/StorageHealthTests.swift
Tests/AirPortUtilityAppTests/StorageNotificationTests.swift
Tests/AirPortUtilityAppTests/TimeMachineBackupTests.swift
Tests/AirPortUtilityAppTests/WiFiCongestionTests.swift
```

Everything else in this repository — including `backend/*.py`, the majority
of `Sources/`, and all files not listed above — is MIT-licensed under
[`LICENSE`](LICENSE).

If a future change moves substantial new code into or out of a file, or a
new file is added, re-run the same `git blame`-based check before assuming
its license status; don't add an SPDX header based on guesswork.
