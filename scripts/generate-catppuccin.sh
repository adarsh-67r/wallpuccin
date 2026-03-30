#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_DIR="$REPO_ROOT/original-walls"
OUTPUT_DIR="$REPO_ROOT/catppuccin-walls"
THEME="catppuccin"
UPSCALE_SCALE="${UPSCALE_SCALE:-2}"
UPSCALE_MODEL="${UPSCALE_MODEL:-realesrgan-x4plus}"
UPSCALE_STRICT="${UPSCALE_STRICT:-false}"
TMP_DIR="$(mktemp -d)"
TMP_CONVERTED_DIR="$TMP_DIR/converted"
TMP_UPSCALED_DIR="$TMP_DIR/upscaled"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ ! -d "$INPUT_DIR" ]]; then
  echo "Input directory not found: $INPUT_DIR"
  exit 1
fi

echo "Applying $THEME theme to wallpapers in $INPUT_DIR"
mkdir -p "$TMP_CONVERTED_DIR" "$TMP_UPSCALED_DIR" "$OUTPUT_DIR"

found=0
while IFS= read -r -d '' _; do
  found=$((found + 1))
done < <(find "$INPUT_DIR" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) -print0)

if [[ "$found" -eq 0 ]]; then
  echo "No files found in $INPUT_DIR"
  exit 1
fi

processed=0
convert_failed=0
upscale_failed=0
generated=0
upscale_available=1
upscale_setup_missing=0
while IFS= read -r -d '' src; do
  processed=$((processed + 1))
  base_name="$(basename "$src")"
  converted_path="$TMP_CONVERTED_DIR/$base_name"
  upscaled_path="$TMP_UPSCALED_DIR/$base_name"

  convert_output=""
  if ! convert_output="$(gowall convert "$src" -t "$THEME" --output "$converted_path" </dev/null 2>&1)"; then
    echo "Failed to convert: $base_name"
    if [[ -n "$convert_output" ]]; then
      echo "$convert_output"
    fi
    convert_failed=$((convert_failed + 1))
    continue
  fi

  upscale_output=""
  if [[ "$upscale_available" -eq 1 ]] && gowall upscale "$converted_path" -s "$UPSCALE_SCALE" -m "$UPSCALE_MODEL" --output "$upscaled_path" </dev/null >/dev/null 2>"$TMP_DIR/upscale.err"; then
    final_path="$upscaled_path"
  else
    if [[ "$upscale_available" -eq 1 ]]; then
      upscale_output="$(cat "$TMP_DIR/upscale.err" || true)"
      echo "Upscaling skipped for: $base_name"
      if [[ -n "$upscale_output" ]]; then
        echo "$upscale_output"
      fi
      if [[ "$upscale_output" == *"the upscaler has not been setup"* ]]; then
        upscale_setup_missing=1
        upscale_available=0
        echo "Upscaler is not set up in this environment; disabling further upscale attempts."
      fi
    else
      echo "Upscaling skipped for: $base_name (upscaler unavailable in this run)"
    fi
    upscale_failed=$((upscale_failed + 1))
    if [[ "$UPSCALE_STRICT" == "true" ]]; then
      continue
    fi
    final_path="$converted_path"
  fi

  if [[ -e "$OUTPUT_DIR/$base_name" ]]; then
    echo "Overwriting existing file: $base_name"
  fi
  mv -f -- "$final_path" "$OUTPUT_DIR/$base_name"
  generated=$((generated + 1))
done < <(find "$INPUT_DIR" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) -print0)

if [[ "$convert_failed" -gt 0 ]]; then
  echo "Failed to convert $convert_failed image(s)."
  exit 1
fi

if [[ "$UPSCALE_STRICT" == "true" && "$upscale_failed" -gt 0 ]]; then
  echo "Upscaling failed for $upscale_failed image(s) with UPSCALE_STRICT=true."
  exit 1
fi

expected_generated=$((processed - convert_failed))
if [[ "$UPSCALE_STRICT" == "true" ]]; then
  expected_generated=$((expected_generated - upscale_failed))
fi
if [[ "$generated" -ne "$expected_generated" ]]; then
  echo "Expected $expected_generated generated file(s), produced $generated."
  exit 1
fi

echo "Generated $generated Catppuccin wallpapers in $OUTPUT_DIR (upscale failures: $upscale_failed)"
if [[ "$upscale_setup_missing" -eq 1 ]]; then
  echo "Note: run gowall upscale interactively once to set up the upscaler, then re-run generation."

fi