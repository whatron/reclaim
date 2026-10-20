import AppKit
import SwiftUI

// MARK: - Large files

enum FileSort: String, CaseIterable, Identifiable {
    case size, idle
    var id: String { rawValue }
    var label: String { self == .size ? "Biggest first" : "Longest unopened" }
}

struct LargeFilesView: View {
    @EnvironmentObject var model: AppModel
    @State var category: FileCategory = .all
    @State var sort: FileSort = .size
    @State var picked: Set<String> = []

    var body: some View {
        Group {
            switch model.largeState {
            case .idle, .loading:
                ScanningState(symbol: "doc.text.magnifyingglass", tint: Palette.sky,
                              title: "Finding large files", status: "Asking Spotlight for files over 100 MB…")
            case .loaded:
                if model.large.isEmpty {
                    ContentUnavailableView {
                        Label("No files over 100 MB", systemImage: "checkmark.seal")
                    } description: {
                        Text("Your space is spread across many smaller files. The Space Map is the better place to look.")
                    } actions: {
                        Button("Open Space Map") { model.openInMap(Paths.home) }
                    }
                } else {
                    loaded
                }
            }
        }
        .navigationTitle("Large Files")
        .task { model.loadLargeIfNeeded() }
    }

    private var files: [LargeFile] {
        let list = category == .all ? model.large : model.large.filter { $0.category == category }
        switch sort {
        case .size: return list
        case .idle: return list.sorted { $0.idleDays > $1.idleDays }
        }
    }

    private var loaded: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "Large Files",
                           subtitle: "Every file over 100 MB in your home folder, with when you last opened it. Old installers and long-forgotten videos are the usual suspects.")

                CategoryChips(selection: $category)

                HStack {
                    Picker("Sort", selection: $sort) {
                        ForEach(FileSort.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 300)
                    Spacer()
                    let stale = files.filter { $0.idleDays > 180 && !$0.isProtected }
                    Button("Tick Unopened for 6 Months") {
                        withAnimation(.snappy) { picked.formUnion(stale.map(\.path)) }
                    }
                    .disabled(stale.isEmpty)
                }

                LazyVStack(spacing: 2) {
                    ForEach(files) { file in
                        LargeFileRow(file: file, isOn: picked.contains(file.path)) {
                            if picked.contains(file.path) { picked.remove(file.path) } else { picked.insert(file.path) }
                        }
                    }
                }
                .padding(6)
                .card(padding: 0)
            }
            .padding(.horizontal, 36)
            .padding(.top, 28)
            .padding(.bottom, 130)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .bottom) { dock }
        .onChange(of: model.large) { _, newValue in
            picked.formIntersection(Set(newValue.map(\.path)))
        }
    }

    private var dock: some View {
        let chosen = model.large.filter { picked.contains($0.path) }
        let bytes = chosen.reduce(Int64(0)) { $0 + $1.size }
        return ActionDock {
            VStack(alignment: .leading, spacing: 2) {
                Text(chosen.isEmpty ? "Tick files to remove them" : "\(chosen.count) file\(chosen.count == 1 ? "" : "s") ticked")
                    .font(.headline)
                Text("\(model.large.count) large files, \(Format.short(model.large.reduce(Int64(0)) { $0 + $1.size })) in total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 20)
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(chosen.map { URL(fileURLWithPath: $0.path) })
            }
            .disabled(chosen.isEmpty)
            Button {
                model.requestTrash(chosen.map { TrashItem(path: $0.path, name: $0.name, size: $0.size) })
            } label: {
                Label(bytes > 0 ? "Move \(Format.short(bytes)) to Trash" : "Move to Trash", systemImage: "trash")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.sky)
            .controlSize(.large)
            .disabled(chosen.isEmpty)
        }
    }
}

struct CategoryChips: View {
    @EnvironmentObject var model: AppModel
    @Binding var selection: FileCategory

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FileCategory.allCases) { cat in
                    let list = cat == .all ? model.large : model.large.filter { $0.category == cat }
                    if !list.isEmpty || cat == .all {
                        let isOn = selection == cat
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { selection = cat }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: cat.symbol)
                                Text(cat.label)
                                Text(Format.short(list.reduce(Int64(0)) { $0 + $1.size }))
                                    .foregroundStyle(isOn ? Color.white.opacity(0.8) : Color.secondary)
                                    .monospacedDigit()
                            }
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(isOn ? Color.white : Color.primary)
                            .background(Capsule().fill(isOn ? AnyShapeStyle(Palette.sky) : AnyShapeStyle(Color.primary.opacity(0.06))))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct LargeFileRow: View {
    @EnvironmentObject var model: AppModel
    let file: LargeFile
    let isOn: Bool
    let toggle: () -> Void
    @State var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            RoundCheck(isOn: isOn, tint: Palette.sky)
                .opacity(file.isProtected ? 0.25 : 1)
            Image(nsImage: Icons.icon(file.path))
                .resizable()
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(file.name)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if file.idleDays > 365 {
                        Pill(text: "Unopened for \(file.idleDays / 365)+ yr", tint: Palette.sand, symbol: "moon.zzz")
                    }
                }
                Text("\(Paths.tilde(file.folder))  ·  \(opened)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let note = file.smartNote {
                    Label(note, systemImage: "lightbulb")
                        .font(.caption)
                        .foregroundStyle(Palette.mint)
                }
            }
            Spacer(minLength: 12)
            Text(Format.bytes(file.size))
                .font(.display(16, .bold))
                .monospacedDigit()
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(isOn ? 0.06 : (hovering ? 0.035 : 0))))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if !file.isProtected { toggle() } }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(URL(fileURLWithPath: file.path)) }
            Button("Show in Finder") { model.reveal(file.path) }
            Button("Show in Space Map") { model.openInMap(file.folder) }
        }
    }

    private var opened: String {
        if let used = file.lastUsed { return "opened \(Format.ago(used))" }
        if file.modified > Format.trustworthyDate { return "never opened, changed \(Format.ago(file.modified))" }
        return "never opened"
    }
}

// MARK: - Duplicates

struct DuplicatesView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            switch model.dupesState {
            case .idle:
                intro
            case .loading:
                ScanningState(symbol: "square.on.square", tint: Palette.violet, title: "Comparing files",
                              status: model.dupesStatus, progress: model.dupesProgress)
            case .loaded:
                if model.dupes.isEmpty {
                    ContentUnavailableView {
                        Label("No duplicates over 20 MB", systemImage: "checkmark.seal")
                    } description: {
                        Text("Every big file in your home folder is one of a kind.")
                    } actions: {
                        Button("Scan Again") { model.findDuplicates() }
                    }
                } else {
                    loaded
                }
            }
        }
        .navigationTitle("Duplicates")
    }

    private var intro: some View {
        VStack(spacing: 18) {
            SymbolTile(symbol: "square.on.square", tint: Palette.violet, size: 76)
            Text("Find identical files").font(.display(26, .bold))
            Text("Reclaim compares files over 20 MB by their contents, not their names, so only true copies show up. For each set it suggests keeping the copy outside Downloads with the cleanest name.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 500)
            Button {
                model.findDuplicates()
            } label: {
                Label("Find Duplicates", systemImage: "magnifyingglass")
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.violet)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loaded: some View {
        let extra = model.dupes.reduce(Int64(0)) { $0 + $1.reclaimable }
        let copies = model.dupes.reduce(0) { $0 + $1.extras.count }
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "Duplicates",
                           subtitle: "\(Format.short(extra)) is taken up by \(copies) extra cop\(copies == 1 ? "y" : "ies") of files you already have. The copy marked Keep stays put.")
                HStack {
                    Spacer()
                    Button("Scan Again") { model.findDuplicates() }
                }
                LazyVStack(spacing: 12) {
                    ForEach(model.dupes) { group in
                        DuplicateCard(group: group)
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 28)
            .padding(.bottom, 130)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .bottom) { dock }
    }

    private var dock: some View {
        let count = model.dupes.reduce(0) { sum, g in sum + g.files.filter { model.checkedDupes.contains($0.path) }.count }
        let bytes = model.checkedDupeBytes
        return ActionDock {
            VStack(alignment: .leading, spacing: 2) {
                Text(count == 0 ? "Nothing ticked" : "\(count) cop\(count == 1 ? "y" : "ies") ticked")
                    .font(.headline)
                Text("Reclaim always leaves at least one copy of every file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 20)
            Button("Tick All Extras") {
                withAnimation(.snappy) {
                    model.checkedDupes = Set(model.dupes.flatMap { $0.extras.map(\.path) })
                }
            }
            Button {
                model.requestTrashDupes()
            } label: {
                Label(bytes > 0 ? "Move \(Format.short(bytes)) to Trash" : "Move to Trash", systemImage: "trash")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.violet)
            .controlSize(.large)
            .disabled(count == 0)
        }
    }
}

struct DuplicateCard: View {
    @EnvironmentObject var model: AppModel
    let group: DuplicateGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                if let first = group.files.first {
                    Image(nsImage: Icons.icon(first.path))
                        .resizable()
                        .frame(width: 38, height: 38)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.keeper?.name ?? "Duplicate")
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(group.files.count) identical copies, \(Format.bytes(group.size)) each")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Format.bytes(group.reclaimable))
                        .font(.display(17, .bold))
                        .monospacedDigit()
                    Text("reclaimable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)

            Divider().padding(.leading, 66)

            ForEach(Array(group.files.enumerated()), id: \.element.id) { index, file in
                let isOn = model.checkedDupes.contains(file.path)
                HStack(spacing: 12) {
                    RoundCheck(isOn: isOn, tint: Palette.violet)
                        .scaleEffect(0.85)
                    if index == 0 {
                        Pill(text: "Keep", tint: Palette.mint, symbol: "star.fill")
                    }
                    Text(Paths.tilde(file.path))
                        .font(.system(.callout, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text("Added \(Format.ago(file.created))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 7)
                .padding(.leading, 50)
                .padding(.trailing, 14)
                .contentShape(Rectangle())
                .onTapGesture {
                    if isOn { model.checkedDupes.remove(file.path) } else { model.checkedDupes.insert(file.path) }
                }
                .contextMenu {
                    Button("Open") { NSWorkspace.shared.open(URL(fileURLWithPath: file.path)) }
                    Button("Show in Finder") { model.reveal(file.path) }
                }
            }
            .padding(.bottom, 4)
        }
        .card(padding: 0)
    }
}
