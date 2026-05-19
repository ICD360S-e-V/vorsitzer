# Security Policy

## Reporting a vulnerability

Please report security issues privately via GitHub Security Advisories — **not**
in a public issue or pull request:

  https://github.com/ICD360S-e-V/vorsitzer/security/advisories/new

This goes to the maintainers only and keeps exploit details out of public view
until a patch is released. We acknowledge reports within 7 days and ship fixes
to confirmed high-severity issues within 30 days, distributed through the
in-app auto-update flow.

If GitHub itself is involved (e.g., the report concerns the repository being
publicly leaked), email `claudeai@icd360s.de` with subject `[security]`.

## Scope

In scope:

- Flutter desktop client (Windows + Android) in this repository
- Authentication and session handling (`lib/services/api_service.dart`,
  `lib/services/device_key_service.dart`)
- Client-side cryptography (e.g., `lib/services/routine_service.dart`)
- Server-side API endpoints exposed by `icd360sev.icd360s.de` (server source
  is not in this repository)

Out of scope:

- Vulnerabilities requiring physical access to an unlocked device
- Social engineering of ICD360S e.V. members or staff
- Denial-of-service through high-volume traffic
- Issues that originate in a third-party dependency — report those upstream;
  we pick up patches automatically via Dependabot

## Already-known issues

Public history of this repository contains a hardcoded AES key
(`lib/services/routine_service.dart`, commit `fd34308`) and an old MySQL
password (`CLAUDE.md`, commits `9de48fc..a331a6a`). Both were treated as
compromised at the time of discovery. The AES key is being rotated under
the dual-key versioned-ciphertext scheme tracked in pull request #25; do
not file new reports against either of these without new context.
