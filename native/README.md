# VPNkerla — native application alpha

This is source code, not a released or certified installer. The commercial API
is a separate service in `../infra/commercial`; the existing Sites login and
pilot agent are not replaced automatically.

## Implemented source

- Native Flutter home with email-code registration/login, server-owned tariffs,
  YooKassa checkout in the browser, payment verification and three device slots.
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

Run `python3 native/materialize.py /absolute/new/client-directory` from this
product bundle. The script verifies pinned upstream and core revisions, applies
the maintained patch and copies the custom interface. Git and network access
to GitHub are required. Never build an unverified substitute core binary.

Use Flutter 3.47.1, Go 1.26.4 and Rust 1.95.0 with the pinned dependency lock.
The core also requires platform toolchains; Android needs SDK/NDK, Windows a Windows build
host, macOS a Mac. `dart run setup.dart --help` describes packaging targets.

In the reconstructed client:

```sh
CI=true TAR_OPTIONS=--no-same-owner flutter --suppress-analytics pub get
dart run intl_utils:generate
flutter analyze
```

For a release build supply a verified HTTPS commercial API origin through
`KERLA_API_URL` in the setup script's `env.json` file (no merchant secrets in
this file). Keep native hook `build_assets` enabled. Run `dart run setup.dart`
for the host target or `dart run setup.dart android`. Configure your own signing
keys; do not distribute an unsigned/debug build as a finished release.

## Release gates still outstanding

Compile and test installers on each OS; exercise real TUN routing, reconnect,
suspend/resume, DNS and
IPv6 behavior; test an actual YooKassa sandbox payment and webhook; configure
mail delivery and commercial API HTTPS; verify device revoke/expiry on the VPS.
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

No GitHub Actions build has been launched: no existing VPNkerla repository was
found among the connected GitHub installations. The source can be uploaded to
a new repository and its manual workflow run when that access is available.

## Build from the product repository

The root `.github/workflows/native-pilot.yml` reconstructs the pinned client from
`native/materialize.py` before building. Use this workflow when the GitHub repo
contains the product tree with `native/`, rather than the reconstructed Flutter
client itself. It runs an Android build for pull requests and supports manual platform builds. It keeps payments disabled when the API input
is empty. No GitHub execution has been performed yet. See `GITHUB-BUILD-RU.md`.
