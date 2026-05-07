# Vendored binaries

This file lists every binary committed to the repo that is not built from the source in this repo. Anyone updating a vendored binary must also update its entry here (filename, version, source URL, SHA-256, license, reason for vendoring).

CI may use this file as the source of truth for SHA verification — re-introducing or modifying a binary without updating this file should fail the build.

## Status

| Severity | Item |
|---|---|
| ⚠️ Action required | All Android JARs are vendored against an outdated Zebra Link-OS Multiplatform SDK (v2.14.5198, ca. 2018). Several have known CVEs (see below). The right fix is to upgrade Zebra SDK to a current version (3.x), which removes most of these transitive deps. Until the upgrade, they are documented here as a known risk. |

## Android — `android/libs/`

| File | Version | Source | SHA-256 | License | Reason |
|---|---|---|---|---|---|
| `ZSDK_ANDROID_API.jar` | Zebra Link-OS Multiplatform SDK 2.14.5198 (build 03b8d7e) | Zebra Developer Portal — https://developer.zebra.com (login-walled) | `85314d15e3f66ae2bdf72bbaf470473078be8d16d08f98d860b4588078b5e067` | Zebra Link-OS SDK License (proprietary; redistributable per SDK EULA) | Plugin's primary dep — provides `com.zebra.sdk.{comm,printer,printer.discovery}` |
| `jackson-databind-2.2.3.jar` | 2.2.3 | https://repo1.maven.org/maven2/com/fasterxml/jackson/core/jackson-databind/2.2.3/ | `d0eef10544e4c81de0aad17cc2a6275438a04ee651c057fd0549736a21f23d68` | Apache-2.0 | ⚠️ Transitively required by Zebra SDK 2.14 (126 class refs). **Has known RCE CVEs** (CVE-2017-7525, CVE-2017-15095, CVE-2018-7489, CVE-2018-14718, CVE-2019-12384, CVE-2019-14540, CVE-2019-16335, CVE-2019-17531, CVE-2020-9548, …). Cannot be removed without upgrading the Zebra SDK. |
| `jackson-core-2.2.3.jar` | 2.2.3 | https://repo1.maven.org/maven2/com/fasterxml/jackson/core/jackson-core/2.2.3/ | `a74fa96e1ca00c47c185b2a78ed935a9e8b2e8ebb2691ef71494190dc4332b5a` | Apache-2.0 | ⚠️ Pair of jackson-databind. Same upgrade story. |
| `jackson-annotations-2.2.3.jar` | 2.2.3 | https://repo1.maven.org/maven2/com/fasterxml/jackson/core/jackson-annotations/2.2.3/ | `106c9188f1c7fc77754e169672041e9a7db2c7844b1ad1d5d22807611e1399e1` | Apache-2.0 | ⚠️ Pair of jackson-databind. Same upgrade story. |
| `httpcore-4.3.1.jar` | 4.3.1 | https://repo1.maven.org/maven2/org/apache/httpcomponents/httpcore/4.3.1/ | `5a172c9536eff1115eff2eae1ac3b7aa616a8b532994d12d1a06ad5fd7366d65` | Apache-2.0 | Transitively required by Zebra SDK (multipart upload). Outdated. |
| `httpmime-4.3.2.jar` | 4.3.2 | https://repo1.maven.org/maven2/org/apache/httpcomponents/httpmime/4.3.2/ | `b8ac0a04db70fecbd5f22d265743485fe32f6c6291aa82bcc669d0e1aa26e9c2` | Apache-2.0 | Transitively required by Zebra SDK (`org.apache.http.entity.mime.MultipartEntityBuilder`). Outdated. |
| `commons-net-3.1.jar` | 3.1 | https://repo1.maven.org/maven2/commons-net/commons-net/3.1/ | `34a58d6d80a50748307e674ec27b4411e6536fd12e78bec428eb2ee49a123007` | Apache-2.0 | Transitively required by Zebra SDK (network discovery). Outdated. |
| `commons-lang3-3.4.jar` | 3.4 | https://repo1.maven.org/maven2/org/apache/commons/commons-lang3/3.4/ | `734c8356420cc8e30c795d64fd1fcd5d44ea9d90342a2cc3262c5158fbc6d98b` | Apache-2.0 | Transitively required by Zebra SDK (`EqualsBuilder`, `HashCodeBuilder`). Outdated. |
| `commons-validator-1.4.0.jar` | 1.4.0 | https://repo1.maven.org/maven2/commons-validator/commons-validator/1.4.0/ | `50cee086060f86238c51f83900299552f76f8054e38c34557c7139b7e27a6c54` | Apache-2.0 | Transitively required by Zebra SDK (`UrlValidator`, `RegexValidator`). Outdated. |
| `opencsv-2.2.jar` | 2.2 | https://repo1.maven.org/maven2/net/sf/opencsv/opencsv/2.2/ | `168fd9ae011cefccfaa2aaaab9daa731d94057a766c0d49f2705bd0d1ff7fab8` | Apache-2.0 | Transitively required by Zebra SDK (`au.com.bytecode.opencsv.CSVReader`, single ref). Very old. |
| `snmp6_1z.jar` | unknown (custom build) | unknown | `a63cd9a4cafcd70a1b29b292e41c1c042f1d8dd5a5fb4c0af3524ea38a7a151c` | unknown | Transitively required by Zebra SDK for SNMP-based printer discovery (88 class refs). Provenance unclear — likely a re-package of [SNMP4J](https://www.snmp4j.org/) or a custom Zebra build. **License needs verification before redistribution.** |

### Removed in this PR

| File | Version | SHA-256 of original | Reason |
|---|---|---|---|
| `core-1.53.0.0.jar` | BouncyCastle 1.53 | (recorded in git history) | Zebra SDK uses `org.spongycastle.*`, not `org.bouncycastle.*`. Bundled JAR was unreachable dead weight. CVEs avoided: CVE-2015-7940, CVE-2016-1000338..352, CVE-2018-1000180, CVE-2018-1000613, CVE-2018-5382. |
| `pkix-1.53.0.0.jar` | BouncyCastle 1.53 | (recorded in git history) | Same — `org.bouncycastle.*` not referenced. |
| `prov-1.53.0.0.jar` | BouncyCastle 1.53 | (recorded in git history) | Same — `org.bouncycastle.*` not referenced. |

Verification: `jdeps -v android/libs/ZSDK_ANDROID_API.jar | grep -iE 'bouncy|spongy'` shows `org.spongycastle` references only (e.g. from `com.zebra.sdk.certificate.internal.CertUtilities`). The bundled `org.bouncycastle.*` 1.53 classes never matched what the SDK requested.

## Path forward

1. **Upgrade Zebra SDK to current.** Zebra Link-OS Multiplatform SDK 3.x removes most of these transitive deps. Coordinates should be confirmed via Zebra's developer portal before adoption. Once upgraded, remove the corresponding JARs from `android/libs/` and update this file.
2. **CI guard.** Add a CI step that fails if a `.jar` is added to `android/libs/` without a corresponding entry here, or if a SHA-256 mismatches.
3. **Replace `snmp6_1z.jar`** with a verified release from a known SNMP library (SNMP4J or similar) — its provenance is currently unclear.

## Why we didn't fully delete the rest

`jdeps -v android/libs/ZSDK_ANDROID_API.jar` shows the SDK has hard class references (resolved at the JVM/Dalvik bytecode level) into Jackson, Apache HTTP, commons-*, opencsv, and a custom SNMP package. Deleting them would surface as `NoClassDefFoundError` at runtime when network discovery / SNMP / multipart upload paths run. The right fix is to upgrade Zebra SDK, not to keep the SDK pinned to 2.14.5198 and try to substitute a newer Jackson — that path lands in version-conflict purgatory.
