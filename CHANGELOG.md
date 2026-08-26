# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/),
versionamento conforme [SemVer](https://semver.org/lang/pt-BR/).

## [Não lançado]

## [1.0.7] — 2026-08-25

### Adicionado

- Assinatura da **Cotia Labs** no app: rodapé do painel mostra
  "Claude Status por Cotia Labs" ao lado da versão, e o menu de opções ganhou
  um item que abre o repositório da Cotia Labs.
- `build-app.sh` aceita `SIGNING_IDENTITY`: com um Developer ID a assinatura
  sai com hardened runtime e timestamp; sem ele, continua ad-hoc como antes.
- Pipeline de release importa um certificado Developer ID para uma keychain
  temporária quando os secrets `SIGNING_CERTIFICATE_P12`,
  `SIGNING_CERTIFICATE_PASSWORD` e `SIGNING_IDENTITY` existem. Sem secrets,
  o build segue ad-hoc.

## [1.0.6] — 2026-08-25

### Corrigido

- Popover continuava abrindo ~115 pt abaixo do menu bar. A causa era o
  `contentSize` do `NSPopover`: sem valor explícito ele vale 320x320, e o
  AppKit posiciona o painel para esse tamanho antes do SwiftUI encolher a
  view. Agora o `NSHostingController` usa `sizingOptions = .preferredContentSize`
  e o `contentSize` é atualizado a partir do `fittingSize` antes de cada
  abertura. Medido em runtime: o topo do painel encosta no menu bar.
- Anel da barra de menus mostrava a janela mais cheia, que costuma ser a
  semanal. Passa a mostrar a **sessão atual** (janela de 5 horas), com
  fallback para a semanal em planos que não reportam sessão. Os avisos de
  80% e 95% seguem olhando a janela mais próxima do limite, qualquer que seja.
- Tooltip da barra agora identifica a janela: "Sessão atual: 5% usado".

## [1.0.5] — 2026-08-25

### Adicionado

- Licença do projeto: código aberto para uso não comercial, sob a
  [PolyForm Noncommercial License 1.0.0](LICENSE.md), com nota de copyright
  no `Info.plist` e seção de licença no README.
- Item "Licença: uso não comercial" no menu de opções, abrindo o texto.

## [1.0.4] — 2026-08-25

### Adicionado

- Versão do app no rodapé do painel e no topo do menu de opções, lida do
  `Info.plist` (`CFBundleShortVersionString`, com o número do build do CI
  quando houver).
- Flag `--version` no executável.

## [1.0.3] — 2026-08-25

### Corrigido

- Popover abria distante do topo da tela. O medidor era uma `NSView` dentro do
  botão do status item e o `button.frame` era sobrescrito a cada render, então
  o AppKit ancorava o popover numa geometria errada. Agora o medidor é
  desenhado como `NSImage` e atribuído a `button.image`: sem subview, sem
  mexer em frames, e o popover encosta no menu bar como nos demais apps.

### Alterado

- Clique passa pelo `target/action` do próprio botão, com
  `sendAction(on: [.leftMouseUp, .rightMouseUp])`; botão direito e Ctrl+clique
  seguem abrindo o menu de opções.

## [1.0.2] — 2026-08-25

### Adicionado

- Ícone do app (`logo.icns`), embutido no bundle como `AppIcon.icns` e usado
  também como ícone do volume do DMG.

## [1.0.1] — 2026-08-25

### Corrigido

- Posição do popover ajustada para apontar corretamente para a borda inferior do ícone da barra de menus.

## [1.0.0] — 2026-08-25

Primeira versão.

### Adicionado

- Widget de barra de menus com anel animado mostrando a janela de uso mais
  apertada do plano, com easing até o novo valor e pulsação acima de 95%.
- Painel com uma barra animada por janela — sessão de 5 horas, semanal de todos
  os modelos, e as semanais de Opus e Sonnet quando o plano as retorna — com
  percentual em `contentTransition(.numericText())`.
- Contador "Reinicia em 2 h 46 min" atualizado a cada segundo, virando data
  absoluta ("Reinicia sáb., 11:00") para janelas distantes.
- Leitura do uso via `GET /api/oauth/usage` com o token OAuth local
  (`~/.claude/.credentials.json`, com fallback para o keychain).
- Status da plataforma no rodapé, vindo de `status.anthropic.com`.
- Notificações locais ao cruzar 80% e 95%, rearmadas quando a janela reinicia.
- Opções: intervalo de atualização (1 / 5 / 15 / 30 min), porcentagem na barra,
  avisos de limiar e abrir no login (`SMAppService`).
- `--dump` para imprimir as janelas no terminal sem abrir a interface.
- `build-app.sh` com `--universal`, `--dmg` e `--install`; DMG universal
  (arm64 + x86_64) publicado pelo pipeline do GitHub Actions.

### Notas

- O endpoint de uso não é oficial e pode mudar sem aviso.
- Proteções contra o 429 do endpoint: `User-Agent` no formato do CLI, intervalo
  mínimo de 60 s entre chamadas, backoff que respeita `Retry-After` até 15 min,
  e painel que mantém os últimos números bons quando um refresh falha.
- O app é assinado apenas ad-hoc; não é notarizado.

[Não lançado]: https://github.com/Cotia-Labs/ClaudeStatusBar/compare/v1.0.6...HEAD
[1.0.6]: https://github.com/Cotia-Labs/ClaudeStatusBar/compare/v1.0.5...v1.0.6
[1.0.5]: https://github.com/Cotia-Labs/ClaudeStatusBar/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/Cotia-Labs/ClaudeStatusBar/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/Cotia-Labs/ClaudeStatusBar/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/Cotia-Labs/ClaudeStatusBar/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/Cotia-Labs/ClaudeStatusBar/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/Cotia-Labs/ClaudeStatusBar/releases/tag/v1.0.0
