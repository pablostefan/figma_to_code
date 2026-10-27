# Plugin figma2dart para o Copilot

Agentes e skills do figma2dart num plugin ([Agent Plugins 1.0](https://docs.github.com/pt/copilot/concepts/customizations/plugins)).
Instalado uma vez por máquina, vale em qualquer pacote do monorepo, sem copiar arquivos para cada app.

```
copilot_plugin/
├── plugin.json                         manifesto
├── skills/                             skills (Copilot e outros clientes)
│   ├── figma2dart-setup/               descobrir caminhos, instalar a CLI, resolver o doctor
│   ├── figma2dart-screen/              implementar uma tela pelo brief
│   ├── figma2dart-component/           construir um componente fora do DS
│   ├── figma2dart-review/              revisão visual da tela
│   ├── figma2dart-connect/             anotar um componente do DS (@FigmaConnect)
│   └── figma2dart-policy/              montar e conferir o FigmaPolicy (tokens, ícones)
└── com.github.copilot/                 só Copilot
    ├── lsp.json                        LSP do Dart (Copilot CLI)
    ├── hooks/                          doctor e dart analyze depois de editar; confirmação para editar o Acme
    └── agents/
        ├── figma-to-flutter.agent.md   telas do Figma → Flutter
        ├── figma-component-builder.agent.md
        ├── figma-visual-reviewer.agent.md
        └── figma-ds-mapper.agent.md    anotações e política do DS
```

## Instalar (local)

**1. O plugin**, apontando para esta pasta no seu clone do repositório:

- **VS Code:** nas configurações do usuário (`settings.json`):

  ```json
  "chat.plugins.enabled": true,
  "chat.pluginLocations": {
    "/caminho/do/repo/copilot_plugin": true
  }
  ```

- **Copilot CLI:** `copilot plugin install /caminho/do/repo/copilot_plugin`.

Como o VS Code lê a pasta direto, um `git pull` já atualiza agentes e skills. Na Copilot CLI, o plugin é copiado:
rode o `install` de novo depois de atualizar.

**2. A CLI** (uma vez por máquina): `<repo>/…/figma2dart/tool/figma2dart setup`. Ele grava o comando `figma2dart` em
`~/.pub-cache/bin` (que precisa estar no `PATH`); o comando roda a CLI do repositório git de onde for chamado. Se
você esquecer, a skill `figma2dart-setup` encontra o script e roda o setup depois de pedir sua confirmação.

## LSP do Dart (Copilot CLI)

O plugin traz o servidor `dart` (`dart language-server`), e a Copilot CLI passa a usá-lo no lugar da busca por texto:
definição, referências, hover, símbolos e rename vêm do analyzer. Ajuda a ler construtores, factories e classes de
tokens do Acme sem abrir os arquivos inteiros.

- Precisa do `dart` no `PATH` (o do Flutter serve) e de uma Copilot CLI recente (`copilot update`): o formato Agent
  Plugins (`com.github.copilot/`) é das versões novas.
- `onlyAnalyzeProjectsWithOpenFiles`: o analyzer carrega só os pacotes dos arquivos que o agente abre, não o monorepo
  inteiro. Por isso, "achar referências" só vê esses pacotes; o impacto de uma mudança no DS continua no `doctor`.
- Cada pacote precisa do `pub get` (ou do `melos bootstrap`) feito, senão os imports não resolvem.
- Não traz os erros de compilação: continue com `dart analyze`.
- Conferir: `/lsp` mostra `dart` vindo do plugin; `/lsp test dart` sobe o servidor e diz se deu certo.
- Um `.github/lsp.json` no repositório com um servidor `dart` vence este; com `"disabled": true`, desliga.
- O VS Code não lê este arquivo: lá, a extensão do Dart já dá isso ao Copilot.

## Hooks (Copilot CLI)

[`hooks/figma2dart.sh`](com.github.copilot/hooks/figma2dart.sh) roda em toda edição de arquivo do agente. Só informa,
nunca bloqueia sozinho:

| Quando | O que faz |
|---|---|
| antes de editar algo em `acme/` ou `acme_templates/` | pede confirmação ao usuário (`ask`): um componente do DS não muda por causa de uma tela |
| depois de editar um `*.figma.dart` ou o `figma_policy.dart` | roda `figma2dart doctor --json` e devolve ao agente `mappings`, `problems` e `warnings` |
| depois de editar um `.dart` em `lib/figma/` | roda `dart analyze` no arquivo e devolve os erros (o LSP não traz erros) |

- Precisa de `jq` (já vem no macOS) e, para o doctor, do `figma2dart` no `PATH`; sem eles, o hook não faz nada.
- O doctor leva alguns segundos (o analyzer carrega as anotações). Passou de 120 s, o hook desiste sem travar o agente.
- Telas numa pasta que não seja `lib/figma/` não disparam o `dart analyze`.
- Sem ninguém para confirmar (`copilot -p`), o `ask` vira recusa.
- A saída também vem no formato do VS Code, mas não conferi se o VS Code carrega hooks de plugin.

## Usar

- Telas: agente **figma-to-flutter** ("implemente a tela Confirmar do último export").
- DS: agente **figma-ds-mapper**, de dentro do pacote de mapeamentos ("monte a política", "anote o Button Icon").

## Manter

- Cada skill fica em `skills/<nome>/SKILL.md`, e `<nome>` é igual ao `name:` do frontmatter (o VS Code ignora a
  skill quando não é).
- Os agentes apontam para as skills com `../../skills/<nome>/SKILL.md`.
- O teste `figma2dart/test/plugin_test.dart` confere as duas coisas e o manifesto.
