#!/usr/bin/env bash
# Hooks do figma2dart. Só informam: devolvem contexto ao agente ou pedem confirmação ao usuário, nunca negam.
#   pre:  editar o Acme (acme/, acme_templates/) → pede confirmação.
#   post: editou *.figma.dart ou figma_policy.dart → `figma2dart doctor`; editou lib/figma/**.dart → `dart analyze`.
# Entrada no stdin: Copilot CLI (`toolArgs`) ou formato do VS Code (`tool_input`).
mode=$1
command -v jq >/dev/null || exit 0
input=$(cat)
args=$(jq -c '(.toolArgs // .tool_input // {}) | if type == "string" then (fromjson? // .) else . end' <<<"$input")
# edit/create: `path`; VS Code: `filePath`; apply_patch: o patch em texto, com os arquivos em `*** Add|Update File:`.
paths=$(jq -r 'if type == "string" then (scan("\\*\\*\\* (?:Add|Update) File: (.+)") | .[0])
  else (.path // .filePath // .file_path // empty) end' <<<"$args")
[ -n "$paths" ] || exit 0

# Saída nos dois formatos: campos na raiz (Copilot CLI) e em hookSpecificOutput (VS Code).
ask() {
  jq -n --arg t "$1" '{permissionDecision: "ask", permissionDecisionReason: $t,
    hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $t}}'
}
context() {
  jq -n --arg t "$1" '{additionalContext: $t, hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $t}}'
}

if [ "$mode" = pre ]; then
  acme=$(grep -E '/(acme|acme_templates)/' <<<"$paths")
  [ -n "$acme" ] && ask "Edição no Design System (Acme): $acme. Componentes do DS não mudam por uma tela; confirme se é isso mesmo."
  exit 0
fi

out=""
while IFS= read -r path; do
  dir=$(dirname "$path")
  [ -d "$dir" ] || continue
  case "$path" in
    *.figma.dart | */figma_policy.dart)
      command -v figma2dart >/dev/null || continue
      report=$(cd "$dir" && figma2dart doctor --json 2>/dev/null |
        jq -c '{mappings, problems, warnings}' 2>/dev/null) || continue
      out+="figma2dart doctor depois de editar $path: $report"$'\n' ;;
    */lib/figma/*.dart)
      # shortcut: a pasta das telas fica fixa em lib/figma (o padrão do figma_to_dart.yaml); outra pasta não dispara.
      result=$(cd "$dir" && dart analyze "$path" 2>&1) && continue
      out+="dart analyze $path:"$'\n'"$(head -40 <<<"$result")"$'\n' ;;
  esac
done <<<"$paths"
[ -n "$out" ] && context "$out"
exit 0
