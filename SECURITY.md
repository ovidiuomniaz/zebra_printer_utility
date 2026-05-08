# Security Policy

## Reporting a vulnerability

Please report suspected vulnerabilities by opening a GitHub issue marked **(security)** at https://github.com/ovidiuomniaz/zebra_printer_utility/issues, or email the maintainer privately if the issue is sensitive.

Expected response time: best-effort, typically within a week.

## Scope and threat model

This plugin is a Flutter wrapper around Zebra's Link-OS Multiplatform SDK. It connects to label printers over **Bluetooth (RFCOMM / MFi)** and **TCP/IP** on the local network. It is intentionally *not* a hardened transport — most of the security boundary lives in the printer firmware and the LAN it sits on. Integrators should understand the limits below before deploying.

### In-scope vulnerabilities

- Memory-safety, injection, or RCE bugs in Dart, Java, Swift, or Obj-C code in this repo.
- Vulnerabilities in vendored binaries (`android/libs/*.jar`, `ios/libZSDK_API.a`) — see [`docs/VENDORED.md`](docs/VENDORED.md) for the current inventory and SHA-256s.
- Excessive Android runtime permissions or location-data exposure.
- Method-channel surface bugs that allow a Flutter caller to escape the plugin's intended scope (e.g., reading arbitrary files, invoking unrelated system APIs).

### Out of scope — known limitations

- **No TLS on printer connections.** Zebra ZPL/CPCL printing over TCP (port 6101 or 9100) is **cleartext** by design of the protocols; the plugin does not wrap them in TLS, and most Zebra firmware does not support it on these ports. **Treat the LAN as the security boundary.** A LAN attacker can:
  - Sniff every print payload (which may include PII — names, addresses, prescriptions, receipts).
  - ARP-spoof the printer's IP and exfiltrate or alter content.
  - Inject arbitrary ZPL into the real printer, including commands that change persistent settings (calibration, network config).
  - Mitigation: deploy printers on a VLAN or isolated Wi-Fi SSID; do not expose them to untrusted clients.
- **Arbitrary ZPL via `print(String data)`.** The `print` method takes raw ZPL/CPCL and forwards it verbatim to the printer. ZPL has no privilege-escalation surface, but it can permanently reconfigure the printer. **Integrators must validate ZPL coming from untrusted input** before passing it to `print`.
- **Bluetooth pairing**. The plugin discovers and connects to BT printers using the OS pairing flow. Trust of the paired device is delegated to the OS / user.
- **Outdated transitive Java libraries.** The bundled Zebra Android SDK transitively depends on `jackson-databind 2.2.3`, `commons-*`, `httpcore`, `opencsv`, etc. — all old. See [`docs/VENDORED.md`](docs/VENDORED.md) for the inventory and the path forward (upgrade Zebra SDK to 3.x). Reachability of any specific CVE requires that the relevant code path is invoked at runtime.

## Hardening recommendations for integrators

- Run printers on an isolated network segment (VLAN or dedicated Wi-Fi).
- Validate / template any ZPL that comes from user input or external systems.
- Pin the printer IP and reject unexpected MAC addresses on first connect.
- Subscribe to `ZebraStatus` events and treat unexpected disconnects/reconnects as suspicious.
- Audit every plugin upgrade against [`docs/VENDORED.md`](docs/VENDORED.md) — re-introduction of a removed JAR or modification of a SHA should fail your build.

## Audit history

- 2026-05-07 — Initial security audit and remediation plan: see [`docs/SECURITY-AUDIT.md`](docs/SECURITY-AUDIT.md) and [`docs/REMEDIATION-PLAN.md`](docs/REMEDIATION-PLAN.md).
