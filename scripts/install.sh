#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCH=1
for argument in "$@"; do
    case "$argument" in
        --no-open) LAUNCH=0 ;;
        --help|-h)
            printf 'Usage: bash scripts/install.sh [--no-open]\n'
            printf 'Build locally, install in ~/Applications, and open Pocket Paws.\n'
            printf 'Set INSTALL_DIR to choose another destination. No sudo is needed.\n'
            exit 0 ;;
        *) printf 'Unknown option: %s\n' "$argument" >&2; exit 2 ;;
    esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
    printf 'Pocket Paws requires macOS.\n' >&2
    exit 1
fi
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
    printf 'Install Apple command-line tools first: xcode-select --install\n' >&2
    printf 'Finish that installation, then run this script again.\n' >&2
    exit 1
fi
SWIFT_VERSION="$(swift --version)"
if [[ ! "$SWIFT_VERSION" =~ Swift\ version\ ([0-9]+) ]] || (( BASH_REMATCH[1] < 6 )); then
    printf 'Building Pocket Paws requires Swift 6 or newer (Xcode 16+ tools).\n' >&2
    printf 'Update your Apple developer tools, then check: swift --version\n' >&2
    exit 1
fi

INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
mkdir -p "$INSTALL_DIR"
INSTALL_DIR="$(cd "$INSTALL_DIR" && pwd)"
APP="$INSTALL_DIR/Pocket Paws.app"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ROOT/Resources/Info.plist")"
if [[ -e "$APP" || -L "$APP" ]]; then
    EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || true)"
    if [[ "$EXISTING_ID" != "$BUNDLE_ID" || -L "$APP" ]]; then
        printf 'The destination is not a matching Pocket Paws installation: %s\n' "$APP" >&2
        printf 'Choose another folder using INSTALL_DIR.\n' >&2
        exit 1
    fi
fi

# Close running copies so a singleton from Downloads does not intercept the new
# launch. With --no-open, only close copies whose files will actually be replaced.
swift - "$BUNDLE_ID" "$APP" "$ROOT/dist/Pocket Paws.app" "$LAUNCH" <<'SWIFT'
import AppKit
let args = CommandLine.arguments
let paths = Set([args[2], args[3]].map { URL(fileURLWithPath: $0).standardizedFileURL.path })
let apps = NSRunningApplication.runningApplications(withBundleIdentifier: args[1]).filter {
    args[4] == "1" || paths.contains($0.bundleURL?.standardizedFileURL.path ?? "")
}
for app in apps {
    guard app.terminate() else {
        fputs("Quit Pocket Paws from its paw menu, then run the installer again.\n", stderr)
        exit(1)
    }
}
let deadline = Date().addingTimeInterval(10)
while apps.contains(where: { !$0.isTerminated }) && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
if apps.contains(where: { !$0.isTerminated }) {
    fputs("Pocket Paws is still running. Quit it and retry the installer.\n", stderr)
    exit(1)
}
SWIFT

bash "$ROOT/scripts/build-app.sh"

# Stage a complete bundle instead of merging files into an older version.
STAGING="$(mktemp -d "$INSTALL_DIR/.pocket-paws-install.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "$ROOT/dist/Pocket Paws.app" "$STAGING/Pocket Paws.app"
codesign --verify --deep --strict "$STAGING/Pocket Paws.app"
if [[ -d "$APP" ]]; then mv "$APP" "$STAGING/previous.app"; fi
if ! mv "$STAGING/Pocket Paws.app" "$APP"; then
    if [[ -d "$STAGING/previous.app" ]]; then
        if ! mv "$STAGING/previous.app" "$APP"; then
            trap - EXIT
            printf 'The previous app is preserved at: %s\n' "$STAGING/previous.app" >&2
        fi
    fi
    exit 1
fi

printf 'Installed: %s\n' "$APP"
if [[ "$LAUNCH" == "1" ]]; then
    open "$APP"
    printf 'Look for the paw icon in your Mac menu bar.\n'
fi
