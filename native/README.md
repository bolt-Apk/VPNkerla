# VPNkerla — native application pilot

The source handoff was merged into the main branch through [PR #1](https://github.com/bolt-Apk/VPNkerla/pull/1).
Android [run #5](https://github.com/bolt-Apk/VPNkerla/actions/runs/34558831066)
passed all six client tests and produced the corrected ARM64 APK. The downloaded
APK passed SHA-256, signature, package name, VPNkerla label and native library
verification. [BUILD-STATUS.json](BUILD-STATUS.json) records the exact source
commit and artifact receipt. Real-device VPN behavior remains untested.

The Android pilot connects with an existing personal key. Its account API,
registration and payments are not configured. The separate commercial service
source belongs to the earlier product bundle; this repository handoff contains
the native client. The current website and VPN service are separate deployments.

## Implemented source

- Source for email-code registration/login, server-owned tariffs, YooKassa
  checkout, payment verification and three device slots; these account features
  require the separate API and are unavailable in the existing-key pilot.
- VPN button uses the existing FlClash native lifecycle and TUN integration.
- Server-generated Mihomo configuration: VLESS REALITY, VLESS XHTTP, Hysteria 2,
  fallback group without a DIRECT fallback.
- Session token stays in memory: the alpha requires login again after restart.
- Existing-key pilot mode accepts issued REALITY, XHTTP/TLS and Hysteria 2 links
  without account registration or payments; the VPN server still enforces key validity.
- Android, Windows, macOS and Linux targets inherited from FlClash.
- iOS is **not implemented**. It requires a separate Network Extension target,
  Apple signing, platform testing and store review.

## Reproduce source

From the repository root, run:

```sh
python3 native/materialize.py /absolute/new/client-directory
```

`native/upstream.json` pins the upstream client, core and dependency lock;
`native/upstream.patch` contains maintained upstream changes; `native/overlay/`
contains the custom interface, tests and pilot build script. The materializer
checks the pinned revisions and lock, applies the patch and copies the overlay
into a new directory. Git and network access to GitHub are required.

The previously uploaded ZIP is an older project snapshot. Reproduce the current
client from the current main branch, including the root workflow and `native/`.

Use Flutter 3.47.1, Go 1.26.4 and Rust 1.95.0 with the pinned dependency lock.
The core also requires platform toolchains. Android uses SDK 36 and NDK
28.2.13676358; the workflows explicitly select that NDK for Flutter's native
hooks. Windows needs a Windows build host, and macOS a Mac.
`dart run setup.dart --help` describes packaging targets.

In the reconstructed client:

```sh
python tool/kerla_build.py --platform android
```

This checks the client and builds a debug-signed APK for Android ARM64. The
script temporarily disables native hooks during localization and tests, restores
both hooks, then builds with `--split-per-abi --target-platform android-arm64`.
It copies `app-arm64-v8a-debug.apk` to `kerla-dist/VPNkerla-android-pilot.apk`
and writes a SHA-256 checksum and build status.

For a release build supply a verified HTTPS commercial API origin through
`KERLA_API_URL` in the setup script's `env.json` file (no merchant secrets in
this file). Keep native hook `build_assets` enabled. Run `dart run setup.dart`
for the host target or `dart run setup.dart android`. Configure your own signing
keys; do not distribute an unsigned/debug build as a finished release.

## Release gates still outstanding

Install the verified pilot recorded in `BUILD-STATUS.json` and exercise real TUN routing, reconnect, suspend/resume, DNS and IPv6 behavior on
physical Android devices. Windows, macOS and Linux installers have not been
built. Before enabling account features, test a YooKassa sandbox payment and
webhook, configure mail delivery and commercial API HTTPS, and verify device
revoke/expiry on the VPS.
No 5,000-user load test has been performed. Automatic protocol selection does
not guarantee access during filtering or a complete mobile data shutdown.

Advanced upstream settings remain available in this alpha. App names and primary
icons use VPNkerla. Internal helper service names are still upstream: coexistence
with an installed FlClash helper requires review before a Windows/Linux release.

## License

Based on FlClash by chen08209, GPL-3.0. Preserve upstream notices and provide
corresponding source and build instructions with distributed binaries. See
`LICENSE-FlClash` and the pinned upstream license/dependency notices. This is
not a closed-source proprietary relicense.

## Automated pilot build

The reconstructed source includes `tool/kerla_build.py` and a manual GitHub
Actions workflow named **VPNkerla pilot**. It does not publish releases, contact
Telegram, or enable payments. Choose one target; the default is Android arm64.
Leave the API URL empty to test an already issued key. The Android result is a
**debug-signed pilot**, not a store release; desktop bundles are unsigned.

Run on a configured host:

```sh
python tool/kerla_build.py --platform android
```

The script regenerates localization, analyzes the project, runs the focused
client tests and restores both native build hooks before packaging. Output and
SHA-256 checksums go to `kerla-dist/`. macOS, Windows and Linux must be built on
the corresponding host. OS-level VPN permission and routing still need a real
device test. Apple iOS remains a separate implementation.

## Build from the product repository

The root `.github/workflows/native-pilot.yml` reconstructs the pinned client from
`native/materialize.py` before building. Use this workflow when the GitHub repo
contains the product tree with `native/`, rather than the reconstructed Flutter
client itself. It runs an Android build for pull requests and supports manual platform builds. It keeps payments disabled when the API input
is empty. Current CI history is linked above; artifact verification is recorded
in `BUILD-STATUS.json`. See `GITHUB-BUILD-RU.md`.
