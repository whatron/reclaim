import Foundation

enum Advice {
    case safe, review, keep

    var label: String {
        switch self {
        case .safe: return "Safe to clear"
        case .review: return "Look before deleting"
        case .keep: return "Keep"
        }
    }
}

struct Explanation {
    let title: String
    let detail: String
    let advice: Advice
    let symbol: String
}

/// Plain-language descriptions of folders that commonly fill up a developer's Mac.
enum Knowledge {
    private struct Rule {
        let match: (String) -> Bool
        let explanation: Explanation
    }

    private static func under(_ relative: String) -> (String) -> Bool {
        let root = Paths.h(relative)
        return { $0 == root || $0.hasPrefix(root + "/") }
    }

    private static func named(_ name: String) -> (String) -> Bool {
        return { Paths.name($0) == name }
    }

    private static let rules: [Rule] = [
        Rule(match: under(".ollama"), explanation: Explanation(
            title: "Ollama models",
            detail: "Local AI models. Remove unused ones from Smart Clean rather than deleting files here, so Ollama's index stays consistent.",
            advice: .review, symbol: "brain")),
        Rule(match: under(".colima"), explanation: Explanation(
            title: "Colima virtual machine",
            detail: "The Linux VM that runs your Docker containers. Its disk image only shrinks after pruning Docker and trimming the VM. Smart Clean does both.",
            advice: .keep, symbol: "shippingbox")),
        Rule(match: under("Library/Containers/com.docker.docker"), explanation: Explanation(
            title: "Docker Desktop disk",
            detail: "Docker Desktop's virtual disk. Prune images from Smart Clean instead of deleting this file.",
            advice: .keep, symbol: "shippingbox")),
        Rule(match: under(".m2/repository"), explanation: Explanation(
            title: "Maven downloads",
            detail: "Java libraries downloaded by Maven. Everything here is fetched again on the next build.",
            advice: .safe, symbol: "cup.and.saucer")),
        Rule(match: under(".gradle"), explanation: Explanation(
            title: "Gradle caches",
            detail: "Dependencies, wrapper distributions and build caches. Gradle recreates what it needs.",
            advice: .safe, symbol: "cup.and.saucer")),
        Rule(match: under(".npm"), explanation: Explanation(
            title: "npm cache",
            detail: "Every package npm has downloaded. Clearing it only means slower first installs.",
            advice: .safe, symbol: "curlybraces")),
        Rule(match: under("go/pkg/mod"), explanation: Explanation(
            title: "Go module cache",
            detail: "Downloaded Go modules. Use Smart Clean, because Go marks these files read-only.",
            advice: .safe, symbol: "chevron.left.forwardslash.chevron.right")),
        Rule(match: under(".cache/huggingface"), explanation: Explanation(
            title: "Hugging Face models",
            detail: "Downloaded models and datasets. They can be many gigabytes and slow to download again.",
            advice: .review, symbol: "brain")),
        Rule(match: under(".cache"), explanation: Explanation(
            title: "Tool caches",
            detail: "Caches for pip, uv, pre-commit and other command-line tools. Rebuilt on demand.",
            advice: .safe, symbol: "terminal")),
        Rule(match: under("IdeaSnapshots"), explanation: Explanation(
            title: "IntelliJ snapshots",
            detail: "Memory and CPU profiler snapshots. Only useful while you're investigating a problem.",
            advice: .safe, symbol: "camera.metering.matrix")),
        Rule(match: under("Library/Caches"), explanation: Explanation(
            title: "App caches",
            detail: "Temporary data apps keep to load faster. Apps rebuild it; quit them before clearing.",
            advice: .safe, symbol: "archivebox")),
        Rule(match: under("Library/Developer/Xcode/DerivedData"), explanation: Explanation(
            title: "Xcode build data",
            detail: "Intermediate build products. Xcode rebuilds them; clearing also fixes many odd build errors.",
            advice: .safe, symbol: "hammer")),
        Rule(match: under("Library/Developer/Xcode/iOS DeviceSupport"), explanation: Explanation(
            title: "iPhone debug symbols",
            detail: "Copied from each iPhone you've debugged. Recreated when you plug the device in again.",
            advice: .safe, symbol: "iphone")),
        Rule(match: under("Library/Developer/CoreSimulator"), explanation: Explanation(
            title: "iOS simulators",
            detail: "Simulator devices and their data. Remove unavailable ones from Smart Clean.",
            advice: .review, symbol: "iphone")),
        Rule(match: under("Library/Application Support/MobileSync/Backup"), explanation: Explanation(
            title: "iPhone backups",
            detail: "Local backups of your iPhone or iPad. Delete old ones from Finder's device page so you don't lose the latest.",
            advice: .review, symbol: "iphone.gen3")),
        Rule(match: under("Library/Messages"), explanation: Explanation(
            title: "Messages attachments",
            detail: "Photos and files from your chats. Manage them in Messages, or System Settings › General › Storage.",
            advice: .keep, symbol: "message")),
        Rule(match: under("Library/Mail"), explanation: Explanation(
            title: "Mail",
            detail: "Your mailboxes and attachments. Manage these inside Mail.",
            advice: .keep, symbol: "envelope")),
        Rule(match: under("Library/Mobile Documents"), explanation: Explanation(
            title: "iCloud Drive",
            detail: "Files synced with iCloud. Deleting here deletes them everywhere; use Finder to remove local copies instead.",
            advice: .keep, symbol: "icloud")),
        Rule(match: under("Pictures"), explanation: Explanation(
            title: "Pictures",
            detail: "Your photos. If the Photos library is large, turn on Optimise Mac Storage in Photos settings.",
            advice: .keep, symbol: "photo.on.rectangle")),
        Rule(match: under("Downloads"), explanation: Explanation(
            title: "Downloads",
            detail: "Installers and archives pile up here. Large Files shows the ones you haven't opened in months.",
            advice: .review, symbol: "arrow.down.circle")),
        Rule(match: named("node_modules"), explanation: Explanation(
            title: "Node packages",
            detail: "Installed JavaScript dependencies. Recreated with npm install, so old projects can safely lose them.",
            advice: .safe, symbol: "curlybraces")),
        Rule(match: named(".venv"), explanation: Explanation(
            title: "Python virtual environment",
            detail: "Installed Python packages for one project. Recreate it from requirements when you need it.",
            advice: .safe, symbol: "chevron.left.forwardslash.chevron.right")),
        Rule(match: named("DerivedData"), explanation: Explanation(
            title: "Build data",
            detail: "Intermediate build products that are rebuilt automatically.",
            advice: .safe, symbol: "hammer")),
        Rule(match: { $0.hasSuffix(".photoslibrary") }, explanation: Explanation(
            title: "Photos library",
            detail: "Never delete this. To save space, turn on Optimise Mac Storage in Photos settings.",
            advice: .keep, symbol: "photo.on.rectangle.angled")),
        Rule(match: { $0.hasSuffix(".dmg") || $0.hasSuffix(".pkg") }, explanation: Explanation(
            title: "Installer",
            detail: "Once the app is installed, the installer is no longer needed.",
            advice: .safe, symbol: "shippingbox")),
    ]

    static func explain(_ path: String) -> Explanation? {
        rules.first { $0.match(path) }?.explanation
    }
}
