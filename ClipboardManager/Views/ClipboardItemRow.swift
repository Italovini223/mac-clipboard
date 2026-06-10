import AppKit
import SwiftUI

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onFavoriteToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Type icon
            Image(systemName: item.contentType.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)

            // Content preview
            VStack(alignment: .leading, spacing: 2) {
                if item.contentType == .image, let data = item.rawData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 40)
                        .cornerRadius(4)
                } else {
                    Text(item.previewContent)
                        .font(.system(size: 13))
                        .lineLimit(2)
                        .foregroundStyle(isSelected ? .white : .primary)
                }

                HStack(spacing: 6) {
                    if let app = item.sourceApp {
                        Text(shortAppName(app))
                            .font(.system(size: 10))
                            .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                    }
                    Text(item.relativeTime)
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? .white.opacity(0.7) : .tertiary)
                }
            }

            Spacer()

            // Favorite indicator
            if item.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : .yellow)
                    .font(.system(size: 11))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentColor : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 1) { onSelect() }
        .contextMenu {
            Button(item.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                onFavoriteToggle()
            }
            Divider()
            Button("Copy", role: nil) { copyToClipboard() }
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.content, forType: .string)
    }

    private func shortAppName(_ bundleId: String) -> String {
        bundleId.components(separatedBy: ".").last?.capitalized ?? bundleId
    }
}
