#!/bin/bash
set -euo pipefail

if ! command -v jq &>/dev/null; then
  echo "error: 'jq' is required." >&2
  exit 1
fi

OUTPUT="${1:-"command_help.jsonl"}"
BUILTINS="$(compgen -b | tr '\n' ' ')"

# <command> [ -h, --help, help ]
APPEND_HELP_COMMANDS="git awk xargs cat sleep find grep tar cut"

# help <command>
PREPEND_HELP_COMMANDS="$BUILTINS for while select time"

export TEMP_OUTPUT="$(mktemp -d)/output.jsonl"
touch "$TEMP_OUTPUT"

append_to_output() {
  local cmd="$1"
  local output="$2"

  if [ -n "$output" ]; then
    jq -nc --arg c "$cmd" --arg o "$output" '{$c:$o}' >>"$TEMP_OUTPUT"
  fi

}

append_help_extract() {
  local cmd="$1"
  local cmd_output
  local help_args=(--help -h help)

  for arg in $help_args; do
    cmd_output="$($cmd $arg 2>&1 || true)"
    [ ! -z "$cmd_output" ] && break
  done

  append_to_output "$cmd" "$cmd_output"
}

prepend_help_extract() {
  local cmd="$1"
  local cmd_output

  cmd_output="$(help $cmd 2>&1 || true)"
  append_to_output "$cmd" "$cmd_output"
}

export -f append_to_output
export -f append_help_extract
export -f prepend_help_extract

printf '%s\n' $PREPEND_HELP_COMMANDS | xargs -I {} -P 0 bash -c 'prepend_help_extract "{}"'
printf '%s\n' $APPEND_HELP_COMMANDS | xargs -I {} -P 0 bash -c 'append_help_extract "{}"'

mv "$TEMP_OUTPUT" "$OUTPUT"
