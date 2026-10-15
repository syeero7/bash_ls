#!/bin/bash
set -euo pipefail

if ! command -v jq &>/dev/null; then
  echo "error: 'jq' is required." >&2
  exit 1
fi

export OUTPUT="$(mktemp -d)/output.jsonl"
touch "$OUTPUT"

append_to_output() {
  local cmd="$1"
  local output="$2"

  if [ -n "$output" ]; then
    jq -nc --arg c "$cmd" --arg o "$output" '{$c:$o}' >>"$OUTPUT"
  fi

}

extract_append_help() {
  local cmd="$1"
  local cmd_output
  local help_args=(--help -h help)

  for arg in $help_args; do
    cmd_output="$($cmd $arg 2>&1 || true)"
    [ ! -z "$cmd_output" ] && break
  done

  append_to_output "$cmd" "$cmd_output"
}

extract_prepend_help() {
  local cmd="$1"
  local cmd_output

  cmd_output="$(help $cmd 2>&1 || true)"
  append_to_output "$cmd" "$cmd_output"
}

export -f append_to_output
export -f extract_append_help
export -f extract_prepend_help

BUILTINS=" $(compgen -b | tr '\n' ' ') "

append_help_commands=" git awk xargs cat sleep find grep tar "
prepend_help_commands="$BUILTINS for while select time "

printf '%s\n' $prepend_help_commands | xargs -I {} -P 0 bash -c 'extract_prepend_help "{}"'
printf '%s\n' $append_help_commands | xargs -I {} -P 0 bash -c 'extract_append_help "{}"'

echo $OUTPUT
