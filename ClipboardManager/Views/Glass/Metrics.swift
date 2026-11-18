import CoreGraphics

/// Medidas compartilhadas do visual glass.
/// Regra de concentricidade: raio interno = raio externo − recuo entre as duas formas
/// (campo de busca dentro do painel: `innerRadius`; miniatura dentro da linha: `thumbnailRadius`).
enum Metrics {
    // Painel (card glass)
    static let panelWidth: CGFloat = 640
    /// Altura máxima do card: busca + lista (400) + rodapé, com folga.
    static let cardMaxHeight: CGFloat = 500
    static let panelRadius: CGFloat = 26
    static let panelInset: CGFloat = 10
    static let innerRadius: CGFloat = panelRadius - panelInset

    /// Margem transparente ao redor do card para a sombra/refração do glass não serem cortadas.
    static let panelOuterMargin: CGFloat = 24

    /// Tamanho da janela (NSPanel): card + margem. Única fonte para `createPanel` e `positionPanel`.
    static let panelSize = CGSize(
        width: panelWidth + panelOuterMargin * 2,
        height: cardMaxHeight + panelOuterMargin * 2
    )

    // Linhas da lista
    static let listMaxHeight: CGFloat = 400
    static let rowRadius: CGFloat = 12
    static let rowInset: CGFloat = 8
    static let thumbnailRadius: CGFloat = rowRadius - rowInset
    static let badgeSize: CGFloat = 28
    static let badgeRadius: CGFloat = 8

    // Teclas (keycaps) e demais controles pequenos
    static let keycapRadius: CGFloat = 8

    // Espaçamentos
    static let spaceXS: CGFloat = 4
    static let spaceS: CGFloat = 8
    static let spaceM: CGFloat = 12
}
