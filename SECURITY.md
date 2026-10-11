# Security policy

Security fixes will focus on the latest public Karim Ink preview. Older preview versions may not receive separate fixes.

## Report a security issue

Use [GitHub private vulnerability reporting](https://github.com/12kareem2323-png/karim-ink/security/advisories/new) if it is available for this repository. If it is not available, open a minimal [issue](https://github.com/12kareem2323-png/karim-ink/issues) asking for a private reporting route, without publishing the vulnerability details.

Include the affected version, the impact and safe reproduction steps. Do not attach credentials, private drawings or other people's information. This project does not currently promise a response time or offer a bug bounty.

## Download and data handling

Get the Mac app from the [official release page](https://github.com/12kareem2323-png/karim-ink/releases/tag/v0.1.0). Version 0.1.0 is **ad hoc signed and unnotarized**, with no Apple Developer ID signature. Check the SHA-256 checksum. A checksum identifies a file; it does not replace developer signing or notarization. Keep macOS security protections enabled. [Support](SUPPORT.md) links Apple's per-app first-launch instructions; this project does not recommend disabling Gatekeeper or removing quarantine flags.

API and Craft credentials use macOS Keychain. Drawings and exports are ordinary files protected by your Mac's file permissions; they are not encrypted by Karim Ink. Optional network features are described in [PRIVACY.md](PRIVACY.md).

The app validates supported drawing and scene formats and bounds resource sizes. This reduces risk but does not make arbitrary imported files safe or establish that every defect has been removed. Keep important editable files backed up.

The supported scope is the Karim Ink app and repository. Third-party tablet drivers, cloud providers, payment services and external workspace software have their own security processes.
