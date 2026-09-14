import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var app: AppState

    @State private var showScrubSheet = false
    @State private var showUnscrubSheet = false
    @State private var showKeysSheet = false
    @State private var showAboutSheet = false
    @State private var pendingReplace: DiscNode?
    @State private var pendingResize: Int?
    @State private var pendingImport: (tableIndex: Int, offset: UInt64)?

    var body: some View {
        VStack(spacing: 0) {
            infoBar
            Divider()
            VSplitView {
                DiscTreeView(pendingReplace: $pendingReplace, pendingResize: $pendingResize, pendingImport: $pendingImport)
                    .frame(minHeight: 200)
                LogPanelView()
                    .frame(minHeight: 100, idealHeight: 160)
            }
        }
        .toolbar { toolbarContent }
        .sheet(isPresented: $showScrubSheet) { ScrubSheet().environmentObject(app) }
        .sheet(isPresented: $showUnscrubSheet) { UnscrubSheet().environmentObject(app) }
        .sheet(isPresented: $showKeysSheet) { KeysView() }
        .sheet(isPresented: $showAboutSheet) { AboutView() }
        .sheet(isPresented: Binding(get: { pendingResize != nil }, set: { if !$0 { pendingResize = nil } })) {
            if let pendingResize {
                ResizePartitionSheet(partitionIndex: pendingResize).environmentObject(app)
            }
        }
        .sheet(isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })) {
            if let pendingImport {
                ImportPartitionSheet(initialTableIndex: pendingImport.tableIndex, initialOffset: pendingImport.offset)
                    .environmentObject(app)
            }
        }
        .onChange(of: pendingReplace) { _, newValue in
            guard let node = newValue else { return }
            PanelPresenter.openFile(configure: { $0.message = "Choose the replacement file for \"\(node.name)\"" }) { url in
                if let url { app.replace(node: node, withDataAt: url) }
                pendingReplace = nil
            }
        }
        .alert("Error", isPresented: Binding(get: { app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.errorMessage ?? "")
        }
        .navigationTitle(app.discURL?.lastPathComponent ?? "Wii Scrubber")
    }

    private var infoBar: some View {
        HStack {
            if let disc = app.wiiDisc {
                VStack(alignment: .leading, spacing: 2) {
                    Text(disc.gameTitle.isEmpty ? disc.gameID : disc.gameTitle).font(.headline)
                    Text("\(disc.gameID) - Disc \(disc.discNumber + 1), v\(disc.discVersion) - boot: \(disc.bootMode == 0 ? "auto" : String(UnicodeScalar(disc.bootMode)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                let used = disc.partitions.reduce(UInt64(0)) { $0 + $1.usedDataSize }
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Data size").font(.caption).foregroundStyle(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(used), countStyle: .binary)).font(.headline)
                }
            } else if let gc = app.gcDisc {
                Text("\(gc.gameTitle) [\(gc.gameID)] -- GameCube (read-only)").font(.headline)
                Spacer()
            } else {
                Text("No disc loaded").foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { openISO() } label: { Label("Open ISO", systemImage: "opticaldiscdrive") }
        }
        ToolbarItem { Button { showKeysSheet = true } label: { Label("Keys", systemImage: "key") } }
        ToolbarItem {
            Button { showScrubSheet = true } label: { Label("Clean and Save", systemImage: "sparkles") }
                .disabled(!app.isWiiDisc || app.isBusy)
        }
        ToolbarItem {
            Button { trimISO() } label: { Label("Trim ISO", systemImage: "scissors") }
                .disabled(!app.isWiiDisc || app.isBusy)
        }
        ToolbarItem {
            Button { showUnscrubSheet = true } label: { Label("Unscrub Image", systemImage: "arrow.uturn.backward") }
                .disabled(app.isBusy)
        }
        ToolbarItem {
            Button { showAboutSheet = true } label: { Label("About", systemImage: "info.circle") }
        }
    }

    private func openISO() {
        PanelPresenter.openFile(configure: {
            $0.allowedContentTypes = [UTType(filenameExtension: "iso") ?? .data]
            $0.allowsOtherFileTypes = true
        }) { url in
            guard let url else { return }
            app.openISO(url: url)
        }
    }

    private func trimISO() {
        let base = app.discURL?.deletingPathExtension().lastPathComponent ?? "disc"
        PanelPresenter.saveFile(configure: { $0.nameFieldStringValue = "\(base)-trimmed.iso" }) { url in
            guard let url else { return }
            app.trim(destinationURL: url)
        }
    }
}

#Preview {
    ContentView().environmentObject(AppState())
}
