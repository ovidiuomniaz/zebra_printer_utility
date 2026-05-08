# Security Audit & Remediation Plan

**Audited:** 2026-05-07
**Scope:** Full repo — Dart (`lib/`), Android (`android/`), iOS (`ios/`), bundled binaries.
**Verdict:** ⚠️ Not safe to ship to production as-is. Critical supply-chain issues plus runtime defects.

This document records the audit findings and the remediation plan. Each finding has a stable ID (H1, M1, L1, …) so PRs can reference them directly.

---

## Summary table

| ID | Severity | Area | One-line |
|---|---|---|---|
| H1 | Critical | Android deps | 14 vendored JARs incl. `jackson-databind 2.2.3` (multiple known RCE CVEs) and BouncyCastle 1.53 |
| H2 | Critical | iOS deps | Closed-source static archive `libZSDK_API.a` committed with no provenance/checksum |
| H3 | High | iOS deps | Vendored deprecated `AsyncSocket` (pre-GCD CocoaAsyncSocket) frozen at unknown revision |
| H4 | High | iOS deps | Vendored unlicensed third-party `POSWIFIManager` (1831 LOC, Chinese 2016 POS code) |
| M1 | Medium | Android runtime | `BluetoothDiscoverer` schedules perpetual `startDiscovery` after stop; receiver leak |
| M2 | Medium | Android runtime | `Printer.print()` leaks a thread on every call (`Looper.loop()` blocks before the unreachable `quit()`) |
| M3 | Medium | Network | No TLS / authentication on TCP printer connections (cleartext PII; ZPL-injection on LAN) |
| M4 | Medium | Android perms | `BLUETOOTH_SCAN` declared without `usesPermissionFlags="neverForLocation"`; FINE/COARSE always requested |
| M5 | Medium | Android perms | `checkPermission` checks `COARSE` but requests `FINE` — inconsistent |
| M6 | Medium | Android runtime | Static `discoveredPrinters` accumulates across instances; never cleared on detach |
| M7 | Medium | Android API | `getLocateValue` resolves Flutter-supplied resource keys via `getIdentifier()` |
| M8 | Medium | Build | AGP 7.3 + manifest `package=` blocks AGP 8.x consumers |
| L1 | Low | Build | Android Gradle Plugin 7.3.0 outdated |
| L2 | Low | Supply chain | No SHA-256 manifest for any vendored binary |
| L3 | Low | Tests | No real test coverage (default scaffold only) |
| L4 | Low | Metadata | `pubspec.yaml`, podspec still point at upstream maintainer; `homepage = http://example.com` |
| L5 | Low | Hygiene | `.idea/`, `.vscode/` committed |
| L6 | Low | Robustness | NPE-on-null assumptions in method-channel argument parsing |
| L7 | Low | Surface | `print(String data)` accepts arbitrary ZPL; integrators must sanitize |
| L8 | Low | Robustness | Base64 image decode has no size cap (memory-pressure DoS) |
| L9 | Low | License | Build excludes `META-INF/LICENSE`/`NOTICE` from APK (Apache-2.0 compliance risk) |
| L10 | Low | Quality | Default Bluetooth `DeviceFilter` is a no-op |

---

## Critical / High

### H1 — Vendored Java libraries with known RCE CVEs

`android/libs/` contains 14 JARs committed directly. Most are 8–13 years old, and several have well-documented remote-code-execution CVEs that are reachable via deserialization once on the classpath.

| JAR | Year | Known issues |
|---|---|---|
| `jackson-databind-2.2.3.jar` | 2013 | CVE-2017-7525, CVE-2017-15095, CVE-2018-7489, CVE-2018-14718, CVE-2019-12384, CVE-2019-14540, CVE-2019-16335, CVE-2019-17531, CVE-2020-9548… (deserialization gadget chains, RCE) |
| `jackson-core-2.2.3.jar` / `jackson-annotations-2.2.3.jar` | 2013 | Pair with vulnerable databind |
| `core-1.53.0.0.jar`, `prov-1.53.0.0.jar`, `pkix-1.53.0.0.jar` | 2015 | BouncyCastle 1.53 — CVE-2015-7940, CVE-2016-1000338..352, CVE-2018-1000180, CVE-2018-1000613, CVE-2018-5382 |
| `commons-validator-1.4.0.jar` | 2014 | CVE-2019-10086 family |
| `commons-lang3-3.4.jar` | 2015 | CVE-2017-1000487 |
| `httpcore-4.3.1.jar`, `httpmime-4.3.2.jar` | 2014 | Outdated httpclient family |
| `commons-net-3.1.jar` | 2012 | Multiple CVEs |
| `opencsv-2.2.jar` | ~2010 | Ancient |
| `snmp6_1z.jar` | ? | No version, unclear provenance |
| `ZSDK_ANDROID_API.jar` | ? | Zebra SDK with no version pin / SHA |

**Risk.** Even if the host application never directly imports `com.fasterxml.jackson.*`, the classes are on the APK's classpath and reachable from the bundled Zebra SDK and the Apache HTTP client family. ProGuard/R8 may strip *some* unused classes, but "unused-by-app" ≠ "removed-from-APK", and gadget chains exploit classes that look unused.

**Remediation.**
- Replace `implementation fileTree(dir: 'libs', include: ['*.jar'])` with explicit Maven coordinates.
- Pull Zebra Link-OS SDK from Zebra's official Maven artifact — modern Link-OS does not require Jackson 2.2.3 / BouncyCastle 1.53 / opencsv 2.2 as separate vendored deps.
- If transitive deps still drag in any of the above, force-pin to current versions (`jackson-databind` ≥ `2.16`, BouncyCastle ≥ `1.78`, etc.).
- Re-run `./gradlew app:dependencies` and verify nothing is below current GA.

**Acceptance.** No `*.jar` files in `android/libs/`. CI runs OWASP Dependency-Check (or equivalent) and fails on any High/Critical CVE.

---

### H2 — Closed-source iOS static archive committed to the repo

`ios/libZSDK_API.a` is a Mach-O fat archive (armv7 / i386 / x86_64 / arm64) checked in with **no version metadata, no provenance, no checksum**. Integrators have no way to verify it matches Zebra's official release; any future fork can swap it silently.

**Remediation.**
- Pull Zebra's iOS SDK via CocoaPods or Swift Package Manager.
- If vendoring is unavoidable: document the exact Zebra SDK version, publish a SHA-256, and add a CI check that the file matches.
- Drop the i386 slice — only x86_64 simulators have been supported since Xcode 10 (iOS 12).

**Acceptance.** `libZSDK_API.a` removed; podspec points at official package; or, if vendored, SHA-256 recorded in `docs/VENDORED.md` and verified by a CI step.

---

### H3 — Vendored deprecated `AsyncSocket`

`ios/Classes/AsyncSocket.{h,m}` (4313 LOC) is the **pre-GCD** version of CocoaAsyncSocket from cocoaasyncsocket on Google Code. It has been deprecated for over a decade in favor of `GCDAsyncSocket` and is frozen at whatever revision was committed — every fix landed upstream since is missing.

**Remediation.** Replace with `GCDAsyncSocket` (or `CocoaAsyncSocket`) pulled via CocoaPods/SPM. The API surface used by `POSWIFIManager` is small (delegate-based connect/disconnect/write); migrating is straightforward.

**Acceptance.** No `AsyncSocket.{h,m}` in `ios/Classes/`. Generic-printer flow continues to work.

---

### H4 — Vendored `POSWIFIManager` of unknown provenance

`ios/Classes/POSWIFIManager.{h,m}` (1831 LOC) was originally `XYWIFIManager.m`, header reads:
```
//  Created by apple on 16/4/5.
//  Copyright © 2016年 Admin. All rights reserved.
```

No license, no source URL, no maintainer — this is third-party POS-printer code of unknown origin imported in 2016. Mixed English/Chinese comments. Used to drive the generic (port 9100) printer flow.

**Risk.** Unknown license (potential infringement on redistribution); unknown vulnerability history; cannot be patched. This is reachable from every consumer of the iOS plugin.

**Remediation.** Replace with a thin Swift/Obj-C class on top of `GCDAsyncSocket` (~150 LOC). The needed surface: connect, disconnect, write, status callback.

**Acceptance.** `POSWIFIManager.{h,m}` removed; replacement class with clear license header in place; iOS generic-printer integration test passes.

---

## Medium

### M1 — Perpetual Bluetooth scan loop with receiver leak

[`android/src/main/java/com/rubdev/zebrautil/BluetoothDiscoverer.java`](../android/src/main/java/com/rubdev/zebrautil/BluetoothDiscoverer.java):

- Line 127: `new Handler().postDelayed(() -> BluetoothAdapter.getDefaultAdapter().startDiscovery(), 10_000);` — every time discovery finishes the receiver schedules another global `startDiscovery` 10 s later. `stopBluetoothDiscovery()` nulls the static singleton but the queued runnable still fires; result is **discovery restarts indefinitely after stop**.
- `new Handler()` with no `Looper` argument is a footgun — crashes if the receiver is invoked off the main thread.
- Lines 83-84 register `btReceiver` twice (once for `ACTION_FOUND`, once for `ACTION_DISCOVERY_FINISHED`); `unregisterReceiver` is called once. If `stopBluetoothDiscovery` is never invoked, both receivers leak.

**Remediation.**
- Guard the `postDelayed` lambda with a "still scanning?" check, or cancel via `Handler.removeCallbacksAndMessages(null)` in `stopBluetoothDiscovery`.
- Use a single receiver with both intent filters (or two distinct receivers stored separately).
- Call `unregisterReceiver` defensively in a try/catch.
- Bind the `Handler` to `Looper.getMainLooper()` explicitly.

**Acceptance.** `stopBluetoothDiscovery` actually stops discovery (verified by logcat); `adb shell dumpsys bluetooth_manager` shows no lingering scan after detach.

---

### M2 — Thread leak on every `print()` call

[`Printer.java:238-244`](../android/src/main/java/com/rubdev/zebrautil/Printer.java):
```java
new Thread(() -> {
    Looper.prepare();
    doConnectionTest(data);
    Looper.loop();          // blocks forever
    Objects.requireNonNull(Looper.myLooper()).quit();   // unreachable
}).start();
```
`Looper.loop()` only returns once the looper is quit, but `quit()` is the *next* statement. Every print call leaks one thread + one Looper.

**Remediation.** `doConnectionTest` doesn't actually need a Looper — it does a blocking write on the connection. Drop the Looper:
```java
new Thread(() -> doConnectionTest(data)).start();
```
Or use a single-threaded `ExecutorService` to serialize prints.

**Acceptance.** No thread growth in `adb shell ps -T <pid>` after N prints; existing print flow still works.

---

### M3 — No TLS / authentication on TCP printer connections

Both Android (`Socketmanager`, `TcpConnection`) and iOS use raw TCP to ports `6101` (Zebra) and `9100` (generic). Print payloads — potentially containing PII (names, addresses, prescriptions, receipts) — cross the LAN in cleartext.

**Risk.** A LAN attacker can:
- Sniff every label/receipt printed.
- ARP-spoof the printer's IP and exfiltrate or alter content.
- Inject arbitrary ZPL into the real printer (alter calibration, network config, persistent settings).

This is a limitation of network-print protocols, not a defect we can fix in the plugin alone — but the README must disclose it. There's also **no validation** of the user-supplied IP; a misuse of the plugin can weaponize it as a port-scanner.

**Remediation.**
- Document the cleartext nature in `README.md` and `SECURITY.md`.
- Optionally: support Zebra's TLS-capable port (typically `9143` for HTTPS-style configurations) where the printer firmware allows.
- Add basic IP/hostname validation (RFC 1123 hostnames; private vs. public IP guard if appropriate for the use case).

**Acceptance.** `SECURITY.md` exists and lists the threat model; integrators are warned in the README.

---

### M4 — Over-broad runtime permissions on Android

[`android/src/main/AndroidManifest.xml`](../android/src/main/AndroidManifest.xml) requests:
- `ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION` unconditionally.
- `BLUETOOTH_SCAN` *without* `android:usesPermissionFlags="neverForLocation"`.

On Android 12+ this means Google Play assumes the app uses BT scan results to derive user location — Play Store review flag and an unnecessary privacy regression. Pre-12, location should be capped via `android:maxSdkVersion="30"`.

**Remediation.**
```xml
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation"
    tools:targetApi="s" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.INTERNET" />
```

**Acceptance.** `aapt dump permissions` shows only API-appropriate permissions on each Android version.

---

### M5 — `checkPermission` checks `COARSE` but requests `FINE`

[`Printer.java:148-179`](../android/src/main/java/com/rubdev/zebrautil/Printer.java) checks `ACCESS_COARSE_LOCATION`, then calls `requestPermissions(["ACCESS_FINE_LOCATION"])`. Inconsistent — if the user grants COARSE only, the pre-flight check passes but BT scan may silently return partial results on older Android versions.

**Remediation.** With M4 applied, `BLUETOOTH_SCAN` (with `neverForLocation`) replaces the location requirement on Android 12+. For Android 11 and earlier, request `ACCESS_FINE_LOCATION` and check the same.

**Acceptance.** Permission check and permission request match; BT scan succeeds on every supported Android level.

---

### M6 — Static state across plugin instances

[`Printer.java:58-59`](../android/src/main/java/com/rubdev/zebrautil/Printer.java):
```java
private static ArrayList<DiscoveredPrinter> discoveredPrinters = new ArrayList<>();
private static ArrayList<DiscoveredPrinter> sendedDiscoveredPrinters = new ArrayList<>();
```
Static lists accumulate forever; never cleared on engine detach. State leaks across multiple plugin instances and across hot-restart cycles.

**Remediation.** Move to instance fields, or clear them in `onDetachedFromEngine` / `disconnect`.

**Acceptance.** No reference to `discoveredPrinters` outliving its plugin instance.

---

### M7 — `getLocateValue` resource enumeration

[`Printer.java:602-605`](../android/src/main/java/com/rubdev/zebrautil/Printer.java):
```java
String resourceKey = call.argument("ResourceKey");
@SuppressLint("DiscouragedApi") int resId = context.getResources().getIdentifier(resourceKey, "string", context.getPackageName());
result.success(resId == 0 ? "" : context.getString(resId));
```
Lets the Dart side enumerate any `R.string.*` in the plugin package using a user-supplied key. Scoped to the plugin's own resources, so impact is low — but the right design is a hardcoded `Map<String,String>`. The `@SuppressLint("DiscouragedApi")` is suppressing exactly this lint.

**Remediation.** Replace with an explicit allow-list:
```java
private static final Map<String, Integer> ALLOWED = Map.of(
    "connected", R.string.connected,
    "disconnect", R.string.disconnect,
    "done", R.string.done /* … */
);
```
Or, simpler: stop sending strings through the channel — return enum tokens and let Dart format them.

**Acceptance.** `getResources().getIdentifier()` no longer used.

---

### M8 — AGP 7.3 + manifest `package=` blocks AGP 8.x consumers

`AndroidManifest.xml` declares `package="com.rubdev.zebrautil"` while `build.gradle` also sets `namespace`. AGP 8.x rejects this combination — meaning any host app that has upgraded to AGP 8 cannot use this plugin without patching it.

**Remediation.**
- Remove the `package=` attribute from `AndroidManifest.xml`.
- Bump AGP to a current 8.x release (e.g., `8.5.x`) in `android/build.gradle`.
- Bump `compileSdk` to current target (35) and Java toolchain to 17.
- Verify `compileSdk = 34` is still the floor consumers can rely on.

**Acceptance.** Plugin builds clean against AGP 8.5+, AGP 7.x, and Flutter 3.16+.

---

## Low

### L1 — AGP 7.3.0 outdated
Bundle a current AGP version (≥ 8.5) — see M8.

### L2 — No SHA-256 manifest for vendored binaries
While any binary remains vendored (during the H1/H2 transition), publish a `docs/VENDORED.md` listing each binary with its expected SHA-256 and source URL, and add a CI step that verifies the hashes.

### L3 — No real tests
`test/zebrautility_test.dart` is the default Flutter scaffold. Add at minimum:
- Unit tests for `zebraStatusFromStrings` (English + Spanish + color fallback).
- A `MethodChannel` mock test for `connectToPrinter` happy/error paths.

### L4 — Stale fork metadata
- `pubspec.yaml` `repository:` points at upstream `anthonyR012/zebra_printer_utility`.
- `zebrautil.podspec` `homepage = 'http://example.com'`, `s.platform = :ios, '8.0'` (iOS 8 is from 2014; current minimum should be iOS 13+), `s.author = 'Anthony Rubio' / rubionn27@gmail.com`.
- `pubspec.yaml` `description:` is below the 60-char pub.dev threshold.

Update all to match the current fork.

### L5 — `.idea/`, `.vscode/` committed
Move to `.gitignore`. No sensitive content observed, but they leak the maintainer's IDE config and add diff noise.

### L6 — NPE-prone method-channel parsing
Calls like `print(call.argument("Data").toString())` NPE when "Data" is missing. Wrap in a small helper:
```java
private static String requireString(MethodCall call, String key, MethodChannel.Result result) {
    Object v = call.argument(key);
    if (v == null) { result.error("INVALID_ARGS", "Missing " + key, null); return null; }
    return v.toString();
}
```

### L7 — `print(String data)` accepts arbitrary ZPL
By design, but ZPL can permanently reconfigure the printer (calibration, network config, persistent settings). Document in the README that integrators must validate / sanitize ZPL coming from untrusted input.

### L8 — Base64 image decode without size cap
[`Printer.java:545-553`](../android/src/main/java/com/rubdev/zebrautil/Printer.java) — `BitmapFactory.decodeByteArray` on user-supplied Base64 with no size limit. Memory-pressure DoS if a huge image is passed. Cap the byte length (e.g., 10 MB) and reject earlier.

### L9 — Build excludes `META-INF/LICENSE`/`NOTICE`
[`android/build.gradle:35-43`](../android/build.gradle) excludes Apache-2.0 license/notice files. While necessary to avoid duplicate-file errors during APK packaging, this risks Apache-2.0 compliance violations for downstream APKs. Once H1 lands and the JAR fleet is gone, this hack should no longer be needed.

### L10 — No-op default Bluetooth filter
[`BluetoothDiscoverer.java:56`](../android/src/main/java/com/rubdev/zebrautil/BluetoothDiscoverer.java): `DeviceFilter filter = value -> true;` is misleading — the real filter is `isPrinterClass`. Either remove the parameter or implement a real filter.

---

## What's *not* an issue (verified)

- ✅ No hardcoded secrets/API keys/tokens in source.
- ✅ No `Runtime.exec`, `ProcessBuilder`, `dlopen`, `System.load`, or `eval`-style execution.
- ✅ No outbound HTTP — the plugin only opens local TCP/Bluetooth sockets.
- ✅ The bundled `ExternalAccessory.framework` and `QuartzCore.framework` directories contain only `.tbd` text-stub linker files + headers + module maps. Not binaries — safe (just unusual to vendor).
- ✅ No reflection-based dynamic class loading.
- ✅ Dart code does not execute received native data as code; the Flutter ↔ native channel is type-safe Map-based RPC.

---

## Suggested PR sequence

| Order | PR | Size | Findings closed |
|---|---|---|---|
| 1 | Replace vendored JARs with Maven coordinates | Large | H1, L9 |
| 2 | Replace iOS vendored libraries with SPM/CocoaPods | Large | H2, H3, H4 |
| 3 | Fix BT scan loop, receiver leak, thread leak | Small | M1, M2, M6 |
| 4 | Fix Android permissions and AGP/manifest namespace | Small | M4, M5, M8, L1 |
| 5 | Replace `getLocateValue` with allow-list; null-safe args; image size cap | Small | M7, L6, L8 |
| 6 | Add `SECURITY.md`, document ZPL/cleartext caveats, fix metadata | Small | M3, L4, L5, L7 |
| 7 | Add tests, CI, dependency-check | Medium | L2, L3 |

Each PR should reference its finding IDs in the commit body.

---

## CI suggestions

- Add a GitHub Actions workflow that runs OWASP Dependency-Check on Android dependencies (or `gradle dependencyCheckAnalyze`).
- Add `flutter analyze` and `flutter test` jobs.
- Add a SHA-256 verification step for any remaining vendored binary.
- Block PRs that re-introduce files in `android/libs/`.
