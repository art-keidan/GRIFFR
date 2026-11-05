#!/bin/zsh
set -e
project_dir="${0:A:h:h}"
cd -- "$project_dir"
claude_bin="$(command -v claude 2>/dev/null || true)"
if [[ -z "$claude_bin" && -x "$HOME/.local/bin/claude" ]]; then
  claude_bin="$HOME/.local/bin/claude"
fi
if [[ -z "$claude_bin" ]]; then
  print -r -- "Claude Code non trovato. Apri Claude Code in: $project_dir"
  print -r -- "Il prompt pronto è in Appunti/PROMPT-CLAUDE.txt."
  read -r '?Premi Invio per chiudere.'
  exit 1
fi
prompt_file="$project_dir/Appunti/PROMPT-CLAUDE.txt"
initial_prompt="$(<"$prompt_file")"
exec "$claude_bin" --name "GRIFFR · Compositore ad azioni" "$initial_prompt"
