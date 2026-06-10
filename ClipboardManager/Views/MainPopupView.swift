import SwiftUI

struct MainPopupView: View {
    @Bindable var viewModel: ClipboardViewModel
    var onClose: () -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.5)
            itemList
            if viewModel.items.isEmpty {
                emptyState
            }
        }
        .frame(width: 640)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        .onKeyPress(.upArrow)   { viewModel.moveSelection(by: -1); return .handled }
        .onKeyPress(.downArrow) { viewModel.moveSelection(by:  1); return .handled }
        .onKeyPress(.return) {
            if let item = viewModel.selectedItem {
                viewModel.selectItem(item)
                onClose()
            }
            return .handled
        }
        .onKeyPress(.escape) { onClose(); return .handled }
        .onAppear { searchFocused = true }
    }

    // MARK: - Subviews

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 15, weight: .medium))

            TextField("Search clipboard history…", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
                .submitLabel(.done)

            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }

            Text("\(viewModel.items.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                        ClipboardItemRow(
                            item: item,
                            isSelected: viewModel.selectedIndex == index,
                            onSelect: {
                                viewModel.selectItem(item)
                                onClose()
                            },
                            onFavoriteToggle: { viewModel.toggleFavorite(item) },
                            onDelete:         { viewModel.deleteItem(item) }
                        )
                        .id(index)

                        if index < viewModel.items.count - 1 {
                            Divider().padding(.leading, 38).opacity(0.4)
                        }
                    }
                }
            }
            .frame(maxHeight: 400)
            .onChange(of: viewModel.selectedIndex) { _, idx in
                withAnimation(.easeInOut(duration: 0.1)) {
                    proxy.scrollTo(idx, anchor: .center)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: viewModel.searchQuery.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.quaternary)
            Text(viewModel.searchQuery.isEmpty ? "No clipboard history yet" : "No results for "\(viewModel.searchQuery)"")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
