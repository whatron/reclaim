import AppKit
import SwiftUI

// MARK: - Large files

struct LargeFilesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection = Set<LargeFile.ID>()

    var body: some View {
        Group {
            switch model.largeState {
            case .idle, .loading:
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Searching with Spotlight…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                if model.large.isEmpty {
                    ContentUnavailableView {
                        Label("No files over 500 MB", systemImage: "checkmark.circle")
                    } description: {
                        Text("Your space is spread across many smaller files. Explore is the better place to look.")
                    } actions: {
                        Button("Open Explore") { model.section = .explore }
                    }
                } else {
                    table
                }
            }
        }
        .navigationTitle("Large Files")
        .navigationSubtitle("Single files over 500 MB in your home folder")
        .task { model.loadLargeIfNeeded() }
    }

    private var selectedFiles: [LargeFile] {
        model.large.filter { selection.contains($0.id) }
    }

    private var table: some View {
        Table(model.large, selection: $selection) {
            TableColumn("Name") { (file: LargeFile) in
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                        .resizable()
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(file.name).lineLimit(1)
                        Text(Paths.tilde(file.folder))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(.vertical, 3)
            }
            TableColumn("Size") { (file: LargeFile) in
                Text(Format.bytes(file.size))
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .width(min: 80, ideal: 100, max: 140)
            TableColumn("Modified") { (file: LargeFile) in
                Text(file.modified, format: .relative(presentation: .named))
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 150, max: 220)
        }
        .contextMenu(forSelectionType: LargeFile.ID.self) { ids in
            Button("Show in Finder") {
                for id in ids { model.reveal(id) }
            }
            Button("Move to Trash") {
                let items = model.large.filter { ids.contains($0.id) }
                    .map { TrashItem(path: $0.path, name: $0.name, size: $0.size) }
                model.requestTrash(items)
            }
        } primaryAction: { ids in
            for id in ids { model.reveal(id) }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                let files = selectedFiles
                if files.isEmpty {
                    Text("\(model.large.count) files, \(Format.bytes(model.large.reduce(Int64(0)) { $0 + $1.size })) in total")
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(files.count) selected, \(Format.bytes(files.reduce(Int64(0)) { $0 + $1.size }))")
                }
                Spacer()
                Button("Show in Finder") {
                    for f in files { model.reveal(f.path) }
                }
                .disabled(files.isEmpty)
                Button("Move to Trash", role: .destructive) {
                    model.requestTrash(files.map { TrashItem(path: $0.path, name: $0.name, size: $0.size) })
                }
                .disabled(files.isEmpty || files.allSatisfy { $0.isProtected })
                .keyboardShortcut(.delete, modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }
}

// MARK: - Activity

struct ActivityView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.log.isEmpty {
                ContentUnavailableView("Nothing yet",
                                       systemImage: "clock.arrow.circlepath",
                                       description: Text("Cleanups you run show up here, with the output of each command."))
            } else {
                List {
                    ForEach(Array(model.log.reversed())) { entry in
                        LogRow(entry: entry)
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Activity")
    }
}

struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        if entry.output.isEmpty {
            header
                .padding(.vertical, 4)
        } else {
            DisclosureGroup {
                Text(entry.output)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            } label: {
                header
            }
            .padding(.vertical, 4)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: entry.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(entry.ok ? Palette.safe : Palette.careful)
            Text(entry.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Text(entry.date, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
