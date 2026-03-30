#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_DIR="$REPO_ROOT/original-walls"
OUTPUT_DIR="$REPO_ROOT/catppuccin-walls"
PALETTE="${PALETTE:-catppuccin-mocha}"
TMP_DIR="$(mktemp -d)"
TMP_WORK_DIR="$TMP_DIR/work"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if ! command -v lutgen >/dev/null 2>&1; then
  echo "Required command not found: lutgen"
  exit 1
fi

if [[ ! -d "$INPUT_DIR" ]]; then
  echo "Input directory not found: $INPUT_DIR"
  exit 1
fi

echo "Applying $PALETTE palette to wallpapers in $INPUT_DIR"
mkdir -p "$TMP_WORK_DIR" "$OUTPUT_DIR"

found=0
while IFS= read -r -d '' _; do
  found=$((found + 1))
done < <(find "$INPUT_DIR" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) -print0)

if [[ "$found" -eq 0 ]]; then
  echo "No files found in $INPUT_DIR"
  exit 1
fi

processed=0
generated=0
while IFS= read -r -d '' src; do
  processed=$((processed + 1))
  base_name="$(basename "$src")"
  work_path="$TMP_WORK_DIR/$base_name"
  cp -- "$src" "$work_path"

  apply_output=""
  if ! apply_output="$(lutgen apply "$work_path" -p "$PALETTE" </dev/null 2>&1)"; then
    echo "Failed to apply palette: $base_name"
    if [[ -n "$apply_output" ]]; then
      echo "$apply_output"
    fi
    continue
  fi
done < <(find "$INPUT_DIR" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) -print0)

for themed in "$TMP_WORK_DIR"/*_"$PALETTE".*; do
  [[ -e "$themed" ]] || continue
  themed_name="$(basename "$themed")"
  output_name="${themed_name/_$PALETTE/}"
  if [[ -e "$OUTPUT_DIR/$output_name" ]]; then
    echo "Overwriting existing file: $output_name"
  fi
  mv -f -- "$themed" "$OUTPUT_DIR/$output_name"
  generated=$((generated + 1))
done

if [[ "$generated" -ne "$processed" ]]; then
  echo "Expected $processed generated file(s), produced $generated."
  exit 1
fi

echo "Generated $generated Catppuccin wallpapers in $OUTPUT_DIR"