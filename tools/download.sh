#!/usr/bin/env bash
# Fetch the pinned TwIL-8B GGUF (QUANT + VARIANT) into /models. Resumable, sha256 checked. A later start is a no-op
# once the revision stamp matches.
set -euo pipefail

dest=/models
model_id=${MODEL_ID:-webAI-Official/TwIL-8B}
revision=${MODEL_REVISION:-58d49f0d9909e62f9c2fb09e99fc5c76f3f2d630}
file="TwIL-8B-${QUANT:-Q4_K_M}-${VARIANT:-balanced}.gguf"

# sha256 of each file at the pinned revision (Hugging Face LFS oid). balanced only ships as Q4_K_M.
declare -A SHA=(
  [TwIL-8B-Q4_K_M-balanced.gguf]=17bda82d2608ca61b6aca48394f212349ef1515d0d9a2e6edee06619152faa0e
  [TwIL-8B-Q4_K_M-verbose.gguf]=5646abbb98f6ab81cfb9f7590aef894011ba50a259fb5d5aac8284d154e64ef0
  [TwIL-8B-Q8_0-verbose.gguf]=6242f84e5d9854ca54a9f39dd14dadbd9eaad5b3d2bc6195d408cae69e8f85d6
  [TwIL-8B-F16-verbose.gguf]=c5d8f7d35d82c38e845f23612513ac49333e5fa23a1788d843449124e13b64bd
)

curl_fetch() {
  local url=$1 path=$2
  local -a args=(-fL --retry 8 --retry-delay 2 --retry-all-errors -C - --output "$path")
  [[ -n ${HF_TOKEN:-} ]] && args+=(-H "Authorization: Bearer ${HF_TOKEN}")
  curl "${args[@]}" "$url"
}

fetch() {
  local name=$1
  local expect=${SHA[$name]:-}
  if [[ -z $expect ]]; then
    echo "no checksum for ${name}; known files: ${!SHA[*]}" >&2
    exit 1
  fi
  local path=$dest/$name stamp=$dest/.$name.sha256 url="https://huggingface.co/${model_id}/resolve/${revision}/${name}"
  if [[ -f $stamp && $(<"$stamp") != "$revision $expect" ]]; then
    echo "revision changed, re-downloading $name"
    rm -f "$path" "$stamp"
  fi
  if [[ -f $path && -f $stamp ]]; then
    echo "present $name"
    return
  fi
  mkdir -p "$dest"
  # A complete file without a stamp (copied in, or an interrupted check) is checked rather than fetched again.
  if [[ ! -f $path ]] || [[ $(sha256sum "$path" | awk 'NR==1 { print $1 }') != "$expect" ]]; then
    echo "downloading $name"
    curl_fetch "$url" "$path"
    if [[ $(sha256sum "$path" | awk 'NR==1 { print $1 }') != "$expect" ]]; then
      echo "checksum mismatch for $name, downloading again" >&2
      rm -f "$path"
      curl_fetch "$url" "$path"
      [[ $(sha256sum "$path" | awk 'NR==1 { print $1 }') == "$expect" ]] || { echo "checksum mismatch for $name" >&2; exit 1; }
    fi
  fi
  printf '%s %s\n' "$revision" "$expect" >"$stamp"
  echo "verified $name"
}

fetch "$file"
exit 0
