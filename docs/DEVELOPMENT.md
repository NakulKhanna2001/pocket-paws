# Developer guide

This guide covers the Mac app. See the [Windows guide](WINDOWS.md) for the .NET
tray app, Windows build commands, and native checks. Both apps embed the same
animal JSON from `Sources/PawsCore/Animals/`.

## Build and install

Requires Swift 6+ and Xcode 16+ command-line tools. There are no third-party
dependencies. Run these from the repository root:

```sh
swift run PawsChecks
bash scripts/build-app.sh
open "dist/Pocket Paws.app"
```

`bash scripts/install.sh` builds, installs into `~/Applications`, and launches the
app. It closes running copies first so an older copy does not intercept the launch.
It verifies the staged bundle's signature and replaces older installations without
retaining stale resources. Preferences remain in `dev.pocketpaws.mac`.

Installer options:

- `--no-open`: install without launching; only stop copies being replaced.
- `INSTALL_DIR="/your/folder"`: choose a different destination.
- `UNIVERSAL=1`: build both Apple Silicon and Intel slices.

The first build can take a few minutes. Building locally normally avoids the
downloaded-app verification prompt, although managed Macs may enforce additional
policies. No Apple Developer membership is needed for local builds.

## Add an animal

1. Copy a JSON file in `Sources/PawsCore/Animals/` and give it a unique `id`.
2. Set the name, species, personality, and six-digit RGB `accent`.
3. Draw `pixels`: a front-facing rectangular sprite, 8–48 pixels per side.
   `.` is transparent. Add other characters to `palette` as RGB hex colors without
   `#`. Reserve `o` for outline, `b` for body, and `e` for eyes.
4. Set `eyeRow` and the two `eyeColumns` to the zero-based front-facing eye pixels.
5. Optionally add `sidePixels` with the same dimensions and palette for alternate
   artwork experiments. The desktop companion uses the front sprite.
6. Update the expected animal count in `Tests/PawsChecks/main.swift`, run
   `swift run PawsChecks`, and rebuild.

Files are discovered automatically and sorted by filename. Two separated groups
on the bottom occupied row identify the feet for the shared six-frame step cycle.
The renderer is in `Sources/PocketPaws/PixelArt.swift`.

Regenerate the README portraits with `swift scripts/export-readme-animals.swift`,
then add your animal's picture, name, and species to the README table.

For a distributed fork, change `CFBundleIdentifier` in `Resources/Info.plist` to
your own reverse-DNS identifier.

## Project structure

```text
Sources/PawsCore/          Animal schema, gesture state machine, screen placement
Sources/PawsCore/Animals/  Original editable pixel-art JSON
Sources/PocketPaws/        AppKit overlay, SwiftUI menu-bar controls, renderer
Tests/PawsChecks/          Gesture, asset, and multi-display checks
Resources/Info.plist       macOS app metadata
scripts/build-app.sh      App bundle, generated icon, signing, release ZIP
scripts/install.sh        Local build, installation, and launch
```

Position updates run at 60 Hz; pixel animation runs at 8 fps. The pet follows the
pointer directly, with placement clamped to the current display. It ignores mouse
events and does not take keyboard focus. Reduced Motion is respected; pausing the
pet stops its timer and mouse monitors.

The overlay is configured to join Spaces and full-screen apps. Secure system
surfaces and exclusive full-screen apps may suppress it. Long press is not Force
Click, and automatic global “thinking/loading” detection is not implemented.

## Checks and previews

```sh
swift run PawsChecks
swift run PocketPaws --smoke-test
swift run PocketPaws --render-preview /absolute/path/preview.png
swift run PocketPaws --export-walk-preview /absolute/path/walking.gif
swift run PocketPaws --export-companion-preview /absolute/path/companion.gif
```

The smoke test launches and exits the real AppKit application. Preview commands
render the app's art without recording the desktop. Before a release, also check
mouse interactions, display layouts, Spaces, and full-screen apps interactively.

## Signed releases

The build script produces `dist/Pocket Paws.app` and `dist/Pocket-Paws-macOS.zip`.
Local builds use an ad-hoc signature. For a Developer ID-signed and notarized
release, configure your certificate and notary profile, then run:

```sh
UNIVERSAL=1 SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" bash scripts/build-app.sh
xcrun notarytool submit dist/Pocket-Paws-macOS.zip --keychain-profile YOUR_PROFILE --wait
xcrun stapler staple "dist/Pocket Paws.app"
ditto -c -k --sequesterRsrc --keepParent "dist/Pocket Paws.app" dist/Pocket-Paws-macOS.zip
```

The GitHub Actions workflow runs checks, builds the universal app, verifies local
installation, and uploads a ZIP artifact on pushes, pull requests, and manual
dispatch. It does not automatically notarize or publish releases.
