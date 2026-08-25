# ClaudeStatusBar

Widget de barra de menus para macOS que mostra, de forma animada, os
**limites de uso do plano Claude** — a mesma informação do `/usage` do
Claude Code — mais o status da plataforma.

## Build

```bash
./build-app.sh            # gera dist/ClaudeStatusBar.app
./build-app.sh --install  # também copia para /Applications
open dist/ClaudeStatusBar.app

./.build/release/ClaudeStatusBar --dump   # imprime os números no terminal
```

Requisitos: macOS 13+, toolchain Swift, e login ativo do Claude Code
(`claude auth`).

## O que aparece

Na barra: um **anel que enche** com o percentual da janela mais apertada.
Verde → amarelo → laranja → vermelho, com pulsação lenta acima de 95%.
O anel faz easing até o novo valor a cada atualização, nunca salta.
Opcionalmente mostra a porcentagem em texto ao lado.

Clique abre o painel:

```
Limites de uso do plano
Sessão atual                        53% usado
▓▓▓▓▓▓▓▓▓░░░░░░░░
Janela de 5 horas      Reinicia em 2 h 46 min

Todos os modelos                    35% usado
▓▓▓▓▓▓░░░░░░░░░░░
Semanal                  Reinicia sáb., 11:00

● All Systems Operational                18:04
```

Barras animam com spring ao carregar e a cada mudança de valor, o
percentual usa `contentTransition(.numericText())`, e o contador
"Reinicia em…" corre em tempo real (TimelineView de 1 s).

Clique com o botão direito (ou no `⋯`) abre as opções: intervalo de
atualização (1 / 5 / 15 / 30 min), porcentagem na barra, avisos em 80% e
95%, abrir no login, e o link do status page.

## De onde vêm os dados

- **Uso:** `GET https://api.anthropic.com/api/oauth/usage` com o token OAuth
  local (`~/.claude/.credentials.json`, com fallback para o item de keychain
  `Claude Code-credentials`). É o mesmo endpoint que alimenta o `/usage`.
  **API não oficial** — pode mudar sem aviso. O token só sai do processo no
  header `Authorization` para a api.anthropic.com.
- **Status da plataforma:** `status.anthropic.com/api/v2/summary.json`.

O endpoint separa os pedidos por `User-Agent`: qualquer coisa que não pareça
o CLI cai num bucket estreito e devolve 429 persistente. Por isso o app envia
`claude-cli/<versão> (external, cli)` e ainda assim se protege:

- intervalo mínimo de 60 s entre chamadas, independente do que a UI peça
  (abrir o popover reaproveita o valor em cache);
- em 429, respeita `Retry-After` ou dobra a espera até 15 min;
- o "Atualizar agora" fura o cooldown normal, mas nunca o backoff de 429;
- em falha, o painel mantém os últimos números bons esmaecidos com a nota
  "Mostrando dados de …" em vez de apagar tudo.

Intervalos disponíveis: 1 / 5 / 15 / 30 min (padrão 5 min).

## Estrutura

| Arquivo | Papel |
| --- | --- |
| `App.swift` | Entry point, política `.accessory`, flag `--dump` |
| `AppDelegate.swift` | NSStatusItem, popover, menu de opções |
| `MenuBarGauge.swift` | Anel animado desenhado na barra de menus |
| `UsagePanel.swift` | Painel SwiftUI com barras animadas e countdown |
| `UsageStore.swift` | Polling, notificações de limiar, formatadores |
| `UsageFetcher.swift` / `UsageModel.swift` | Endpoint de uso e modelo |
| `Credentials.swift` | Leitura do token OAuth local |
| `StatusFetcher.swift` / `StatusModel.swift` | Status page |
| `Preferences.swift` / `Notifier.swift` | Ajustes e notificações locais |
