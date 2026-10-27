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
└── com.github.copilot/agents/          agentes (só Copilot)
    ├── figma-to-flutter.agent.md       telas do Figma → Flutter
    ├── figma-component-builder.agent.md
    ├── figma-visual-reviewer.agent.md
    └── figma-ds-mapper.agent.md        anotações e política do DS
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

## Usar

- Telas: agente **figma-to-flutter** ("implemente a tela Confirmar do último export").
- DS: agente **figma-ds-mapper**, de dentro do pacote de mapeamentos ("monte a política", "anote o Button Icon").

## Manter

- Cada skill fica em `skills/<nome>/SKILL.md`, e `<nome>` é igual ao `name:` do frontmatter (o VS Code ignora a
  skill quando não é).
- Os agentes apontam para as skills com `../../skills/<nome>/SKILL.md`.
- O teste `figma2dart/test/plugin_test.dart` confere as duas coisas e o manifesto.
