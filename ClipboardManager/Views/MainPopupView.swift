import SwiftUI

struct MainPopupView: View {
    @Bindable var viewModel: ClipboardViewModel
    var onClose: () -> Void

    @FocusState private var searchFocused: Bool
    @State private var showingClearConfirmation = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            itemList
            if viewModel.items.isEmpty {
                emptyState
            } else {
                Divider().opacity(0.5).padding(.horizontal, Metrics.panelInset)
                footer
            }
        }
        .frame(width: Metrics.panelWidth)
        // O glass desenha a própria borda e sombra; nada de overlay/shadow manual aqui.
        .glassSurface(cornerRadius: Metrics.panelRadius)
        // Margem transparente para a sombra/refração do glass não serem cortadas pela janela.
        .padding(Metrics.panelOuterMargin)
        // Ancorado no topo: a busca não "pula" quando a lista encolhe ao filtrar.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        // Re-focuses the search field on every open (onAppear fires only on first render)
        .task(id: viewModel.popupOpenCount) {
            searchFocused = true
        }
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
                .accessibilityLabel("Clear search")
                .transition(.scale.combined(with: .opacity))
            }

            Text("\(viewModel.items.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.08), in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        // Campo plano (sem glass dentro do glass), com raio concêntrico ao do painel.
        .background(.quaternary, in: RoundedRectangle(cornerRadius: Metrics.innerRadius, style: .continuous))
        .padding(Metrics.panelInset)
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 2) {
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
                        // Use the stable database ID — not the position index — so SwiftUI
                        // correctly identifies each row when the list is reordered or prepended.
                        .id(item.id)
                    }
                }
                .padding(.horizontal, Metrics.rowInset)
                .padding(.vertical, Metrics.spaceXS)
            }
            .frame(maxHeight: Metrics.listMaxHeight)
            .onChange(of: viewModel.selectedIndex) { _, idx in
                guard viewModel.items.indices.contains(idx) else { return }
                if reduceMotion {
                    proxy.scrollTo(viewModel.items[idx].id, anchor: .center)
                } else {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        proxy.scrollTo(viewModel.items[idx].id, anchor: .center)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            keyHint("↩", "Paste")
            keyHint("↑↓", "Navigate")
            keyHint("esc", "Close")

            Spacer()

            // Um único elemento glass no rodapé: não precisa de GlassEffectContainer.
            Button {
                showingClearConfirmation = true
            } label: {
                Label("Clear History", systemImage: "trash")
                    .font(.system(size: 11))
            }
            .adaptiveGlassButton()
            .controlSize(.small)
        }
        .padding(.horizontal, Metrics.spaceM + 2)
        .padding(.vertical, Metrics.spaceS)
        .alert("Clear Clipboard History?", isPresented: $showingClearConfirmation) {
            Button("Clear", role: .destructive) {
                Haptics.destructive()
                viewModel.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Favorited items will not be removed.")
        }
    }

    /// Dica de teclado estilo Spotlight: tecla em keycap + rótulo.
    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .frame(minWidth: 18)
                .background(Color.primary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: Metrics.keycapRadius / 2, style: .continuous))
            Text(label)
                .font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: viewModel.searchQuery.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 30))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text(viewModel.searchQuery.isEmpty ? "No clipboard history yet" : "No results for \"\(viewModel.searchQuery)\"")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
