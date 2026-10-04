# Memória do MBC6 Test ROM no OMM

A memória do projeto fica em dois lugares:

- **OMM compartilhada**, consultada pelo MCP no escopo `mbc6test`, com backup no `ai-omm-backup`. É a mais completa: o histórico consolidado das conversas (2026-10-03) e as descobertas técnicas registradas em 2026-10-04 estão lá.
- **Pasta `memory/` deste repositório**, um retrato feito no commit `d151752` (2026-10-01) que viaja com o código pelo Git. Ela não recebeu os registros posteriores.

Ainda falta decidir qual dos dois é o canônico para o MBC6: o registro OMM `cb0b46d8` (2026-10-01) trata `memory/` como a memória ativa, mas os registros mais novos foram gravados na OMM compartilhada. Até o Rafael decidir, consulte os dois e prefira a OMM quando divergirem.

As regras e fontes completas estão no `CLAUDE.md` e nos documentos técnicos (`docs/`). O `AGENTS.md` é só um guia curto de trabalho.

## Uso rápido

Pelo MCP da OMM: `context` ou `search` com `scope: "mbc6test"`, `get_memory` para abrir um registro e `search_sources`/`read_source` para conferir a origem.

Com o comando OMM instalado (ele não estava instalado nesta máquina em 2026-10-04), abra o terminal nesta pasta:

```sh
omm search "flash JEDEC ID"
omm context "MBC6 source precedence"
omm remember --kind observation --title "Resultado observado" --content "O que ocorreu, em qual versão e em que condições" --source "docs/mbc6-notes.md" --evidence "docs/test-matrix.md: T31"
omm handoff --status in_progress --summary "Onde a investigação parou" --next "Próxima ação"
```

O histórico importado da conversa Claude Code permanece identificável pelas fontes e IDs de sessão nas anotações. A transcrição inteira não foi copiada para a memória.

## Como usar com segurança

- Consulte a memória antes de repetir uma investigação e abra as fontes citadas antes de mudar um contrato.
- Siga a ordem de fontes e os limites de evidência descritos no `CLAUDE.md`.
- Separe falhas de emuladores específicos de expectativas normativas sobre hardware.
- A busca do OMM é um índice rápido das anotações, não prova por si só que uma afirmação esteja correta.
- O índice local fica em `.omm/`, é ignorado pelo Git e pode ser recriado com `omm rebuild`.
- A skill opcional `mbc6test-expert` complementa a memória com orientação de domínio; os fatos específicos do projeto ficam na OMM, em `memory/` e nas fontes citadas.
