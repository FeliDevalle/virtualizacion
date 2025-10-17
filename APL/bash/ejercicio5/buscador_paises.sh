#!/bin/bash
#Integrantes:
#    CORONEL, THIAGO MARTÍN
#    DEVALLE, FELIPE PEDRO
#    MURILLO, JOEL ADAN
#    RUIZ, RAFAEL DAVID NAZARENO

# === CONFIGURACIÓN DE CACHÉ ===
CACHE_DIR="/tmp/bash_paises_cache"
mkdir -p "$CACHE_DIR"
CACHE_FILE="$CACHE_DIR/cache_paises.txt"

NOMBRES=()
TTL=""

# === FUNCIÓN DE AYUDA ===
mostrar_ayuda() {
    cat << EOF
Uso: $0 -n <pais1> [pais2 ...] -t <ttl_en_segundos>

Opciones:
  -n <pais1> [pais2 ...]  Nombre(s) del país a consultar (ej: argentina spain)
  -t <segundos>           Tiempo de validez del caché en segundos
  -h, --help              Muestra esta ayuda

Ejemplo:
  $0 -n spain argentina brazil -t 3600
EOF
}

# === CONSULTAR API Y GUARDAR EN CACHÉ ===
consultar_api() {
    local pais="$1"
    local url="https://restcountries.com/v3.1/name/$pais"
    curl -s "$url" > "$CACHE_FILE.tmp"

    if [[ $? -ne 0 || ! -s "$CACHE_FILE.tmp" ]]; then
        echo "Error: No se pudo obtener información de la API para '$pais'" >&2
        rm -f "$CACHE_FILE.tmp"
        return 1
    fi

    local fecha json_oneline
    fecha=$(date +%s)
    json_oneline=$(tr '\n' ' ' < "$CACHE_FILE.tmp" | sed 's/  */ /g')
    echo "$pais|$fecha|$json_oneline" >> "$CACHE_FILE"

    echo "$json_oneline" > "$CACHE_FILE.tmp"
    return 0
}

# === BUSCAR EN CACHÉ ===
buscar_cache() {
    local pais="$1"
    if [[ ! -f "$CACHE_FILE" ]]; then
        return 1
    fi

    local linea nombre_guardado fecha_guardada json_guardado ahora diferencia
    linea=$(grep -i "^${pais}|" "$CACHE_FILE" 2>/dev/null | tail -n 1)
    if [[ -z "$linea" ]]; then
        return 1
    fi

    nombre_guardado="${linea%%|*}"
    local rest="${linea#*|}"
    fecha_guardada="${rest%%|*}"
    json_guardado="${rest#*|}"

    ahora=$(date +%s)
    diferencia=$((ahora - fecha_guardada))

    if [[ $diferencia -lt $TTL ]]; then
        echo "$json_guardado" > "$CACHE_FILE.tmp"
        return 0
    else
        return 1
    fi
}

# === MOSTRAR RESULTADO EN FORMATO REQUERIDO ===
mostrar_resultado() {
    awk '
    BEGIN {
        country=""; capital=""; region=""; population=""; curcode=""; curname="";
    }
    {
        line = $0

        if (match(line, /"name"[[:space:]]*:[[:space:]]*{[^}]*"common"[[:space:]]*:[[:space:]]*"([^"]*)"/, m))
            country = m[1]

        if (match(line, /"capital"[[:space:]]*:[[:space:]]*\["?([^"\]]*)"?/, m))
            capital = m[1]

        if (match(line, /"region"[[:space:]]*:[[:space:]]*"([^"]*)"/, m))
            region = m[1]

        if (match(line, /"population"[[:space:]]*:[[:space:]]*([0-9]+)/, m))
            population = m[1]

        if (match(line, /"currencies"[[:space:]]*:[[:space:]]*{[^}]*"([^"]+)"[[:space:]]*:[[:space:]]*{[^}]*"name"[[:space:]]*:[[:space:]]*"([^"]*)"/, m)) {
            curcode = m[1]
            curname = m[2]
        }

        if (country != "") {
            print "País: " country
            if (capital != "") print "Capital: " capital
            if (region != "") print "Región: " region
            if (population != "") print "Población: " population
            if (curname != "") {
                printf "Moneda: %s", curname
                if (curcode != "") printf " (%s)", curcode
                printf "\n"
            }
            exit
        }
    }' "$CACHE_FILE.tmp"
}

# === PARSEO DE PARÁMETROS ===
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--nombre)
            shift
            while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                NOMBRES+=("$1")
                shift
            done
            ;;
        -t|--ttl)
            TTL="$2"
            shift 2
            ;;
        -h|--help)
            mostrar_ayuda
            exit 0
            ;;
        *)
            echo "Parámetro desconocido: $1" >&2
            mostrar_ayuda
            exit 1
            ;;
    esac
done

# === VALIDACIONES ===
if [[ ${#NOMBRES[@]} -eq 0 || -z "$TTL" ]]; then
    mostrar_ayuda
    exit 1
fi

# === LÓGICA PRINCIPAL PARA CADA PAÍS ===
for NOMBRE in "${NOMBRES[@]}"; do
    if ! buscar_cache "$NOMBRE"; then
        consultar_api "$NOMBRE" || continue
        buscar_cache "$NOMBRE" || { echo "Error leyendo caché después de la consulta" >&2; continue; }
    fi
    mostrar_resultado
    echo "----------------------------"
done
