# Reclaim

A native macOS app that shows what's filling your disk, explains it in plain language, and cleans it up safely.

Your disk is drawn as a glass vessel. Deep blue water is your data, the glowing mint shallows are what Reclaim can clear, coral is the Trash, and the air above is free space. Every cleanup drains the mint.

<!-- screenshots -->

## What it does

**Overview.** Free space at a glance, a one-sentence summary of where you stand, and recommendations ranked by how much space they'd free. Examples: "14 GB is safe to clear", "3 idle projects carry 9 GB", "Full in about 40 days".

**Smart Clean.** Caches and build output that rebuild themselves are ticked for you, and one click cleans them all. Items worth a closer look (Docker, Ollama models, app caches, simulators) are kept separate and never ticked automatically. Each row shows how much it grew this week.

**Space Map.** Your home folder as interactive rings, or as blocks if you prefer. Hover to identify anything, click to select it, and double-click to dive in. The inspector explains common folders (".colima is the VM behind Docker", "keep your Photos library") and says whether each one is safe to clear.

**Projects.** Finds `node_modules`, `target`, `build`, `.venv`, `Pods`, `.next` and friends inside your code projects. Projects you haven't touched for a month, judged by file and git activity, are ticked, and each folder shows the command that rebuilds it.

**Large Files.** Everything over 100 MB, filed by type (videos, installers, archives, disk images), with when you last opened it. It flags installers and archives that are just sitting in Downloads.

**Duplicates.** Finds true copies by comparing contents (SHA-256), not names. It suggests which copy to keep and always leaves at least one.

**Apps.** Third-party apps by size and when you last opened them, with the ones you haven't used in three months picked out.

**History.** An hourly record of free space, a forecast of when your disk fills up, what grew this week, and a log of every cleanup with the commands it ran.

**Menu bar.** Free space at a glance and the top recommendation. Reclaim can warn you when space runs low.

## Build and run

You need macOS 14 or later and Apple's developer tools (Xcode 16 or later, or the Command Line Tools).

```bash
git clone https://github.com/whatron/reclaim.git
cd reclaim
./build.sh --install     # builds, copies to /Applications, opens it
```

`./build.sh` alone builds into `build/Reclaim.app` and opens it from there. To work on the code in Xcode, open `Package.swift`.

You can also skip building: every push is compiled on GitHub, and the **Build** run for a commit has a downloadable **Reclaim-app** zip. That download isn't notarized, so the first time, right-click the app and choose Open.

### First launch

1. macOS asks whether Reclaim can read Documents, Desktop and Downloads. Allow it so those folders are measured.
2. For exact numbers in Library, app containers and the Trash, turn on **Full Disk Access**: System Settings → Privacy & Security → Full Disk Access, then add Reclaim. Reclaim's banner takes you to the right page. Each rebuild changes the app's signature, so after rebuilding you may need to switch Full Disk Access off and on again.

Keyboard: ⌘1–⌘8 switch pages, ⌘R rescans, ⇧⌘K cleans everything recommended, ⌘↑ goes up a folder in Space Map, ⌘⌫ moves the selection to the Trash, and ⌘↩ runs the clean on Smart Clean.

## Safety

- Files are moved to the Trash the same way Finder does it, so **Put Back** works.
- Emptying the Trash is the only permanent action, and you have to type "empty" to do it.
- The only commands Reclaim runs are a fixed set: `docker system prune -af` (volumes are kept), `colima ssh -- sudo fstrim -a`, `npm cache clean --force`, `go clean -modcache`, `brew cleanup --prune=all`, `xcrun simctl delete unavailable` and `ollama rm <model>`.
- Your home folder, Library, Documents, Desktop, iCloud Drive, Mail, Messages, Photos and Music libraries, app bundles' insides, and credential folders such as `.ssh` and `.aws` can never be trashed.
- Everything runs on your Mac. Nothing is uploaded anywhere.

## How the code is laid out

| File | What's in it |
| --- | --- |
| `Model*.swift` | App state, cleanups, discovery scans, insights, forecasting, alerts |
| `Shell.swift`, `System.swift` | Running commands, measuring with `du`, Trash, safety rules, Spotlight |
| `Scanners.swift`, `ProjectScanner.swift`, `DuplicateFinder.swift` | Large files, apps, code projects, duplicates |
| `Knowledge.swift` | Plain-language explanations of common folders |
| `History.swift` | Hourly snapshots, compaction and the fill-up forecast |
| `Theme.swift`, `TideGauge.swift` | Colours, surfaces and the animated vessel |
| `*View.swift`, `SpaceMap.swift` | One file per page; the rings and blocks charts |
