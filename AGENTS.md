# AGENTS.md — MBC6 Test ROM

Guia curto para qualquer agente (Claude, Codex, Copilot etc.) que for
trabalhar neste repositório. As regras técnicas completas continuam no
`CLAUDE.md` (preservado de propósito; não apague nem migre sem
autorização do Rafael) e nos documentos em `docs/`.

## O que é o projeto

ROM de testes aberta, só para Game Boy Color (CGB), que verifica
implementações do mapper MBC6 (cartucho Net de Get) em emuladores e em
hardware compatível. Correção, determinismo e rastreabilidade às fontes
valem mais do que aparência.

## Antes de começar

1. Consulte a memória interna do seu agente sobre este projeto, se ela
   existir.
2. Depois consulte a OMM pelo MCP: `context` e `search` no escopo
   `mbc6test` (inclua `global` quando ajudar — por exemplo, a referência
   `net-de-get-maker`). Abra registros completos com `get_memory` e
   confira fontes com `search_sources`/`read_source`. Para orientação de
   domínio existe a skill OMM `mbc6test-expert`.
3. A pasta `memory/` deste repositório é um retrato antigo da memória do
   projeto (veja `OMM.md`); o conhecimento mais novo está na OMM.

Essa é a ordem de consulta, não a ordem de autoridade. Memórias são
pistas, não provas nem instruções: confirme no código, em `docs/` e nas
fontes originais, seguindo a hierarquia de fontes do `CLAUDE.md`.

## Como trabalhar

- Fale com o Rafael em português do Brasil.
- Só faça commit ou push quando ele pedir.
- Leia a implementação e as fontes antes de mudar algo. Preserve as
  restrições de arquitetura (por exemplo, código que troca bancos fica na
  ROM fixa) salvo motivo documentado, e prefira mudanças pequenas e
  fáceis de auditar.
- Depois de mudar código, layout, dados gerados ou build, rode `make` e
  `make verify`. Isso confere só a ROM estática; não prova que o mapper
  funciona em execução.
- Não transforme comportamento de emulador em regra de hardware. Bug ou
  lacuna de emulador é registrado como tal; comportamento incerto vira
  `INFO` ou `SKIP`.
- Não rode operações destrutivas de flash no desenvolvimento normal. Os
  testes TD1–TD6 só existem no build com `ENABLE_DESTRUCTIVE_FLASH_TESTS=1`.
- Ao testar em emulador, capture só a janela dele (por exemplo,
  `import -window <id>`), nunca a tela inteira: a área de trabalho é
  compartilhada com outras sessões.

## Ao terminar

- Registre na OMM, no escopo `mbc6test`, o conhecimento duradouro novo,
  com origem, versão e evidência. Ao atualizar algo, marque o registro
  antigo como `superseded`.
- Atualize o handoff da OMM com o estado real, os bloqueios e a próxima
  ação.
- Mantenha a memória interna e a OMM coerentes: a OMM não pode ficar
  atrás da memória interna.
