import SwiftUI
import UniformTypeIdentifiers
import AppKit

// =====================================================
// MARK: - FileShelfPanelView
// [TAG: FILE_SHELF_PANEL]
// =====================================================

struct FileShelfPanelView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var shelfStore: FileShelfStore

    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 10) {
            header

            if shelfStore.items.isEmpty {
                emptyState
            } else {
                itemsList
            }
        }
        .padding(12)
        .frame(minWidth: 380, idealWidth: 420, maxWidth: 520, minHeight: 220, idealHeight: 280)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isDropTargeted ? appState.accentColor.opacity(0.72) : Color.white.opacity(0.12), lineWidth: 1)
        )
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted, perform: handleDrop)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.full")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(appState.accentColor)

            Text("File Shelf")
                .font(.system(size: 14, weight: .semibold, design: .rounded))

            Text("\(shelfStore.items.count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.08)))

            Spacer(minLength: 0)

            Button {
                shelfStore.clearAll()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(shelfStore.items.isEmpty)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            Image(systemName: isDropTargeted ? "tray.and.arrow.down.fill" : "tray")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(isDropTargeted ? appState.accentColor : .secondary)

            Text("Drop files here")
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            Text("Park files temporarily and drag them back out later.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }

    private var itemsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(shelfStore.items) { item in
                    FileShelfItemCard(item: item)
                        .environmentObject(shelfStore)
                        .environmentObject(appState)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let supported = providers.filter {
            $0.canLoadObject(ofClass: URL.self) || $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }

        guard supported.isEmpty == false else { return false }
        shelfStore.addItemProviders(supported)
        return true
    }
}

// =====================================================
// MARK: - FileShelfItemCard
// [TAG: FILE_SHELF_ITEM_CARD]
// =====================================================

private struct FileShelfItemCard: View {
    @EnvironmentObject var shelfStore: FileShelfStore
    @EnvironmentObject var appState: AppState

    let item: FileShelfStore.ShelfItem

    @State private var hovering = false

    private var resolvedURL: URL? {
        shelfStore.resolvedURL(for: item)
    }

    private var isAvailable: Bool {
        shelfStore.isAvailable(item)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: shelfStore.icon(for: item))
                .resizable()
                .frame(width: 30, height: 30)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                Text(item.originalPath)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if isAvailable == false {
                    Text("Unavailable")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    shelfStore.remove(itemID: item.id)
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove from shelf")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hovering ? Color.white.opacity(0.09) : Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(appState.accentColor.opacity(hovering ? 0.35 : 0.12), lineWidth: 0.9)
        )
        .onHover { over in
            withAnimation(.easeOut(duration: 0.12)) {
                hovering = over
            }
        }
        .onDrag {
            guard let url = resolvedURL else {
                return NSItemProvider()
            }
            return NSItemProvider(object: url as NSURL)
        }
        .onTapGesture(count: 2) {
            guard let url = resolvedURL else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        .contextMenu {
            Button("Reveal in Finder") {
                guard let url = resolvedURL else { return }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }

            Button(role: .destructive) {
                shelfStore.remove(itemID: item.id)
            } label: {
                Text("Remove from Shelf")
            }
        }
    }
}
