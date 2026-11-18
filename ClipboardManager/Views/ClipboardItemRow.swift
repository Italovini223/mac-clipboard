import AppKit
import SwiftUI

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onFavoriteToggle: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var increasedContrast: Bool { contrast == .increased }

    var body: some View {
        HStack(spacing: 10) {
            typeBadge

            // Content preview
            VStack(alignment: .leading, spacing: 3) {
                if item.contentType == .image, let data = item.rawData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.thumbnailRadius, style: .continuous))
                } else {
                    Text(item.previewContent)
                        .font(item.contentType == .code
                              ? .system(size: 12, design: .monospaced)
                              : .system(size: 13))
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                }

                sourceLine
            }

            Spacer(minLength: 0)

            // Favorite indicator
            if item.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 11))
                    .accessibilityLabel("Favorite")
            }
        }
        .padding(.horizontal, Metrics.rowInset + 2)
        .padding(.vertical, Metrics.rowInset - 1)
        .background(rowBackground)
        .contentShape(RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous))
        .onHover { isHovering = $0 }
        .onTapGesture(count: 1) {
            Haptics.tap()
            onSelect()
        }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .contextMenu {
            Button(item.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                onFavoriteToggle()
            }
            Divider()
            Button("Copy", role: nil) { copyToClipboard() }
            Button("Delete", role: .destructive) {
                Haptics.destructive()
                onDelete()
            }
        }
    }

    // MARK: - Subviews

    /// Selo quadrado arredondado, tintado pelo tipo de conteúdo.
    private var typeBadge: some View {
        let tint = item.contentType.badgeColor
        return RoundedRectangle(cornerRadius: Metrics.badgeRadius, style: .continuous)
            .fill(tint.opacity(0.16))
            .frame(width: Metrics.badgeSize, height: Metrics.badgeSize)
            .overlay {
                Image(systemName: item.contentType.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .accessibilityLabel(item.contentType.label)
    }

    private var sourceLine: some View {
        HStack(spacing: 5) {
            if let app = item.sourceApp {
                if let icon = AppIconCache.shared.icon(for: app) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 12, height: 12)
                }
                Text(AppIconCache.shared.name(for: app))
                Text("·")
            }
            Text(item.relativeTime)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    /// Selecionada: retângulo arredondado inset com tint de acento (estado). Hover: preenchimento mais leve.
    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
        return ZStack {
            if isSelected {
                shape.fill(Color.accentColor.opacity(increasedContrast ? 0.30 : 0.18))
                shape.strokeBorder(Color.accentColor.opacity(increasedContrast ? 0.9 : 0.35),
                                   lineWidth: increasedContrast ? 1 : 0.5)
            } else if isHovering {
                shape.fill(Color.primary.opacity(0.06))
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: isSelected)
        .animation(reduceMotion ? nil : .snappy(duration: 0.12), value: isHovering)
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.content, forType: .string)
    }
}

private extension ClipboardItem.ContentType {
    /// Cor do selo por tipo: identifica a categoria, não é decoração do estado.
    var badgeColor: Color {
        switch self {
        case .text:  .gray
        case .url:   .blue
        case .image: .purple
        case .code:  .orange
        case .file:  .teal
        }
    }
}
