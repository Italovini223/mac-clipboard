import AppKit

/// Feedback de trackpad. No Mac só existe em cliques (com o dedo no trackpad), nunca por teclado;
/// sem trackpad a chamada simplesmente não tem efeito.
@MainActor
enum Haptics {
    static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    static func selection() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    static func destructive() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
}
