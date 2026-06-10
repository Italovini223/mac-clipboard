# Clipboard Manager

Gerenciador de área de transferência nativo para macOS, construído com Swift 6 + SwiftUI. Roda como app de barra de menus com popup estilo Spotlight, histórico persistente em SQLite e acesso via atalho global de teclado.

---

## Instalação

### Opção 1 — Via curl (recomendado)

Cole no Terminal e pressione Enter:

```bash
curl -fsSL https://raw.githubusercontent.com/SEU_USUARIO/SEU_REPOSITORIO/main/install.sh | bash
```

O script faz tudo automaticamente:

1. Verifica macOS 14+
2. Consulta a API do GitHub para obter a versão mais recente
3. Baixa o `.zip` com o binário universal (arm64 + x86_64)
4. Instala o app em `/Applications`
5. Remove o atributo de quarentena do Gatekeeper
6. Oferece abrir o app na hora

Após a instalação, o app aparece na barra de menus. Use **⌥V** para abrir o histórico.

---

### Opção 2 — Download manual

1. Acesse a página de [Releases](https://github.com/SEU_USUARIO/SEU_REPOSITORIO/releases/latest)
2. Baixe o arquivo `ClipboardManager-vX.X.X-universal.zip`
3. Extraia o `.zip` — você verá `Clipboard Manager.app`
4. Arraste para `/Applications`
5. No Terminal, remova a quarentena:
   ```bash
   xattr -dr com.apple.quarantine "/Applications/Clipboard Manager.app"
   ```
6. Abra o app normalmente

> **Por que preciso remover a quarentena?**  
> O app não é notarizado pela Apple (requer conta paga no Apple Developer Program).  
> O `xattr -dr` remove o bloqueio do Gatekeeper localmente — nenhum dado é enviado para nenhum servidor.

---

### Opção 3 — Build a partir do código-fonte

Para desenvolvedores que queiram compilar o projeto localmente.

**Pré-requisitos:**

| Ferramenta | Versão mínima | Como instalar |
|---|---|---|
| macOS | 14.0 (Sonoma) | — |
| Xcode | 15.2 | Mac App Store |
| XcodeGen | qualquer | `brew install xcodegen` |
| Homebrew | qualquer | [brew.sh](https://brew.sh) |

**Passo a passo:**

```bash
# 1. Clone o repositório
git clone https://github.com/SEU_USUARIO/SEU_REPOSITORIO.git
cd SEU_REPOSITORIO

# 2. Gere o projeto Xcode (baixa dependências SPM automaticamente)
./generate.sh

# 3. Abra no Xcode
open ClipboardManager.xcodeproj
```

Dentro do Xcode:

1. Selecione o scheme **ClipboardManager** (canto superior esquerdo)
2. Vá em **Signing & Capabilities** e escolha seu **Development Team**
3. Pressione **⌘R** para compilar e executar
4. Na primeira execução, conceda permissão de **Acessibilidade** quando solicitado:  
   `Ajustes do Sistema → Privacidade e Segurança → Acessibilidade`

---

### Após a instalação

| Ação | Como fazer |
|---|---|
| Abrir histórico | **⌥V** (Option + V) em qualquer app |
| Navegar pelos itens | Setas ↑ ↓ |
| Selecionar e colar | Enter |
| Pesquisar | Digite diretamente no popup |
| Fechar sem colar | Esc |
| Menu de opções | Clique no ícone na barra de menus |
| Configurações | Barra de menus → Settings… ou **⌘,** |

---

### Desinstalar

```bash
# Remove o app
rm -rf "/Applications/Clipboard Manager.app"

# Remove o histórico e configurações (opcional)
rm -rf ~/Library/Application\ Support/ClipboardManager
rm -rf ~/Library/Preferences/com.weethub.ClipboardManager.plist
```

---

## Funcionalidades

- **⌥V** — abre o popup em qualquer app, pesquisa instantânea, navegação por teclado
- **Histórico persistente** — SQLite com busca full-text (FTS5), sobrevive a reinicializações
- **Favoritos** — fixe itens importantes; nunca são removidos automaticamente
- **Filtro inteligente** — ignora tokens JWT, chaves de API e conteúdo de gerenciadores de senhas
- **Auto-paste** — ao selecionar um item, ele é copiado e colado automaticamente no app anterior
- **Barra de menus** — acesso rápido ao histórico, limpeza e configurações
- **Privacidade total** — 100% local, zero telemetria, zero rede

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15.2+ *(only needed to build from source)*
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) *(only needed to build from source)*

## Architecture

```
MVVM · Swift 6 strict concurrency · SwiftUI + AppKit

ClipboardManagerApp (@main)
  └── AppDelegate                    wires all services, owns status item
       ├── ClipboardMonitor          polls NSPasteboard every 0.5 s
       ├── StorageService            GRDB facade over SQLite
       ├── HotkeyService             Carbon RegisterEventHotKey (no Accessibility needed)
       ├── ClipboardViewModel        @Observable, bridges services → Views
       └── PopupWindowController     NSPanel (floating, non-activating)
            └── MainPopupView        Spotlight-style SwiftUI UI
```

## Project Structure

```
ClipboardManager/
├── App/                    Entry point + AppDelegate
├── Models/                 ClipboardItem, Settings
├── Services/               ClipboardMonitor, StorageService, HotkeyService, AccessibilityService
├── ViewModels/             ClipboardViewModel
├── Views/                  MainPopupView, ClipboardItemRow, MenuBarView, SettingsView
├── Windows/                PopupWindowController (NSPanel)
├── Persistence/            SQLiteManager (GRDB + migrations)
└── Resources/              Info.plist, Entitlements, LaunchAgent, Assets
```

## Database

SQLite at `~/Library/Application Support/ClipboardManager/clipboard.db`

```sql
clipboard_history  -- main table (id, content, content_type, source_app, created_at, is_favorite, raw_data)
clipboard_fts      -- FTS5 virtual table, auto-synced with triggers
```

## Hotkey

Default: **⌥V** (Option + V)

Registered via Carbon `RegisterEventHotKey` — works without Accessibility permission, works in all spaces and full-screen apps.

## Auto-paste

When an item is selected, the app:
1. Writes the content to `NSPasteboard`
2. Dismisses the popup (re-activating the previous app)
3. Waits 200 ms
4. Sends a ⌘V `CGEvent` to the session event tap

Requires **Accessibility** permission (System Settings → Privacy & Security → Accessibility).

## Privacy

The app never contacts external servers. All clipboard data stays in `~/Library/Application Support/ClipboardManager/`. Items from apps in the ignore list (e.g. 1Password, Bitwarden) are never stored. Content matching JWT/API-key patterns is automatically skipped.

## Distribution

### Developer ID (direct distribution)

```bash
# Archive in Xcode: Product → Archive
# Then notarize:
xcrun notarytool submit ClipboardManager.xcarchive \
  --apple-id your@email.com \
  --team-id YOURTEAMID \
  --password "@keychain:notarytool-password" \
  --wait
xcrun stapler staple "Clipboard Manager.app"
```

### App Sandbox note

The app runs **without** the App Sandbox (`com.apple.security.app-sandbox = false`). This is required for:
- `RegisterEventHotKey` (global hotkeys)
- `CGEvent.post` (auto-paste simulation)

This makes App Store distribution unavailable. Use Developer ID notarization for Gatekeeper bypass.

## Development Phases

| Phase | Status | Features |
|-------|--------|---------|
| 1 | ✅ Complete | Monitor, history, FTS search, popup, hotkey, auto-paste |
| 2 | Planned | Favorites UI, settings, menu bar improvements |
| 3 | Planned | OCR (Vision), snippets, iCloud sync |
