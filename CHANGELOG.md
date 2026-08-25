# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/),
versionamento conforme [SemVer](https://semver.org/lang/pt-BR/).

## [Não lançado]

## [1.0.1] — 2026-08-25

### Adicionado

- Ícone do app (`logo.icns`), embutido no bundle como `AppIcon.icns` e usado
  também como ícone do volume do DMG.

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

[Não lançado]: https://github.com/Cotia-Labs/ClaudeStatusBar/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/Cotia-Labs/ClaudeStatusBar/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/Cotia-Labs/ClaudeStatusBar/releases/tag/v1.0.0
