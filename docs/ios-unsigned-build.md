# VTT on iPhone — unsigned development build

This is a **free, on-demand CI build** for personal testing. No Mac, Apple
Developer Program membership, signing certificate, or GitHub secret is required
to build the unsigned IPA. **An unsigned IPA cannot be opened directly on iOS**:
it must be signed for a specific device with a separate tool.

## Build the IPA on GitHub

1. Open **Actions → VTT Mobile iOS (unsigned IPA)** in `francesco-bufalini/VTT`.
2. Click **Run workflow**, choose `main`, and launch it.
3. Once the workflow succeeds, download the `VTT-iOS-unsigned-<run number>` artifact.
4. Unzip the downloaded **artifact ZIP**: inside is `VTT-iOS-unsigned.ipa`.
   Do not unzip the IPA itself when passing it to Sideloadly.

The workflow uses Godot **4.7.2** with the matching official iOS export
templates, copies the same *slim mobile shell* as the Android workflow into
a temporary directory, then exports an Xcode project and compiles it with
code signing disabled. The macOS runner is provided by GitHub Actions.
Android and desktop export settings remain unchanged.

The iOS preset has the syntactically required **placeholder** App Store Team ID
`ABCDEFGHIJ`; this is NOT a real account, certificate, or distribution
identity. The Xcode build disables signing; the real developer identity is
supplied later by the owner's sideloading tool.

## Install from Windows (free Apple Account)

1. Install [Sideloadly](https://sideloadly.io/) from its official site on Windows.
   Its Apple device drivers/iTunes prerequisites must be installed as documented.
2. Connect and trust the iPhone via USB. Start Sideloadly.
3. Select the device, supply your own Apple Account and choose
   `VTT-iOS-unsigned.ipa`.
4. Complete the signing/install steps prompted by Sideloadly.
5. On the iPhone, enable Developer Mode if requested and trust the app/developer
   under iOS device management when prompted.

Free personal signing normally expires after **7 days**; refresh/reinstall
through Sideloadly. The free Apple provisioning limits (including installed
development-app limits) apply. Each tester signs the same unsigned IPA using
their own Apple Account. No Apple credentials are stored on GitHub.

**Privacy:** never add Apple passwords, provisioning profiles, or signing keys
to the repository or to action logs.

## Limits and troubleshooting

- Use **Run workflow** only when an iPhone build is needed. GitHub-hosted macOS
  minutes consume the repository's Actions quota and **may incur charges if
  your billing/spending settings permit overages**. Check GitHub
  Settings → Billing and licensing before running to enforce your desired
  spending limit.
- If GitHub Actions reports that macOS hosted jobs are unavailable or billing
  is disabled, this workflow cannot run until your account's Actions settings
  allow a macOS runner.
- If export fails, check the Godot 4.7.2 macOS editor and iOS template paths.
- If Xcode archive fails, inspect the `Compile unsigned iOS archive` step.
  This pipeline deliberately does not create a signed App Store archive.
- iOS local-network discovery may prompt for permission; allow local network
  access if you want to join a LAN-hosted VTT session.
- Successful CI builds do not prove that every gameplay feature works on a
  physical iPhone. Verify character creation, homebrew data, saved documents,
  LAN sessions and inventory transfer after installing.
- For actual public App Store or TestFlight distribution, an appropriate Apple
  Developer Program membership and proper Apple signing are needed.

Documentation: [Godot 4.7 iOS export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_ios.html);
[GitHub Actions](https://docs.github.com/en/actions);
[Sideloadly](https://sideloadly.io/).
