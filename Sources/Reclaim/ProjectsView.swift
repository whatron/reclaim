import AppKit
import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject var model: AppModel
    @State var idleOnly = false

    var body: some View {
        Group {
            switch model.projectsState {
            case .idle, .loading:
                ScanningState(symbol: "folder.badge.gearshape", tint: Palette.sand,
                              title: "Looking through your code",
                              status: model.projectsStatus.isEmpty ? "Starting…" : model.projectsStatus)
            case .loaded:
                if model.projects.isEmpty {
                    ContentUnavailableView {
                        Label("No build folders found", systemImage: "folder.badge.questionmark")
                    } description: {
                        Text("Reclaim looked for node_modules, target, build and .venv folders inside code projects in your home folder.")
                    } actions: {
                        Button("Scan Again") { model.loadProjects() }
                    }
                } else {
                    loaded
                }
            }
        }
        .navigationTitle("Projects")
        .task { model.loadProjectsIfNeeded() }
    }

    private var visible: [Project] {
        idleOnly ? model.projects.filter { $0.isStale } : model.projects
    }

    private var loaded: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: "Projects",
                           subtitle: "Dependencies and build output inside your code projects. All of it can be rebuilt; projects you haven't touched for a month are ticked.")

                ProjectStats()

                HStack {
                    Picker("Show", selection: $idleOnly) {
                        Text("All projects").tag(false)
                        Text("Idle for a month or more").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 340)
                    Spacer()
                    Button("Scan Again") { model.loadProjects() }
                }

                LazyVStack(spacing: 12) {
                    ForEach(visible) { project in
                        ProjectCard(project: project)
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 28)
            .padding(.bottom, 130)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .bottom) { ProjectsDock() }
    }
}

/// A calm placeholder while a long scan runs.
struct ScanningState: View {
    let symbol: String
    let tint: Color
    let title: String
    let status: String
    var progress: Double? = nil

    var body: some View {
        VStack(spacing: 18) {
            SymbolTile(symbol: symbol, tint: tint, size: 76)
                .symbolEffect(.pulse, options: .repeating)
            Text(title).font(.display(24, .bold))
            if let progress {
                ProgressView(value: progress)
                    .tint(tint)
                    .frame(width: 320)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            Text(status)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ProjectStats: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let total = model.projects.reduce(Int64(0)) { $0 + $1.size }
        let stale = model.staleProjects
        let staleBytes = stale.reduce(Int64(0)) { $0 + $1.size }
        let byKind = Dictionary(grouping: model.projects.flatMap { $0.artifacts }, by: { $0.kind })
            .mapValues { $0.reduce(Int64(0)) { $0 + $1.size } }
        let topKind = byKind.max { $0.value < $1.value }

        HStack(spacing: 14) {
            StatTile(value: Format.short(total), label: "rebuildable in \(model.projects.count) projects",
                     tint: Palette.sky, symbol: "hammer")
            StatTile(value: Format.short(staleBytes), label: "in \(stale.count) idle projects",
                     tint: Palette.sand, symbol: "moon.zzz")
            if let topKind {
                StatTile(value: Format.short(topKind.value), label: "of \(topKind.key.label)",
                         tint: Palette.violet, symbol: "shippingbox")
            }
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let tint: Color
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            SymbolTile(symbol: symbol, tint: tint, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.display(22, .heavy))
                    .monospacedDigit()
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}

struct ProjectCard: View {
    @EnvironmentObject var model: AppModel
    let project: Project

    private var allPaths: Set<String> { Set(project.artifacts.map(\.path)) }
    private var allTicked: Bool { allPaths.isSubset(of: model.checkedArtifacts) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                RoundCheck(isOn: allTicked, tint: Palette.sand)
                SymbolTile(symbol: project.symbol, tint: project.isStale ? Palette.sand : Palette.sky, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(project.name).font(.headline)
                        Pill(text: project.ecosystem, tint: .secondary)
                        if project.isStale {
                            Pill(text: "Idle \(idleText)", tint: Palette.sand, symbol: "moon.zzz")
                        }
                    }
                    Text("\(Paths.tilde(project.path))  ·  last change \(Format.ago(project.lastActivity))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 12)
                Text(Format.bytes(project.size))
                    .font(.display(18, .bold))
                    .monospacedDigit()
            }
            .padding(14)
            .contentShape(Rectangle())
            .onTapGesture { toggleAll() }

            Divider().padding(.leading, 82)

            VStack(spacing: 0) {
                ForEach(project.artifacts) { artifact in
                    ArtifactRow(artifact: artifact)
                }
            }
            .padding(.vertical, 4)
        }
        .card(padding: 0)
        .contextMenu {
            Button("Show in Finder") { model.reveal(project.path) }
            Button("Show in Space Map") { model.openInMap(project.path) }
        }
    }

    private var idleText: String {
        let days = project.idleDays
        if days >= 365 { return "\(days / 365) year\(days >= 730 ? "s" : "")" }
        if days >= 60 { return "\(days / 30) months" }
        return "\(days) days"
    }

    private func toggleAll() {
        withAnimation(.snappy(duration: 0.2)) {
            if allTicked {
                model.checkedArtifacts.subtract(allPaths)
            } else {
                model.checkedArtifacts.formUnion(allPaths)
            }
        }
    }
}

struct ArtifactRow: View {
    @EnvironmentObject var model: AppModel
    let artifact: ProjectArtifact
    @State var hovering = false

    var body: some View {
        let isOn = model.checkedArtifacts.contains(artifact.path)
        HStack(spacing: 12) {
            RoundCheck(isOn: isOn, tint: Palette.sand)
                .scaleEffect(0.85)
            VStack(alignment: .leading, spacing: 2) {
                Text(artifact.name)
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                Text(artifact.kind.label == artifact.name ? "Rebuild with \(artifact.kind.rebuild)."
                     : "\(artifact.kind.label). Rebuild with \(artifact.kind.rebuild).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Format.bytes(artifact.size))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 7)
        .padding(.leading, 50)
        .padding(.trailing, 14)
        .background(Color.primary.opacity(hovering ? 0.04 : 0))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if isOn {
                model.checkedArtifacts.remove(artifact.path)
            } else {
                model.checkedArtifacts.insert(artifact.path)
            }
        }
        .contextMenu {
            Button("Show in Finder") { model.reveal(artifact.path) }
        }
    }
}

struct ProjectsDock: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let count = model.checkedArtifacts.count
        let bytes = model.checkedArtifactBytes
        ActionDock {
            VStack(alignment: .leading, spacing: 2) {
                Text(count == 0 ? "Nothing ticked" : "\(count) folder\(count == 1 ? "" : "s") ticked")
                    .font(.headline)
                Text("They go to the Trash. Rebuild any of them later with the command shown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 20)
            Button("Tick Idle Projects") {
                withAnimation(.snappy) {
                    model.checkedArtifacts = Set(model.staleProjects.flatMap { $0.artifacts.map(\.path) })
                }
            }
            .disabled(model.staleProjects.isEmpty)
            Button("Untick All") {
                withAnimation(.snappy) { model.checkedArtifacts.removeAll() }
            }
            .disabled(count == 0)
            Button {
                model.requestTrashArtifacts()
            } label: {
                Label(bytes > 0 ? "Move \(Format.short(bytes)) to Trash" : "Move to Trash", systemImage: "trash")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.sand)
            .controlSize(.large)
            .disabled(count == 0)
        }
    }
}
