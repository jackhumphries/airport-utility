# Security Policy

## Supported Versions

AirPort Utility Powerhouse is a beta project. Security updates are made to the
latest beta and the current `main` branch.

| Version | Supported |
| --- | --- |
| Latest beta release | Yes |
| Latest `main` | Yes |
| Older revisions and forks | No |

## Reporting a Vulnerability

Please report suspected vulnerabilities privately through
[GitHub Private Vulnerability Reporting](https://github.com/pepperstm/airport-utility/security/advisories/new).
Do not open a public issue for an undisclosed vulnerability.

Include as much of the following as possible:

- The affected commit or revision.
- Your macOS and Python versions and the AirPort model involved, if applicable.
- A description of the vulnerability and its potential impact.
- Minimal steps or a proof of concept that reproduces the issue.
- Sanitized logs, traces, or screenshots that help demonstrate the issue.

Before submitting diagnostics, remove passwords, cryptographic material,
configuration exports, IP and MAC addresses, SSIDs, and other private network or
device information.

Relevant reports include vulnerabilities introduced by this repository, such as
credential exposure, command injection, unsafe device operations, firmware
handling flaws, or authentication and protocol-handling weaknesses. Ordinary
bugs, unsupported-device behavior, and feature requests should instead use the
[public issue tracker](https://github.com/pepperstm/airport-utility/issues).
Issues that exist solely in Apple hardware or firmware and are not caused by
this project are outside the scope of this policy and should be reported to the
appropriate vendor.

Reports will be acknowledged and assessed on a best-effort basis. The project
may ask for additional information, coordinate a fix, and agree on a disclosure
date with the reporter. No specific response or remediation timeline is
guaranteed, and this project does not currently offer a bug bounty.

## Safe Testing

Test only on devices and networks that you own or are explicitly authorized to
use. Do not disrupt third-party networks, access third-party data, or perform
destructive testing. In particular, avoid changing passwords, erasing or
archiving disks, or installing firmware unless those actions are necessary,
authorized, and understood.
