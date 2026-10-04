# OMM no MBC6 Test ROM

A memória compartilhada do projeto (OMM) fica fora deste repositório.

## Onde fica cada coisa

- **Dados da OMM**: memórias, fontes importadas, skills, papéis e handoffs do MBC6. Ficam somente no backup `ai-omm-backup` e são acessados pelo MCP da OMM, no escopo `mbc6test`. Essa é a memória canônica do projeto.
- **Programa da OMM**: o repositório `ai-omm` contém só a aplicação, sem dados pessoais.
- **Documentos do próprio projeto**: `AGENTS.md`, este `OMM.md`, `README.md`, `docs/`, o código e o workflow ficam neste repositório. São as fontes de conferência; a OMM os cita e guarda cópias como fontes, mas não os substitui. As regras e fontes completas estão em `docs/project-rules.md` (o antigo `CLAUDE.md`) e nos outros documentos de `docs/`; o `AGENTS.md` é só um guia curto de trabalho.

## Nada de dados da OMM aqui

A pasta `memory/` e o índice local `.omm/` eram cópias legadas de dados da OMM, criadas no commit `d151752` (2026-10-01). Foram removidos em 2026-10-04. O conteúdo deles está no `ai-omm-backup` (os 22 registros, como `superseded`, e os 3 manifestos de importação) e continua no histórico Git.

Não recrie dados da OMM neste repositório, nem rodando a CLI `omm` nesta pasta.

## Como consultar e registrar

Pelo MCP da OMM, no escopo `mbc6test`:

- `context` ou `search` para encontrar registros e `get_memory` para abrir um;
- `search_sources` e `read_source` para conferir a origem;
- `remember` (ou `propose_memory`, quando a pessoa for revisar) para registrar conhecimento novo, com origem e evidência; marque o registro antigo como `superseded` com `set_memory_status`;
- `handoff` para deixar o estado real, os bloqueios e a próxima ação.

Se usar a CLI `omm`, aponte-a para os dados da OMM, nunca para esta pasta. O backup é sincronizado pelo mecanismo normal da OMM (painel "Sincronizar backup" ou `omm sync`), e não por commits neste repositório.

O histórico importado da conversa Claude Code continua identificável pelas fontes e pelos IDs de sessão nas anotações. A transcrição inteira não foi copiada para a OMM; o que existe são resumos, o texto visível parcial e o OCR aproximado das capturas de tela.

## Como usar com segurança

- Consulte a memória antes de repetir uma investigação e abra as fontes citadas antes de mudar um contrato.
- Siga a ordem de fontes e os limites de evidência de `docs/project-rules.md`.
- Separe falhas de emuladores específicos de expectativas normativas sobre hardware.
- A busca da OMM é um índice, não prova: confirme no código, em `docs/` e nas fontes originais.
- A skill `mbc6test-expert`, guardada na OMM, traz orientação de domínio; os fatos do projeto ficam na OMM e nas fontes citadas.
