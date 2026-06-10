# Clipboard Manager — Contexto para Agentes

## O que é este projeto

App nativo macOS de gerenciamento de área de transferência (clipboard manager), similar ao Maccy e Paste. Roda exclusivamente na barra de menus (sem ícone no Dock), monitora o `NSPasteboard` continuamente, persiste o histórico em SQLite e expõe um popup estilo Spotlight via atalho global **⌥V**.

Código 100% local — sem rede, sem telemetria, sem dependência de serviços externos.

---

## Stack

| Camada | Tecnologia |
|---|---|
| Linguagem | Swift 6.0, concorrência estrita (`SWIFT_STRICT_CONCURRENCY: complete`) |
| UI | SwiftUI + AppKit |
| Banco de dados | SQLite via **GRDB.swift 6.29+** (SPM) |
| Hotkey global | Carbon `RegisterEventHotKey` (sem Accessibility) |
| Auto-paste | `CGEvent.post` (requer Accessibility) |
| Observabilidade | `@Observable` (macOS 14 API — não usar `ObservableObject`) |
| Build | XcodeGen → `project.yml` → `ClipboardManager.xcodeproj` |
| CI/CD | GitHub Actions (`.github/workflows/release.yml`), dispara em `git tag v*` |
| Distribuição | GitHub Releases + `install.sh` (curl \| bash) |
| Mínimo | macOS 14.0 (Sonoma) |

---

## Como gerar e compilar

```bash
# Gera o .xcodeproj a partir do project.yml
./generate.sh          # instala xcodegen se necessário

open ClipboardManager.xcodeproj
# Xcode → Signing & Capabilities → definir Development Team → ⌘R
```

O `.xcodeproj` **não é commitado** — sempre gerado pelo XcodeGen.

---

## Estrutura de arquivos

```
ClipboardManager/
├── App/
│   ├── ClipboardManagerApp.swift   @main — MenuBarExtra + Settings scenes
│   └── AppDelegate.swift           NSApplicationDelegate, wires everything
│
├── Models/
│   ├── ClipboardItem.swift         GRDB Record (struct), ContentType enum
│   └── Settings.swift              @Observable, UserDefaults-backed
│
├── Services/
│   ├── ClipboardMonitor.swift      Timer 0.5s, polls NSPasteboard.changeCount
│   ├── StorageService.swift        GRDB facade: insert/fetch/search/delete
│   ├── HotkeyService.swift         Carbon RegisterEventHotKey wrapper
│   └── AccessibilityService.swift  CGEvent ⌘V simulation (auto-paste)
│
├── ViewModels/
│   └── ClipboardViewModel.swift    @Observable @MainActor, search debounce via Task
│
├── Views/
│   ├── MainPopupView.swift         Popup principal (busca + lista)
│   ├── ClipboardItemRow.swift      Linha do histórico com context menu
│   ├── MenuBarView.swift           Itens do menu da barra (MenuBarMenuView)
│   └── SettingsView.swift          TabView: General / Privacy / Hotkeys
│
├── Windows/
│   └── PopupWindowController.swift NSPanel floating, não-ativante
│
├── Persistence/
│   └── SQLiteManager.swift         DatabaseQueue + WAL + migrações + FTS5
│
└── Resources/
    ├── Info.plist                  LSUIElement=true (sem Dock)
    ├── ClipboardManager.entitlements  sandbox=false
    ├── com.weethub.ClipboardManager.plist  LaunchAgent template
    └── Assets.xcassets/
```

---

## Arquitetura e fluxo de dados

```
AppDelegate (cria e conecta tudo)
    │
    ├── SQLiteManager ──────────────────► clipboard.db (WAL + FTS5)
    │        │
    │   StorageService (@MainActor)
    │        │  insert / fetchAll / search / setFavorite / delete
    │        │
    ├── ClipboardMonitor (@MainActor)
    │        │  Timer 0.5s → checkForChanges()
    │        │  onNewItem: @MainActor (ClipboardItem) → Void
    │        │
    ├── HotkeyService (@MainActor)
    │        │  Carbon RegisterEventHotKey → Task { @MainActor in toggle() }
    │        │
    ├── ClipboardViewModel (@Observable @MainActor)
    │        │  items, searchQuery (debounce 150ms via Task)
    │        │  selectItem → escreve NSPasteboard → simulatePaste()
    │        │
    └── PopupWindowController (@MainActor)
             │  NSPanel level=.popUpMenu, collectionBehavior=canJoinAllSpaces
             │  show() → salva previousApp, makeKeyAndOrderFront
             │  hide() → previousApp.activate() → simulatePaste() após 200ms
             │
        MainPopupView (SwiftUI)
             TextField (busca) + LazyVStack + onKeyPress handlers
```

---

## Banco de dados

**Localização:** `~/Library/Application Support/ClipboardManager/clipboard.db`

```sql
-- Tabela principal
CREATE TABLE clipboard_history (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    content      TEXT    NOT NULL DEFAULT '',
    content_type TEXT    NOT NULL DEFAULT 'text',  -- text|url|image|code|file
    source_app   TEXT,
    created_at   DATETIME NOT NULL DEFAULT (CURRENT_TIMESTAMP),
    is_favorite  INTEGER  NOT NULL DEFAULT 0,
    raw_data     BLOB     -- dados binários para imagens
);

-- FTS5 sincronizado por triggers (GRDB gerencia automaticamente)
CREATE VIRTUAL TABLE clipboard_fts USING fts5(
    content,
    content='clipboard_history',
    content_rowid='id'
);
```

**Busca:** FTS5 com `MATCH ?*` (prefix search). Fallback para `LIKE` se FTS retornar vazio.  
**Poda:** automática ao inserir — remove os mais antigos além do `historyLimit` e os mais velhos que `retentionDays`. Favoritos nunca são podados.

---

## Concorrência (Swift 6)

| Classe | Isolamento | Motivo |
|---|---|---|
| `ClipboardViewModel` | `@MainActor` + `@Observable` | atualiza UI |
| `StorageService` | `@MainActor` | ops SQLite são < 10ms para 500 itens |
| `ClipboardMonitor` | `@MainActor` | acessa `NSPasteboard` e `NSWorkspace` |
| `HotkeyService` | `@MainActor` | callback via `Task { @MainActor in }` |
| `AccessibilityService` | `nonisolated Sendable` | só chama C APIs thread-safe |
| `PopupWindowController` | `@MainActor` | manipula `NSWindow` |
| `Settings` | `@Observable` (sem isolamento) | `UserDefaults` é thread-safe |

**Padrão do callback Carbon:** o C callback em `HotkeyService` usa `nonisolated(unsafe) static var onTriggered` e despacha via `Task { @MainActor in }`. Não usar `DispatchQueue.main.async` — conflita com o modelo de concorrência do Swift 6.

**Debounce de busca:** implementado com `Task` cancelável (não com Combine) para compatibilidade com Swift 6 strict concurrency.

---

## Comportamentos importantes

### Evitar loop ao escrever no clipboard
Quando o usuário seleciona um item, o app escreve no `NSPasteboard`. Para o `ClipboardMonitor` não registrar esse write como novo item:
```swift
monitor.isWritingToClipboard = true   // seta antes de escrever
// escreve no NSPasteboard
// na próxima checagem do timer, o flag é lido e resetado para false
```

### Fluxo de auto-paste
1. `ClipboardViewModel.selectItem(_:)` escreve no pasteboard
2. `PopupWindowController.hide()` é chamado (pelo `onClose` closure da view)
3. `hide()` chama `previousApp.activate(options: .activateIgnoringOtherApps)`
4. `Task.sleep(200ms)` aguarda o app anterior ficar ativo
5. `AccessibilityService.shared.simulatePaste()` envia `CGEvent` ⌘V

### NSPanel — configuração crítica
```swift
styleMask:           [.nonactivatingPanel, .borderless, .fullSizeContentView]
level:               .popUpMenu
isFloatingPanel:     true
collectionBehavior:  [.canJoinAllSpaces, .fullScreenAuxiliary]
```
`.nonactivatingPanel` + `makeKeyAndOrderFront` = o painel recebe teclado mas não muda o app ativo.

### Filtro de conteúdo sensível
`ClipboardMonitor` tem regex patterns para JWT (`eyJ...`), API keys (`sk-`, `ghp_`, `AKIA`), chaves PEM e Bearer tokens. Se `settings.ignorePasswords` ou `settings.ignoreApiKeys` estiver ligado, o item é descartado silenciosamente.

Apps na lista `settings.ignoredApps` (bundle IDs) têm todo o conteúdo ignorado.

---

## Dependências externas

| Pacote | Versão | Para que serve |
|---|---|---|
| [GRDB.swift](https://github.com/groue/GRDB.swift) | `>= 6.29.0` | SQLite ORM, FTS5, migrations, WAL |

Sem outras dependências. Carbon, CoreGraphics, ServiceManagement, AppKit são frameworks do sistema.

---

## Configurações (Settings.swift)

Todas persistidas em `UserDefaults`. Valores padrão:

| Propriedade | Padrão | Descrição |
|---|---|---|
| `historyLimit` | 500 | máximo de itens não-favoritos |
| `retentionDays` | 30 | dias antes de expirar |
| `ignorePasswords` | `true` | filtra conteúdo sensível |
| `ignoreApiKeys` | `true` | filtra tokens/chaves de API |
| `ignoredApps` | 1Password, Bitwarden, etc | bundle IDs ignorados |
| `launchAtLogin` | `false` | usa `SMAppService.mainApp` |
| `showInMenuBar` | `true` | controla visibilidade |

---

## Fases de desenvolvimento

| Fase | Status | Escopo |
|---|---|---|
| 1 | Completa | Monitor, histórico, FTS, popup, ⌥V, auto-paste, filtro sensível |
| 2 | Planejada | UI de favoritos, melhorias de configurações |
| 3 | Planejada | OCR via Vision framework, Snippets (`/keyword`), sync iCloud |

---

## Notas de distribuição

- **Sem App Sandbox** — necessário para `RegisterEventHotKey` e `CGEvent.post`. Impede distribuição na App Store.
- **Sem notarização** — distribuído via GitHub Releases com remoção de quarentena pelo `install.sh`.
- O `install.sh` usa a API pública do GitHub Releases para obter a URL do ZIP mais recente.
- CI publica automaticamente ao criar um tag `v*` (`git tag v1.0.0 && git push origin v1.0.0`).
- O binário é compilado como **universal** (arm64 + x86_64) no runner `macos-14` do GitHub Actions.
