import SwiftUI

extension View {
    /// Botão glass no macOS 26 (`.glass` / `.glassProminent`); `.bordered` / `.borderedProminent` antes.
    @ViewBuilder
    func adaptiveGlassButton(prominent: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *), !GlassSupport.forceFallback {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            fallbackButton(prominent: prominent)
        }
        #else
        fallbackButton(prominent: prominent)
        #endif
    }

    @ViewBuilder
    private func fallbackButton(prominent: Bool) -> some View {
        if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }
}
