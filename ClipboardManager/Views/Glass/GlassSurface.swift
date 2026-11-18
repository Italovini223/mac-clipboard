import SwiftUI

/// Decide se o visual usa o glass nativo (macOS 26+) ou o fallback de material (macOS 14–25).
enum GlassSupport {
    /// Só em Debug: `-ForceMaterialFallback YES` nos argumentos de launch (ou a chave no UserDefaults)
    /// força o fallback para testá-lo no macOS 26.
    static var forceFallback: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "ForceMaterialFallback")
        #else
        false
        #endif
    }
}

struct GlassSurface: ViewModifier {
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var increasedContrast: Bool { contrast == .increased }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        // O conteúdo é recortado antes do glass para as linhas não vazarem pelos cantos.
        #if compiler(>=6.2)
        if #available(macOS 26, *), !GlassSupport.forceFallback, !reduceTransparency {
            content
                .clipShape(shape)
                .glassEffect(.regular, in: shape)
                .overlay {
                    // O glass já tem borda e sombra próprias; só reforça com Increase Contrast.
                    if increasedContrast {
                        shape.strokeBorder(Color.primary.opacity(0.45), lineWidth: 1)
                    }
                }
        } else {
            fallback(content, shape: shape)
        }
        #else
        fallback(content, shape: shape)
        #endif
    }

    /// Material com traço fino e sombra manual (o painel não tem sombra de janela).
    /// Com Reduce Transparency vira fundo sólido.
    private func fallback(_ content: Content, shape: RoundedRectangle) -> some View {
        content
            .clipShape(shape)
            .background {
                if reduceTransparency {
                    shape.fill(Color(nsColor: .windowBackgroundColor))
                } else {
                    shape.fill(.regularMaterial)
                }
            }
            .overlay {
                shape.strokeBorder(
                    Color.primary.opacity(increasedContrast ? 0.45 : 0.12),
                    lineWidth: increasedContrast ? 1 : 0.5
                )
            }
            .shadow(color: .black.opacity(0.30), radius: 16, y: 8)
    }
}

extension View {
    /// Superfície flutuante: glass nativo no macOS 26, material nos anteriores.
    func glassSurface(cornerRadius: CGFloat) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius))
    }
}
