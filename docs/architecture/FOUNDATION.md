# Application Foundation

## Existing architecture

The project currently consists of:

- `AirPortUtilityApp`: macOS SwiftUI executable entry point
- `AirPortUtilityCore`: views, models and command coordination
- Python backend: reverse-engineered AirPort communication
- Swift Package Manager build
- Shell-based launcher

## Target architecture

### Presentation

SwiftUI views responsible only for rendering state and sending user intents.

### Application services

Services coordinating refreshes, diagnostics, configuration snapshots and safe mutations.

### Domain

Typed models for:

- Base stations
- Network health
- Connected clients
- Storage health
- Backup health
- Diagnostics
- Configuration changes

### Infrastructure

Adapters for:

- Existing Python backend
- Bonjour discovery
- File persistence
- Keychain
- Logging
- Network diagnostics

## Safety boundary

Read operations and write operations must be represented separately.

A mutating operation should follow this sequence:

1. Read current configuration.
2. Export and persist a snapshot.
3. Calculate the proposed change.
4. Present a human-readable preview.
5. Require confirmation.
6. Apply the change.
7. Wait for the base station to restart.
8. Verify reachability and expected state.
9. Offer rollback when verification fails.

## Initial implementation rule

The first dashboard implementation must remain read-only.
