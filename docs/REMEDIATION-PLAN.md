# Remediation Plan

Step-by-step plans to close every finding in [`SECURITY-AUDIT.md`](./SECURITY-AUDIT.md). Each section below is a self-contained PR — branch name, findings closed, files touched, concrete steps, acceptance criteria, test plan, risk and rollback.

PR order matters: the supply-chain PRs (1, 2) make several lower-priority findings disappear, so don't start with M1 or you'll re-do the work.

---

## PR 1 — Replace vendored Java libraries with Maven coordinates

**Branch:** `fix/h1-replace-vendored-jars`
**Closes:** H1, L9
**Size:** Large (build system + DI surface)
**Risk:** High — every consumer recompiles against new transitive deps.

### Goal
Drop every JAR in `android/libs/` and resolve all Java deps through Gradle/Maven so they're versioned, auditable, and patchable. Treat this as the gating PR for everything else — until it lands, every other Android-side fix is built on a poisoned dependency tree.

### Steps

1. **Identify the modern Zebra SDK Maven coordinate.**
   - Check Zebra's Developer Portal (https://developer.zebra.com → Link-OS Multiplatform SDK).
   - As of writing, Zebra distributes the Android SDK as a downloadable archive *and* publishes recent versions to their own repository. Confirm whether the current version is on Maven Central, Google Maven, or only on Zebra's repo — and update `android/build.gradle` `repositories { … }` accordingly.
   - **Do not guess the coordinate.** Record the exact `groupId:artifactId:version` you settle on in `docs/VENDORED.md` (created in PR 7).

2. **Audit which classes the plugin actually uses.** Today the plugin's own Java code only references:
   - `com.zebra.sdk.comm.{BluetoothConnection, Connection, ConnectionException, TcpConnection}`
   - `com.zebra.sdk.printer.{ZebraPrinter, ZebraPrinterFactory, ZebraPrinterLanguageUnknownException, PrinterStatus}`
   - `com.zebra.sdk.printer.discovery.{DiscoveredPrinter, DiscoveredPrinterBluetooth, DeviceFilter, NetworkDiscoverer}`
   
   Everything else (Jackson, BouncyCastle, opencsv, Apache HTTP, snmp6_1z) is a *transitive* dep of older Zebra SDK builds. The modern Link-OS SDK has dropped most of these.

3. **Update `android/build.gradle`.**
   - Remove `implementation fileTree(dir: 'libs', include: ['*.jar'])`.
   - Add the explicit Zebra dependency (e.g. `implementation "com.zebra.android:zsdk-api:<version>"` — confirm exact form per step 1).
   - Resolve any transitive dep that is still flagged by Dependency-Check; force-pin to current GA via `configurations.all { resolutionStrategy { force "..." } }`.
   - Remove the `packagingOptions.resources.excludes` block for `META-INF/LICENSE`/`NOTICE` — once we're not bundling 14 conflicting JARs, the duplicate-file errors go away and Apache-2.0 NOTICE files can be preserved (closes L9).

4. **Delete `android/libs/`.**
   - `git rm -r android/libs/`.

5. **Run `./gradlew app:dependencies` from the example app and verify:**
   - No `com.fasterxml.jackson.core:jackson-databind:2.2.3` in the tree.
   - No `org.bouncycastle:* :1.53.0.0`.
   - All resolved versions are at or above their current GA on Maven Central.

6. **Run a CVE scan.** `./gradlew dependencyCheckAnalyze` (after wiring OWASP plugin in PR 7). Zero High/Critical results required.

### Files touched
- `android/build.gradle`
- `android/libs/` (deleted)

### Acceptance criteria
- `android/libs/` does not exist.
- `./gradlew :example:assembleDebug` passes.
- The example app discovers, connects to, and prints to a real Zebra ZQ630 (or equivalent) over Bluetooth and Wi-Fi.
- `dependencyCheckAnalyze` reports 0 High/Critical findings.

### Test plan
- Manual smoke test on Android: discover, connect, print, calibrate, set media type, set darkness, disconnect — all four flows on Bluetooth and Wi-Fi.
- Verify `BLUETOOTH_PRINTER_CLASS = 1664` filtering still works.
- Run `flutter test` (only checks Dart side, but should still pass).

### Risk and rollback
- **Risk:** the new Zebra SDK version may have an API delta (e.g., method signature change, package rename). If so, fix calls in `Printer.java` accordingly — the Java surface area is small (~650 LOC).
- **Rollback:** `git revert` the PR; the old `libs/` directory is recoverable from Git history.

---

## PR 2 — Migrate iOS vendored libraries to package-managed equivalents

**Branch:** `fix/h2-h3-h4-migrate-ios-vendored`
**Closes:** H2, H3, H4
**Size:** Large (iOS native rewrite)
**Risk:** Medium-High — replaces ~6,000 LOC of vendored Obj-C with a thin Swift wrapper.

### Goal
Stop shipping `libZSDK_API.a`, `AsyncSocket.{h,m}`, and `POSWIFIManager.{h,m}` from the repo. Pull them via CocoaPods or SPM, or rewrite where there's no maintained equivalent.

### Steps

#### Part A — Zebra iOS SDK (closes H2)

1. **Confirm Zebra's iOS distribution channel.** Zebra publishes an iOS Link-OS SDK; check whether they offer:
   - A CocoaPod — preferred.
   - A Swift Package — preferred.
   - A signed XCFramework download — acceptable as a pinned vendored binary.
   - Only an unsigned `.a` — fall back to vendoring with a documented SHA-256.

2. **Update `zebrautil.podspec`:**
   - Remove `s.preserve_paths = 'libZSDK_API.a', …`.
   - Remove `s.vendored_libraries = 'libZSDK_API'`.
   - Remove `s.vendored_frameworks = 'ExternalAccessory.framework', 'QuartzCore.framework'` — these are header-only stubs and not needed (iOS SDK provides them).
   - Add `s.dependency 'ZebraLinkOS-iOS', '<version>'` (or the actual pod name).
   - Drop `s.platform = :ios, '8.0'` → `s.platform = :ios, '13.0'` (App Store minimum).
   - Update `s.homepage` and `s.author` (closes part of L4).

3. **Delete `ios/libZSDK_API.a`.**
4. **Delete `ios/ExternalAccessory.framework/` and `ios/QuartzCore.framework/`** — these are unused header-stub copies; the system frameworks are linked via `s.frameworks` or `OTHER_LDFLAGS`.
5. **In `Printer.swift`,** verify `import ZebraSDK` (or whatever the modern module is named) replaces the implicit linkage.

#### Part B — AsyncSocket → GCDAsyncSocket (closes H3)

The deprecated `AsyncSocket.{h,m}` is used only by `POSWIFIManager`. Replacing both at once (Part C) makes Part B disappear — but if Part C is too risky for one PR, intermediate-step:

1. Add `s.dependency 'CocoaAsyncSocket', '~> 7.6'` to the podspec.
2. Replace `AsyncSocket *_sendSocket` with `GCDAsyncSocket *_sendSocket` in `POSWIFIManager.{h,m}`.
3. Update delegate callbacks to `GCDAsyncSocketDelegate`:
   - `onSocket:didConnectToHost:port:` → `socket:didConnectToHost:port:`
   - `onSocket:didReadData:withTag:` → `socket:didReadData:withTag:`
   - `onSocket:didWriteDataWithTag:` → `socket:didWriteDataWithTag:`
   - `onSocketDidDisconnect:` → `socketDidDisconnect:withError:`
4. Delete `ios/Classes/AsyncSocket.{h,m}`.

#### Part C — Replace POSWIFIManager (closes H4)

The cleanest fix is to throw `POSWIFIManager.{h,m}` away and write a small Swift class that does just what the plugin needs:

```swift
final class GenericPrinterClient: NSObject, GCDAsyncSocketDelegate {
    private var socket: GCDAsyncSocket?
    private(set) var isConnected = false

    func connect(host: String, port: UInt16, completion: @escaping (Bool) -> Void) { /* … */ }
    func disconnect() { /* … */ }
    func write(_ data: Data, completion: @escaping (Bool) -> Void) { /* … */ }
}
```

Estimate: 100–150 LOC, replacing 1831 LOC. Wire it into `Printer.swift`'s `connectToGenericPrinter` flow.

1. Implement `GenericPrinterClient.swift`.
2. Replace every `POSWIFIManager` reference in `Printer.swift` with `GenericPrinterClient`.
3. Delete `ios/Classes/POSWIFIManager.{h,m}`.

### Files touched
- `zebrautil.podspec`
- `ios/libZSDK_API.a` (deleted)
- `ios/ExternalAccessory.framework/` (deleted)
- `ios/QuartzCore.framework/` (deleted)
- `ios/Classes/AsyncSocket.{h,m}` (deleted)
- `ios/Classes/POSWIFIManager.{h,m}` (deleted)
- `ios/Classes/GenericPrinterClient.swift` (new)
- `ios/Classes/Printer.swift` (updated)

### Acceptance criteria
- No `.a`/`.framework`/`.m`/`.h` blobs of unknown provenance left in `ios/`.
- `pod lib lint zebrautil.podspec` passes.
- The example iOS app discovers, connects, and prints to a real Zebra MFi Bluetooth printer.
- The example iOS app connects and prints to a generic port-9100 printer (test with a Wi-Fi-attached label printer).

### Test plan
- Smoke test on a real iPhone: dummy `0.0.0.0` connect (local network permission prompt), MFi accessory enumeration, ZPL print.
- Unit test the new `GenericPrinterClient` (mock `GCDAsyncSocket`).

### Risk and rollback
- **Risk:** Apple's MFi requirements may change with the new Zebra SDK version — verify `Supported external accessory protocols` plist entry still resolves.
- **Rollback:** `git revert`; vendored files are in history.

---

## PR 3 — Fix BT scan loop, receiver leak, thread leak, static state

**Branch:** `fix/m1-m2-m6-android-runtime`
**Closes:** M1, M2, M6
**Size:** Small
**Risk:** Low

### Goal
Stop leaking threads and Bluetooth scans. None of these are dependencies of any other PR — pure code fixes.

### Steps

#### M2 — Looper thread leak in `Printer.print()`

Edit [`android/src/main/java/com/rubdev/zebrautil/Printer.java:237-244`](../android/src/main/java/com/rubdev/zebrautil/Printer.java):

```java
// Before
public void print(final String data) {
    new Thread(() -> {
        Looper.prepare();
        doConnectionTest(data);
        Looper.loop();
        Objects.requireNonNull(Looper.myLooper()).quit();
    }).start();
}

// After
private final ExecutorService printExecutor =
    Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "ZebraPrint");
        t.setDaemon(true);
        return t;
    });

public void print(final String data) {
    printExecutor.submit(() -> doConnectionTest(data));
}
```

Add an `onDetachedFromEngine`-equivalent path that calls `printExecutor.shutdown()` to free the thread.

#### M1 — Perpetual BT scan loop with receiver leak

Edit [`android/src/main/java/com/rubdev/zebrautil/BluetoothDiscoverer.java`](../android/src/main/java/com/rubdev/zebrautil/BluetoothDiscoverer.java):

1. Replace `new Handler()` with `new Handler(Looper.getMainLooper())` and store it on the `BtReceiver` instance.
2. In `BtReceiver.onReceive`, only re-schedule if the discoverer instance is still active (i.e., `BluetoothDiscoverer.bluetoothDiscoverer != null`).
3. In `stopBluetoothDiscovery`, call `handler.removeCallbacksAndMessages(null)` before nulling the singleton.
4. In `unregisterTopLevelReceivers`, wrap each `unregisterReceiver` in try/catch — calling unregister on an already-unregistered receiver throws `IllegalArgumentException`.
5. Cancel the in-flight `BluetoothAdapter.cancelDiscovery()` in `stopBluetoothDiscovery`.

#### M6 — Static state across plugin instances

Edit [`android/src/main/java/com/rubdev/zebrautil/Printer.java:58-59`](../android/src/main/java/com/rubdev/zebrautil/Printer.java):

```java
// Before
private static ArrayList<DiscoveredPrinter> discoveredPrinters = new ArrayList<>();
private static ArrayList<DiscoveredPrinter> sendedDiscoveredPrinters = new ArrayList<>();

// After
private final List<DiscoveredPrinter> discoveredPrinters = new ArrayList<>();
private final List<DiscoveredPrinter> sentDiscoveredPrinters = new ArrayList<>();
```

Update every static method that touched these to be instance methods — `startScanning`, `addNewDiscoverPrinter`, `removeDiscoverPrinter`, `addPrinterToDiscoveryPrinterList`, `removePrinterToDiscoveryPrinterList`. The `Context` and `MethodChannel` parameters they currently pass around become instance fields.

### Files touched
- `android/src/main/java/com/rubdev/zebrautil/Printer.java`
- `android/src/main/java/com/rubdev/zebrautil/BluetoothDiscoverer.java`
- `android/src/main/java/com/rubdev/zebrautil/ZebraUtilPlugin.java` (add detach hook to shut down executor)

### Acceptance criteria
- 1000 calls to `print()` create no more than one thread (`adb shell ps -T <pid> | grep ZebraPrint`).
- After `stopScanning()`, `adb shell dumpsys bluetooth_manager` shows no active discovery.
- Two sequential plugin instances do not share `discoveredPrinters` state.

### Test plan
- Bloc/widget test that triggers 1000 prints and inspects thread count on a real device.
- Manual: hot-restart the app while scanning; confirm BT discovery actually stops.
- New unit test in `test/printer_test.dart` for the static-state regression (instantiate two `Printer`s, scan one, verify the other's list is empty).

### Risk and rollback
- **Risk:** very low — code changes are localized and behavior-preserving.
- **Rollback:** `git revert`.

---

## PR 4 — Fix Android permissions and AGP/manifest namespace

**Branch:** `fix/m4-m5-m8-android-build`
**Closes:** M4, M5, M8, L1
**Size:** Small
**Risk:** Medium — touches manifest and AGP version.

### Goal
Make the plugin AGP-8-compatible and Android-12-permissions-correct in one go.

### Steps

#### M8, L1 — AGP & namespace

1. Edit `android/build.gradle`:
   - `classpath("com.android.tools.build:gradle:7.3.0")` → current 8.x release (e.g., `8.5.0`).
   - `compileSdk = 34` → `35` (or current target).
   - Bump Java toolchain to 17:
     ```gradle
     compileOptions {
         sourceCompatibility = JavaVersion.VERSION_17
         targetCompatibility = JavaVersion.VERSION_17
     }
     ```
2. Edit `android/src/main/AndroidManifest.xml`:
   - Remove `package="com.rubdev.zebrautil"` from the `<manifest>` root. Namespace is already set in `build.gradle`.
   - Add `xmlns:tools="http://schemas.android.com/tools"` to support `tools:targetApi`.

#### M4 — Permissions

Replace the manifest body with:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
          xmlns:tools="http://schemas.android.com/tools">

    <uses-permission android:name="android.permission.INTERNET" />

    <!-- Pre-Android 12 Bluetooth -->
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" android:maxSdkVersion="30" />

    <!-- Android 12+ Bluetooth -->
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN"
                     android:usesPermissionFlags="neverForLocation"
                     tools:targetApi="s" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"
                     tools:targetApi="s" />
</manifest>
```

#### M5 — `checkPermission` consistency

Edit [`Printer.java:148-179`](../android/src/main/java/com/rubdev/zebrautil/Printer.java) so the check, the request, and the actual scan all reference the same permission for the running API level:

```java
private void checkPermission(Context context, MethodChannel.Result result) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        // Android 12+: only BLUETOOTH_SCAN is needed (with neverForLocation flag).
        ensurePermission(context, result, Manifest.permission.BLUETOOTH_SCAN);
    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        // Android 6-11: ACCESS_FINE_LOCATION required for BT discovery.
        ensurePermission(context, result, Manifest.permission.ACCESS_FINE_LOCATION);
    } else {
        result.success(true);
    }
}
```

Extract `ensurePermission(context, result, permission)` as a small helper that owns the request listener, so the same path covers both branches.

### Files touched
- `android/build.gradle`
- `android/src/main/AndroidManifest.xml`
- `android/src/main/java/com/rubdev/zebrautil/Printer.java`
- `example/android/build.gradle` (bump AGP) and `example/android/gradle/wrapper/gradle-wrapper.properties` (bump Gradle)

### Acceptance criteria
- `flutter build apk --debug` succeeds against AGP 8.5+ and Flutter 3.16+.
- On a fresh install:
  - Android 11 device requests `ACCESS_FINE_LOCATION` only.
  - Android 12+ device requests `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT`, never location.
- BT discovery succeeds in both cases.
- Google Play's pre-launch report shows no `BLUETOOTH_SCAN`-without-`neverForLocation` warning.

### Test plan
- Test on real Android 11 + Android 14 devices.
- Run `aapt dump permissions` against the built APK and check the permission set per API.
- Run `./gradlew :example:lint` for AGP-8 deprecation warnings.

### Risk and rollback
- **Risk:** AGP 8 may surface lint errors elsewhere in the example app — fix those en-route.
- **Rollback:** `git revert`. Consumers stuck on AGP 7 can pin to the previous tag.

---

## PR 5 — Replace `getLocateValue`, null-safe args, image size cap

**Branch:** `fix/m7-l6-l8-method-channel-hardening`
**Closes:** M7, L6, L8
**Size:** Small
**Risk:** Low

### Goal
Tighten the method-channel surface: no resource enumeration, no NPE-on-null, no unbounded image decode.

### Steps

#### M7 — Replace `getLocateValue` with an allow-list

Edit [`Printer.java:602-605`](../android/src/main/java/com/rubdev/zebrautil/Printer.java):

```java
private static final Map<String, Integer> LOCALE_KEYS = Map.of(
    "connected",   R.string.connected,
    "disconnect",  R.string.disconnect,
    "connecting",  R.string.connecting,
    "disconnecting", R.string.disconnecting,
    "sending_data", R.string.sending_data,
    "done",        R.string.done
);

case "getLocateValue": {
    String key = call.argument("ResourceKey");
    Integer resId = LOCALE_KEYS.get(key);
    result.success(resId == null ? "" : context.getString(resId));
    break;
}
```

(Confirm the actual list of keys used by checking what Dart sends — `lib/zebra_printer.dart` only calls it with `"connected"` today.)

Drop the `@SuppressLint("DiscouragedApi")` since `getIdentifier()` is gone.

#### L6 — Null-safe argument parsing

Add a helper at the top of `Printer.java`:

```java
private static String requireString(MethodCall call, String key, MethodChannel.Result result) {
    Object v = call.argument(key);
    if (v == null) {
        result.error("INVALID_ARGS", "Missing argument: " + key, null);
        return null;
    }
    return v.toString();
}
```

Replace every `call.argument("X").toString()` site with `requireString(call, "X", result)` and bail if the result is `null`. Sites: `print` (`Data`), `connectToPrinter` (`Address`), `connectToGenericPrinter` (`Address`), `convertBase64ImageToZPLString` (`Data`, `rotation`), `setSettings` (`SettingCommand`), `setMediaType` (`MediaType`).

#### L8 — Image size cap

In `convertBase64ImageToZPLString`, add a guard:

```java
private static final int MAX_IMAGE_BYTES = 10 * 1024 * 1024; // 10 MB

private void convertBase64ImageToZPLString(String data, int rotation, MethodChannel.Result result) {
    try {
        byte[] decoded = Base64.decode(data, Base64.DEFAULT);
        if (decoded.length > MAX_IMAGE_BYTES) {
            result.error("IMAGE_TOO_LARGE", "Image exceeds " + MAX_IMAGE_BYTES + " bytes", null);
            return;
        }
        // … existing decode + ZPL conversion
    } catch (Exception e) {
        result.error("-1", "Error", null);
    }
}
```

Optionally, also check `BitmapFactory.Options.inJustDecodeBounds = true` first to detect oversized bitmaps before allocating.

### Files touched
- `android/src/main/java/com/rubdev/zebrautil/Printer.java`

### Acceptance criteria
- `getResources().getIdentifier()` no longer appears anywhere in the plugin.
- Sending a method call with a missing required argument returns a structured `MethodChannel` error instead of crashing.
- Sending a >10 MB Base64 payload returns `IMAGE_TOO_LARGE` instead of OOM-ing.

### Test plan
- Unit test for `requireString` and the image cap.
- Manual: send a malformed Flutter call (missing `Data`) and assert the error is surfaced.

### Risk and rollback
- **Risk:** any caller that depended on the previous "swallow null and crash" behavior gets explicit errors now. That's the point.
- **Rollback:** `git revert`.

---

## PR 6 — `SECURITY.md`, README disclosures, fix metadata

**Branch:** `chore/m3-l4-l5-l7-docs`
**Closes:** M3 (documented), L4, L5, L7 (documented)
**Size:** Small
**Risk:** None

### Goal
Document threat-model boundaries that the plugin can't fix in code, and tidy fork metadata.

### Steps

1. **Add `SECURITY.md`** at the repo root:
   - Threat model: this is a LAN/Bluetooth printer plugin. Print payloads cross the network in cleartext; ZPL is unauthenticated; print jobs can change persistent printer state.
   - Disclosure process: how to report a vulnerability, expected response time, scope.
   - Note that the plugin does not implement TLS for printer connections; integrators using printers on shared networks should use a VLAN or Wi-Fi isolation.
   - Reference [`docs/SECURITY-AUDIT.md`](./SECURITY-AUDIT.md) and this remediation plan.

2. **Update `README.md`:**
   - Add a "Security considerations" section linking to `SECURITY.md`.
   - Note that `print(String data)` accepts arbitrary ZPL and integrators must validate untrusted input (closes L7).

3. **Update `pubspec.yaml`:**
   - `description:` ≥ 60 chars (closes part of L4).
   - `repository:` → this fork's URL.
   - Add `homepage:` and `issue_tracker:`.

4. **Update `zebrautil.podspec`:**
   - `s.homepage` → real URL.
   - `s.author` → fork maintainer.
   - `s.platform = :ios, '13.0'` (closes part of L4; covered by PR 2 if shipped first).

5. **Add `.gitignore` entries** and `git rm -rf --cached .idea .vscode` to stop tracking IDE config (closes L5).

6. **Bump version** in `pubspec.yaml` to reflect the breaking metadata changes.

### Files touched
- `SECURITY.md` (new)
- `README.md`
- `pubspec.yaml`
- `zebrautil.podspec`
- `.gitignore`
- `.idea/`, `.vscode/` (deleted from index)

### Acceptance criteria
- `SECURITY.md` exists and renders on GitHub.
- `pub publish --dry-run` reports zero metadata warnings.
- `git ls-files .idea .vscode` returns nothing.

### Test plan
- Visual review on GitHub.
- Run `pub publish --dry-run` and `pod lib lint`.

### Risk and rollback
- **Risk:** none beyond doc-only churn.
- **Rollback:** `git revert`.

---

## PR 7 — Tests, CI, and dependency-check automation

**Branch:** `chore/l2-l3-l10-ci-tests`
**Closes:** L2, L3, L10
**Size:** Medium
**Risk:** Low

### Goal
Stop relying on manual smoke tests and on no-one re-introducing a vulnerable JAR.

### Steps

1. **Replace `test/zebrautility_test.dart`** with real coverage:
   - Unit tests for `zebraStatusFromStrings` covering English, Spanish, color fallback, and missing-status path.
   - `MethodChannel` mock tests for `connectToPrinter`, `disconnect`, `getCurrentStatus`.
   - A test for `ZebraController.addPrinter`/`removePrinter`/`updatePrinterStatus`/`synchronizePrinter`.

2. **Add a GitHub Actions workflow** at `.github/workflows/ci.yml`:
   - `flutter analyze` and `flutter test` jobs on every PR.
   - Android job that runs `./gradlew :example:assembleDebug` against the latest stable AGP.
   - iOS job that runs `pod lib lint`.

3. **Add OWASP Dependency-Check** (or `gradle-versions-plugin`) to `android/build.gradle` and a CI step that fails on any High/Critical CVE.

4. **Add a SHA-256 verification step** for any binary that *must* remain vendored (after PRs 1 & 2 there should be none — this step then becomes a guardrail, failing if anyone re-adds an `*.a`/`*.jar` to the tree).

5. **Add `docs/VENDORED.md`** listing every external dependency, its source, version, and license. (Empty after PRs 1 & 2 — that's the goal.)

6. **L10 — Default `DeviceFilter`**: change [`BluetoothDiscoverer.java:56`](../android/src/main/java/com/rubdev/zebrautil/BluetoothDiscoverer.java) from `value -> true` to remove the parameter overload entirely (the real filter is `isPrinterClass`); or, if a configurable filter is desired, surface it on the `findPrinters` Flutter API.

### Files touched
- `test/printer_status_test.dart` (new)
- `test/printer_channel_test.dart` (new)
- `test/zebra_controller_test.dart` (new)
- `test/zebrautility_test.dart` (deleted or rewritten)
- `.github/workflows/ci.yml` (new)
- `android/build.gradle` (Dependency-Check plugin)
- `docs/VENDORED.md` (new)
- `android/src/main/java/com/rubdev/zebrautil/BluetoothDiscoverer.java` (L10)

### Acceptance criteria
- Every PR runs `flutter analyze`, `flutter test`, AGP build, and Dependency-Check in CI.
- A PR that adds a `*.jar` to `android/libs/` is blocked by the SHA verification step.

### Test plan
- Open a draft PR that re-adds a JAR to confirm the CI blocks it.
- Verify Dependency-Check picks up a known-vulnerable test fixture and fails.

### Risk and rollback
- **Risk:** initial CI runs may surface unrelated lint that needs separate fixes.
- **Rollback:** `git revert` the workflow file; tests can stay.

---

## Cross-cutting notes

### Order matters
- PR 1 must land before PR 7's Dependency-Check step is meaningful (otherwise the gating step would block PR 1 itself).
- PR 2's iOS rewrite is independent of PR 1 — they can run in parallel.
- PR 3, PR 4, and PR 5 are independent and small; ship in any order after PRs 1 & 2.
- PR 6 is doc-only and can ship anytime, but ideally last so it can reference everything else.

### What's *not* covered
- M3 (cleartext TCP) is not closed by code — it's a documented limitation. The plugin can't implement TLS for protocols the printer firmware doesn't support. PR 6 documents this; that's the right answer.
- L7 (ZPL injection surface) is similarly disclaimed in PR 6. The plugin's job is to send ZPL; sanitization is the integrator's responsibility.

### Branch / commit hygiene
- Each PR's commit message body must reference its finding IDs (e.g., `Closes H1, L9`).
- Rebase on `master` before opening each PR — don't stack PRs unless explicitly intended.
- Tag a release after PR 1 and PR 2 land so consumers know which version contains the supply-chain fixes.
