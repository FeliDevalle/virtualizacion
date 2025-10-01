#!/bin/bash
#Integrantes:
#    CORONEL, THIAGO MARTÍN
#    DEVALLE, FELIPE PEDRO
#    MURILLO, JOEL ADAN
#    RUIZ, RAFAEL DAVID NAZARENO

CACHE_FILE="$(dirname "$0")/cache_paises.txt"
DIR_CACHE=$(dirname "$CACHE_FILE")
mkdir -p "$DIR_CACHE"

NOMBRE=""
TTL=""

mostrar_ayuda() {
    cat << EOF
Uso: $0 -n <pais> -t <ttl_en_segundos>

Opciones:
  -n <pais>           Nombre del país a consultar (ej: spain)
  -t <segundos>       Tiempo de validez del caché en segundos
  -h, --help          Muestra esta ayuda

Ejemplo:
  $0 -n spain -t 3600
EOF
}

consultar_api() {
    curl -s "https://restcountries.com/v3.1/name/$NOMBRE" > "$CACHE_FILE.tmp"
    if [[ $? -ne 0 || ! -s "$CACHE_FILE.tmp" ]]; then
        echo "Error: No se pudo obtener información de la API" >&2
        rm -f "$CACHE_FILE.tmp"
        exit 1
    fi
    fecha=$(date +%s)
    # Guardamos: NOMBRE|timestamp|JSON (JSON en una sola línea)
    json_oneline=$(tr '\n' ' ' < "$CACHE_FILE.tmp" | sed 's/  */ /g')
    echo "$NOMBRE|$fecha|$json_oneline" >> "$CACHE_FILE"
    # dejamos copia temporal para parsear
    echo "$json_oneline" > "$CACHE_FILE.tmp"
}

buscar_cache() {
    if [[ ! -f "$CACHE_FILE" ]]; then
        return 1
    fi

    # Buscar la última entrada del país (case-insensitive)
    linea=$(grep -i "^${NOMBRE}|" "$CACHE_FILE" 2>/dev/null | tail -n 1)
    if [[ -z "$linea" ]]; then
        return 1
    fi

    nombre_guardado="${linea%%|*}"
    rest="${linea#*|}"
    fecha_guardada="${rest%%|*}"
    json_guardado="${rest#*|}"

    ahora=$(date +%s)
    diferencia=$((ahora - fecha_guardada))

    if [[ $diferencia -lt $TTL ]]; then
        # guardar JSON en tmp para que lo lea el parser
        echo "$json_guardado" > "$CACHE_FILE.tmp"
        return 0
    else
        return 1
    fi
}

mostrar_resultado() {
    # El JSON está en una sola línea en $CACHE_FILE.tmp
    awk '
    BEGIN {
        in_name = 0; in_currencies = 0;
        country=""; capital=""; region=""; population=""; curcode=""; curname="";
        found = 0;
    }
    {
        # procesamos la linea completa (JSON en una sola línea)
        line = $0

        # BUSCAR name.common dentro del bloque "name": { ... }
        if (match(line, /"name"[[:space:]]*:[[:space:]]*{[^}]*"common"[[:space:]]*:[[:space:]]*"([^"]*)"/, m)) {
            country = m[1]
        }

        # BUSCAR capital (primer elemento del array)
        if (match(line, /"capital"[[:space:]]*:[[:space:]]*\["?([^"\]]*)"?/, m)) {
            capital = m[1]
        }

        # BUSCAR region
        if (match(line, /"region"[[:space:]]*:[[:space:]]*"([^"]*)"/, m)) {
            region = m[1]
        }

        # BUSCAR population
        if (match(line, /"population"[[:space:]]*:[[:space:]]*([0-9]+)/, m)) {
            population = m[1]
        }

        # BUSCAR currencies: obtenemos el primer par "COD":{... "name":"NOMBRE" ...}
        if (match(line, /"currencies"[[:space:]]*:[[:space:]]*{[^}]*"([^"]+)"[[:space:]]*:[[:space:]]*{[^}]*"name"[[:space:]]*:[[:space:]]*"([^"]*)"/, m)) {
            curcode = m[1]; curname = m[2]
        }

        # Imprimir si al menos encontramos el nombre (name.common)
        if (country != "") {
            print "País: " country
            if (capital != "") print "Capital: " capital
            if (region != "") print "Región: " region
            if (population != "") print "Población: " population
            if (curname != "") {
                # si tenemos curname y curcode mostramos: Moneda: Euro (EUR)
                printf "Moneda: %s", curname
                if (curcode != "") printf " (%s)", curcode
                printf "\n"
            }
            found = 1
            exit
        } else {
            # si no encontramos country, imprimimos mensaje de error mínimo
            print "No se pudo extraer la información esperada del JSON." > "/dev/stderr"
            exit 1
        }
    }' "$CACHE_FILE.tmp"
}

# --- parsear parametros (simple)
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--nombre)
            NOMBRE="$2"
            shift 2
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

# validaciones básicas
if [[ -z "$NOMBRE" || -z "$TTL" ]]; then
    mostrar_ayuda
    exit 1
fi

if ! buscar_cache; then
    consultar_api
    buscar_cache || { echo "Error leyendo cache despues de consulta" >&2; exit 1; }
fi

mostrar_resultado

