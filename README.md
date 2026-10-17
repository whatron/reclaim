# Reclaim

A native macOS app (SwiftUI) that shows what's filling your disk and cleans it up safely.

## Build and run

You need macOS 14 or later and Apple's command-line tools. If you have Xcode or Homebrew, you already have them.

```bash
cd ReclaimMac
chmod +x build.sh
./build.sh --install     # builds, copies to /Applications, opens it
```

Use `./build.sh` without `--install` to build into `build/Reclaim.app` and run it from there.
To work on it in Xcode, open `Package.swift`.

## First launch

1. macOS may ask whether Reclaim can read Documents, Desktop and Downloads. Allow it so those folders get measured.
2. For exact numbers in Library, app containers and the Trash, turn on **Full Disk Access**. Go to
   System Settings → Privacy & Security → Full Disk Access, click +, and add Reclaim. The banner in the app opens that page for you.
   Rebuilding the app gives it a new signature, so you may need to switch Full Disk Access off and on again after a rebuild.

## What it does

- **Clean Up**: free space at a glance, plus one-click cleanups for Ollama models, Docker/Colima, IntelliJ snapshots, Maven, Gradle, npm, Go, Homebrew, app and tool caches, Xcode data, Downloads and the Trash.
- **Explore**: a treemap of your home folder. Click a block to select it, double-click a folder to open it, and right-click for Show in Finder or Move to Trash.
- **Large Files**: every file over 500 MB, found with Spotlight.
- **Activity**: every action, with the full command output.
- **Menu bar**: free space at a glance. You can turn this off in Settings (⌘,).

Keyboard: ⌘R rescans, ⌘1–4 switch sections, ⌘↑ goes to the enclosing folder, and ⌘⌫ moves the selection to the Trash.

## Safety

- Files are moved to the Trash the same way Finder does it, so **Put Back** works.
- Emptying the Trash is the only permanent action, and you have to type "empty" to do it.
- The app only runs a fixed set of cleanup commands: `docker system prune -af` (volumes are kept), `npm cache clean --force`, `go clean -modcache`, `brew cleanup --prune=all`, `xcrun simctl delete unavailable` and `ollama rm <model>`.
- Home, Library, Documents, Desktop, iCloud Drive, Mail and credential folders such as `.ssh` and `.aws` can never be trashed.
