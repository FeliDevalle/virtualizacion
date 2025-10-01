#!/usr/bin/env bash

set -euo pipefail

# Variables vacías
archivo=""
patrones=""

# Parseo de argumentos
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -d|--directorio)
            archivo="$2"
            shift 2
            ;;
        -p|--palabras)
            patrones="$2"
            shift 2
            ;;
        *)
            echo "Parámetro desconocido: $1"
            echo "Uso: $0 -d archivo.log -p \"patron1,patron2\""
            exit 1
            ;;
    esac
done

# Validación
if [[ -z "$archivo" || -z "$patrones" ]]; then
    echo "Faltan parámetros obligatorios."
    echo "Uso: $0 -d archivo.log -p \"patron1,patron2\""
    exit 1
fi

# Separar por coma en array
IFS=',' read -r -a lista <<< "$patrones"

for patron in "${lista[@]}"; do
    # Trim espacios alrededor del patrón
    patron="$(echo "$patron" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    # Contar coincidencias case-insensitive con awk
    count=$(awk -v p="$patron" 'BEGIN{IGNORECASE=1} $0 ~ p {c++} END{print c+0}' "$archivo")
    printf '%s: %d\n' "$patron" "$count"
done