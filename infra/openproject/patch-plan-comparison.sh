#!/bin/sh
set -eu

patch_file() {
  file="$1"
  [ -f "$file" ] || return 0

  ruby -0777 -i -pe '
    gsub(/toggle_title:\s*ベースライン/, "toggle_title: 計画比較")
    gsub(/"toggle_title"\s*:\s*"ベースライン"/, %q{"toggle_title":"計画比較"})
    gsub(/toggle_title:\s*"ベースライン"/, %q{toggle_title:"計画比較"})
    gsub(/toggle_title:\s*"Baseline"/, %q{toggle_title:"Plan comparison"})
    gsub(/"toggle_title"\s*:\s*"Baseline"/, %q{"toggle_title":"Plan comparison"})
  ' "$file"
}

patch_file /app/config/locales/crowdin/js-ja.yml
patch_file /app/config/locales/crowdin/js-en.yml

find /app/public/assets/frontend -type f \( -name '*.js' -o -name '*.mjs' \) -exec grep -IlE 'ベースライン|Baseline' {} + \
  | while IFS= read -r file; do
      if grep -qE 'ベースライン|Baseline' "$file"; then
        patch_file "$file"
      fi
    done
