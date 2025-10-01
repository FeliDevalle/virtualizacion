#!/usr/bin/env bash
# Buscar y contar patrones en un archivo (case-insensitive)
# Uso: ./buscar_log.sh archivo.log "patron1,patron2,..."

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Uso: $0 archivo.log \"patron1,patron2,...\""
  exit 1
fi

archivo="$1"
patrones="$2"

# Separar por coma en array
IFS=',' read -r -a lista <<< "$patrones"

for patron in "${lista[@]}"; do
  # Trim espacios alrededor del patrón
  patron="$(echo "$patron" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  # Contar coincidencias case-insensitive con awk
  count=$(awk -v p="$patron" 'BEGIN{IGNORECASE=1} $0 ~ p {c++} END{print c+0}' "$archivo")
  # Capitalizar primera letra para salida estética (requiere bash >= 4)
  pretty="${patron,,}"
  pretty="${pretty^}"
  printf '%s: %d\n' "$pretty" "$count"
done
