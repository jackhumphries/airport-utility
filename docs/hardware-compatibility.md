# Hardware compatibility reporting

AirPort Utility uses the product identifier reported by an AirPort to select
device-specific behavior. Diagnostics now shows whether that identifier belongs
to the compatibility profiles currently recognised by the app and includes the
assessment in redacted support bundles.

## Assessment states

- **Recognised** means the reported product identifier is present in the app's
  compatibility table. It does not guarantee that every function has been
  exercised on that exact hardware and firmware combination.
- **Unrecognised** means the AirPort reported a non-empty identifier that the app
  does not know. The app does not substitute a visually similar model or invent
  capabilities. A redacted support bundle can be attached to a compatibility
  report so the identifier and observed behavior can be reviewed.
- **Unidentified** means no usable product identifier was reported. The model
  name alone is not used to claim compatibility.

The enabled-capabilities list reflects the app's active profile, including such
items as disks, AirPlay, firmware handling, modem support, remote logging, and
legacy options. A missing item can mean either that the hardware does not support
it or that the current profile has not enabled it; it is not proof that a device
feature is absent.

## Support-bundle data

The compatibility section contains:

- product identifier;
- reported model name and firmware version when available;
- assessment state and explanatory summary;
- names of the device-specific capabilities enabled by the app.

It does not add passwords, configuration payloads, client identities, hardware
addresses, backup paths, or logs beyond the bundle's existing redaction rules.
Users should still review the exact JSON preview before exporting it.

## Adding hardware coverage

An unfamiliar identifier is intentionally not promoted into the recognised
table from a single name match. A useful compatibility report includes the
redacted diagnostics bundle, the physical model number, firmware version, macOS
version, and the exact operation that succeeded or failed. New profiles should
be backed by captured behavior and regression tests before they are treated as
supported.
