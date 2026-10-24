# Matisse iOS Connector

This companion is the native iOS path for selected Android photos and videos.
It receives only the selected backup files over the local network, checks each
file's size and SHA-256, and asks PhotoKit to add photos and videos to Photos.
Documents and audio files are saved in the app's Files container; iOS does not
offer this app a public API to insert local MP3 files into Apple Music.

## Current state

The Swift source and manual macOS build workflow are present. The workflow builds
an unsigned `.app`; it does not sign or install an iPhone app. The Xcode build has
not been run in this Windows/Linux workspace. Apple requires Xcode on a supported
macOS version to build iOS device apps. The generated app will need a valid local
signing/provisioning path before it can be installed on the iPhone.

The desktop receiver is `../iphone_bridge_server.py`. It serves only categories
selected with `--only`, binds to the local network, and uses a fresh random token
in its URL. Stop it with Ctrl+C after the transfer. Keep the PC and iPhone on the
same trusted local network.

Example:

```powershell
python ..\iphone_bridge_server.py --backup ..\..\backups\motorola_razr_fold_20261023_110902 --only foto,video
```

The iOS app currently accepts the printed base URL. Each downloaded item is
verified before it is added. A failed transfer may have completed earlier items;
the app reports each completed item separately. Contact and calendar import stay
in the desktop USB sync path. SMS and call history cannot be written through the
public iOS APIs used here. The SMS selective restore prototype remains a separate
initialized-iPhone experiment and is not presented as a general merge.

## Build

The root workflow `.github/workflows/build-ios-connector.yml` can be started
manually from GitHub Actions after this project is pushed to a repository. It
uses a macOS runner and uploads an unsigned IPA. The root `.gitignore` excludes
phone backups, REA reports, and local toolchains from that repository.

The Windows installation route can use a local IPA signing tool such as
[Sideloadly](https://sideloadly.io/), which documents Windows support and signing
with a free Apple ID. Free provisioning is time-limited and needs periodic
refresh; iOS 16 development-signed apps require Developer Mode ([Apple instructions](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)). The owner enters
Apple credentials only into the signing tool on their own PC; this project does
not collect them. This route has not yet been run on Sandro's PC or iPhone.

Photo imports use Apple's PhotoKit change request APIs, which prompt for the
user's permission before modifying the photo library. See Apple's
[PhotoKit change request documentation](https://developer.apple.com/documentation/photokit/requesting-changes-to-the-photo-library).
