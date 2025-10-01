#!/usr/bin/env bash

#Integrantes:
#    CORONEL, THIAGO MARTÍN
#    DEVALLE, FELIPE PEDRO
#    MURILLO, JOEL ADAN
#    RUIZ, RAFAEL DAVID NAZARENO

set -euo pipefail

# --- Funciones ---
usage() {
    cat <<EOF
Uso: $0 -d <directorio> -p "<patron1,patron2,...>"

Opciones:
  -d, --directorio   Directorio que contiene archivos .log a analizar (acepta rutas con espacios).
  -p, --palabras     Lista de palabras clave separadas por comas (ej: "usb,invalid").
  -h, --help         Mostrar esta ayuda.
EOF
}

error_handler() {
    local exit_code=$?
    local last_cmd="${BASH_COMMAND:-unknown}"
    echo "ERROR: El comando '${last_cmd}' falló con código ${exit_code}."
    echo "Por favor revise los parámetros y permisos. Para ayuda: $0 --help"
    # Aquí podrías eliminar temporales si existieran
    exit "$exit_code"
}

cleanup() {
    # eliminar temporales si los hubiera (ninguno en este script)
    :
}

# Atrapar errores y finalización
trap error_handler ERR
trap cleanup EXIT

# --- Parseo de argumentos ---
directorio=""
patrones=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--directorio)
            directorio="$2"
            shift 2
            ;;
        -p|--palabras)
            patrones="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Parámetro desconocido: $1"
            usage
            exit 1
            ;;
    esac
done

# --- Validaciones ---
if [[ -z "$directorio" || -z "$patrones" ]]; then
    echo "Faltan parámetros obligatorios."
    usage
    exit 1
fi

# Aceptar rutas con ~ y expandir
directorio="$(eval printf '%s' "$directorio")"

if [[ ! -e "$directorio" ]]; then
    echo "El directorio especificado no existe: '$directorio'"
    exit 1
fi

if [[ ! -d "$directorio" ]]; then
    echo "La ruta especificada no es un directorio: '$directorio'"
    exit 1
fi

# Construir lista de archivos .log en el directorio (no recursivo)
mapfile -d '' archivos < <(find "$directorio" -maxdepth 1 -type f -name '*.log' -print0)

if [[ ${#archivos[@]} -eq 0 ]]; then
    echo "No se encontraron archivos .log en el directorio: '$directorio'"
    # Salir con código 0 porque es un caso válido, pero sin resultados
    exit 0
fi

# --- Procesamiento ---
IFS=',' read -r -a lista <<< "$patrones"

for patron_raw in "${lista[@]}"; do
    # Trim espacios
    patron="$(echo "$patron_raw" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    # Ejecutar awk sobre todos los archivos encontrados
    # Usamos IGNORECASE para case-insensitive
    count=$(awk -v p="$patron" 'BEGIN{IGNORECASE=1} $0 ~ p {c++} END{print c+0}' "${archivos[@]}")
    printf '%s: %d\n' "$patron" "$count"
done

# Si llegó hasta acá, éxito
exit 0
