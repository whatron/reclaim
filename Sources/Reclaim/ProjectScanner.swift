import Foundation

enum ArtifactKind: String {
    case nodeModules, jsCache, rustTarget, mavenTarget, scalaTarget, gradleBuild, gradleCache
    case flutterBuild, dartTool, cmakeBuild, pythonVenv, pods, terraform, dotnetBuild

    var label: String {
        switch self {
        case .nodeModules: return "node_modules"
        case .jsCache: return "Framework build cache"
        case .rustTarget: return "Cargo target"
        case .mavenTarget: return "Maven target"
        case .scalaTarget: return "sbt target"
        case .gradleBuild: return "Gradle build"
        case .gradleCache: return "Gradle project cache"
        case .flutterBuild: return "Flutter build"
        case .dartTool: return ".dart_tool"
        case .cmakeBuild: return "CMake build"
        case .pythonVenv: return "Python virtualenv"
        case .pods: return "CocoaPods"
        case .terraform: return "Terraform providers"
        case .dotnetBuild: return ".NET build output"
        }
    }

    var rebuild: String {
        switch self {
        case .nodeModules: return "npm install"
        case .jsCache: return "rebuilt on next dev or build"
        case .rustTarget: return "cargo build"
        case .mavenTarget: return "mvn package"
        case .scalaTarget: return "sbt compile"
        case .gradleBuild, .gradleCache: return "./gradlew build"
        case .flutterBuild, .dartTool: return "flutter pub get"
        case .cmakeBuild: return "cmake --build"
        case .pythonVenv: return "python -m venv, then pip install"
        case .pods: return "pod install"
        case .terraform: return "terraform init"
        case .dotnetBuild: return "dotnet build"
        }
    }
}

struct ProjectArtifact: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let kind: ArtifactKind
    let size: Int64
    var name: String { Paths.name(path) }
}

struct Project: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let name: String
    let ecosystem: String
    let symbol: String
    let lastActivity: Date
    let artifacts: [ProjectArtifact]

    var size: Int64 { artifacts.reduce(0) { $0 + $1.size } }
    var idleDays: Int { Format.days(since: lastActivity) ?? 0 }
    var isStale: Bool { idleDays >= 30 }
}

extension Scanners {
    private static let candidateNames = [
        "node_modules", "target", "build", ".gradle", ".venv", "venv", ".next", ".nuxt", ".svelte-kit",
        ".turbo", ".angular", ".parcel-cache", "Pods", ".terraform", ".dart_tool", "bin", "obj",
    ]
    private static let allowedHidden = [".venv", ".next", ".nuxt", ".svelte-kit", ".turbo", ".angular",
                                        ".parcel-cache", ".gradle", ".terraform", ".dart_tool"]

    /// Finds build output and dependency folders inside code projects under the home folder.
    static func projects(progress: @escaping @Sendable (String) -> Void) -> [Project] {
        progress("Looking for code projects…")
        let home = Paths.home
        var args = ["/usr/bin/find", home, "-maxdepth", "7", "("]
        let pruned = [Paths.h("Library"), Paths.trash, Paths.h("Pictures"), Paths.h("Music"),
                      Paths.h("Movies"), Paths.h("Applications"), Paths.h("go/pkg")]
        for (i, p) in pruned.enumerated() {
            if i > 0 { args.append("-o") }
            args += ["-path", p]
        }
        args += ["-o", "(", "-name", ".*"]
        for keep in allowedHidden { args += ["!", "-name", keep] }
        args += [")", ")", "-prune", "-o", "-type", "d", "("]
        for (i, n) in candidateNames.enumerated() {
            if i > 0 { args.append("-o") }
            args += ["-name", n]
        }
        args += [")", "-print", "-prune"]

        let found = Shell.run(args, timeout: 600).stdout.split(separator: "\n").map(String.init)
        let fm = FileManager.default
        var byProject: [String: [(String, ArtifactKind)]] = [:]
        for dir in found {
            let parent = Paths.parent(dir)
            guard let siblings = try? fm.contentsOfDirectory(atPath: parent),
                  let kind = classify(dir: dir, siblings: Set(siblings)) else { continue }
            byProject[parent, default: []].append((dir, kind))
        }

        let allPaths = byProject.values.flatMap { $0.map { $0.0 } }
        progress("Measuring \(allPaths.count) build folders…")
        let sizes = Shell.sizes(of: allPaths)

        var projects: [Project] = []
        for (root, items) in byProject {
            let artifacts = items.map { ProjectArtifact(path: $0.0, kind: $0.1, size: sizes[$0.0] ?? 0) }
                .filter { $0.size > 0 }
                .sorted { $0.size > $1.size }
            guard !artifacts.isEmpty else { continue }
            let skip = Set(items.map { Paths.name($0.0) })
            let (ecosystem, symbol) = describe(root: root, kinds: items.map { $0.1 })
            projects.append(Project(path: root, name: Paths.name(root), ecosystem: ecosystem, symbol: symbol,
                                    lastActivity: lastActivity(root: root, skipping: skip),
                                    artifacts: artifacts))
        }
        projects.sort { $0.size > $1.size }
        return projects
    }

    private static func classify(dir: String, siblings: Set<String>) -> ArtifactKind? {
        let name = Paths.name(dir)
        let gradle = siblings.contains { $0.hasPrefix("build.gradle") || $0.hasPrefix("settings.gradle") }
        switch name {
        case "node_modules":
            return siblings.contains("package.json") ? .nodeModules : nil
        case ".next", ".nuxt", ".svelte-kit", ".turbo", ".angular", ".parcel-cache":
            return siblings.contains("package.json") ? .jsCache : nil
        case "target":
            if siblings.contains("Cargo.toml") { return .rustTarget }
            if siblings.contains("pom.xml") { return .mavenTarget }
            if siblings.contains("build.sbt") { return .scalaTarget }
            return nil
        case "build":
            if gradle { return .gradleBuild }
            if siblings.contains("pubspec.yaml") { return .flutterBuild }
            if siblings.contains("CMakeLists.txt") { return .cmakeBuild }
            return nil
        case ".gradle":
            return gradle || siblings.contains("gradlew") ? .gradleCache : nil
        case ".venv", "venv":
            return FileManager.default.fileExists(atPath: dir + "/pyvenv.cfg") ? .pythonVenv : nil
        case "Pods":
            return siblings.contains("Podfile") ? .pods : nil
        case ".terraform":
            return siblings.contains { $0.hasSuffix(".tf") } ? .terraform : nil
        case ".dart_tool":
            return siblings.contains("pubspec.yaml") ? .dartTool : nil
        case "bin", "obj":
            return siblings.contains { $0.hasSuffix(".csproj") || $0.hasSuffix(".fsproj") } ? .dotnetBuild : nil
        default:
            return nil
        }
    }

    private static func describe(root: String, kinds: [ArtifactKind]) -> (String, String) {
        if kinds.contains(.rustTarget) { return ("Rust", "gearshape.2") }
        if kinds.contains(.mavenTarget) || kinds.contains(.gradleBuild) || kinds.contains(.gradleCache) {
            return ("Java / Kotlin", "cup.and.saucer")
        }
        if kinds.contains(.scalaTarget) { return ("Scala", "cup.and.saucer") }
        if kinds.contains(.flutterBuild) || kinds.contains(.dartTool) { return ("Flutter", "bird") }
        if kinds.contains(.pods) { return ("iOS", "iphone") }
        if kinds.contains(.pythonVenv) { return ("Python", "chevron.left.forwardslash.chevron.right") }
        if kinds.contains(.dotnetBuild) { return (".NET", "number") }
        if kinds.contains(.terraform) { return ("Terraform", "cloud") }
        if kinds.contains(.cmakeBuild) { return ("C / C++", "hammer") }
        return ("JavaScript", "curlybraces")
    }

    /// The newest change among the project's own files (and git activity), ignoring build folders.
    private static func lastActivity(root: String, skipping: Set<String>) -> Date {
        let fm = FileManager.default
        var newest = Date.distantPast
        let names = (try? fm.contentsOfDirectory(atPath: root)) ?? []
        for name in names where !skipping.contains(name) && name != ".DS_Store" {
            if let date = (try? fm.attributesOfItem(atPath: root + "/" + name))?[.modificationDate] as? Date,
               date > newest {
                newest = date
            }
        }
        for gitFile in [".git/index", ".git/HEAD", ".git/FETCH_HEAD"] {
            if let date = (try? fm.attributesOfItem(atPath: root + "/" + gitFile))?[.modificationDate] as? Date,
               date > newest {
                newest = date
            }
        }
        return newest
    }
}
