# Vendored binaries

This file lists every binary committed to the repo that is not built from the source in this repo. Anyone updating a vendored binary must also update its entry here (filename, version, source URL, SHA-256, license, reason for vendoring).

CI may use this file as the source of truth for SHA verification — re-introducing or modifying a binary without updating this file should fail the build.

## iOS — `ios/`

| File | Version | Source | SHA-256 | License | Reason |
|---|---|---|---|---|---|
| `ios/libZSDK_API.a` | unknown (Mach-O fat: armv7/i386/x86_64/arm64) | Zebra Developer Portal — https://developer.zebra.com → Link-OS Multiplatform SDK iOS | `297e334a1415e11f064ea72d27350e1f85d83e95cc16c219098c93758c8be98d` | Zebra Link-OS SDK License (proprietary; redistributable per SDK EULA) | Zebra does not publish the iOS Link-OS SDK to CocoaPods or SPM (only via their developer portal, login-walled). Plugin's primary iOS dep — provides `ZebraPrinterConnection`, `MfiBtPrinterConnection`, `TcpPrinterConnection`, `ZebraPrinterFactory`, etc. |

### Removed in this PR

| File | Reason |
|---|---|
| `ios/Classes/AsyncSocket.{h,m}` (4313 LOC) | Pre-GCD CocoaAsyncSocket, deprecated upstream over a decade ago. Replaced by `CocoaAsyncSocket` pod (`~> 7.6`) which provides the modern `GCDAsyncSocket`. |
| `ios/Classes/POSWIFIManager.{h,m}` (1831 LOC) | Vendored 2016 third-party POS code from unknown origin (header reads `// XYWIFIManager.m / Created by apple on 16/4/5 / Copyright © 2016年 Admin`). No license, no source URL, no maintainer. Replaced with `ios/Classes/GenericPrinterClient.swift` — a 100-LOC Swift wrapper around `GCDAsyncSocket` with the same call surface (`posConnect/posDisConnect/posWriteCommand/connectOK`). |
| `ios/ExternalAccessory.framework/` | Header-only `.tbd` stub of a system framework. Unused — the system framework is linked via `s.frameworks` in the podspec instead. |
| `ios/QuartzCore.framework/` | Header-only `.tbd` stub of a system framework. Unused — same as above. |

## Behavior delta

The new `GenericPrinterClient` does not auto-reconnect on disconnect. The original `POSWIFIManager` had a connect timer that attempted re-establish; this client surfaces the disconnect to the caller and lets the integrator decide. If integrators relied on auto-reconnect, they need to add it at the Dart layer.

## Path forward

1. **iOS SDK upgrade.** Re-evaluate every Zebra release whether they've published an official CocoaPod / SPM. As of this PR, they have not.
2. **CI guard.** Add a CI step that fails if a binary is added to `ios/` without a corresponding entry here, or if a SHA-256 mismatches.
