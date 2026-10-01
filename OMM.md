# Memória do MBC6 Test ROM no OMM

Este repositório guarda a memória selecionada do MBC6 Test ROM na pasta `memory/`. Ela viaja com o código pelo Git. O `CLAUDE.md`, o `AGENTS.md`, os testes e os documentos técnicos continuam contendo as regras e as fontes completas.

## Uso rápido

Com o comando OMM instalado, abra o terminal nesta pasta:

```sh
omm search "flash JEDEC ID"
omm context "MBC6 source precedence"
omm remember --kind observation --title "Resultado observado" --content "O que ocorreu, em qual versão e em que condições" --source "docs/mbc6-notes.md" --evidence "docs/test-matrix.md: T31"
omm handoff --status in_progress --summary "Onde a investigação parou" --next "Próxima ação"
```

O histórico importado da conversa Claude Code permanece identificável pelas fontes e IDs de sessão nas anotações. A transcrição inteira não foi copiada para a memória.

## Como usar com segurança

- Consulte esta memória antes de repetir uma investigação e abra as fontes citadas antes de mudar um contrato.
- Siga a ordem de fontes e os limites de evidência descritos no `CLAUDE.md` e no `AGENTS.md`.
- Separe falhas de emuladores específicos de expectativas normativas sobre hardware.
- A busca do OMM é um índice rápido das anotações, não prova por si só que uma afirmação esteja correta.
- O índice fica em `.omm/`, é ignorado pelo Git e pode ser recriado com `omm rebuild`.
- A skill opcional `mbc6test-expert` complementa a memória com orientação de domínio; os fatos específicos do projeto permanecem em `memory/` e nas fontes citadas.

