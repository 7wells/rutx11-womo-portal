#!/bin/sh

set -eu

[ "${1:-}" = "-e" ] || exit 1
[ "${2:-}" = "@.value" ] || exit 1

# Extract the controlled test fixture's top-level value field.
awk '
{
  value = $0
  if (value !~ /"value"[ \t]*:/) next
  sub(/^.*"value"[ \t]*:[ \t]*/, "", value)
  sub(/[,}].*$/, "", value)
  gsub(/^[ \t]+|[ \t]+$/, "", value)
  print value
  exit
}'
