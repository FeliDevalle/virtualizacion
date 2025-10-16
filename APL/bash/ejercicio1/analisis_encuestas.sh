# ==========================================================
# Script: analisis_encuestas.sh
# Objetivo: Procesar encuestas de satisfacción y generar
#           un resumen en formato JSON por fecha y canal.
#Integrantes:
#    CORONEL, THIAGO MARTÍN
#    DEVALLE, FELIPE PEDRO
#    MURILLO, JOEL ADAN
#    RUIZ, RAFAEL DAVID NAZARENO
# ==========================================================


# -------- Variables globales --------
DIR_INPUT=""
ARCHIVO_SALIDA=""
MODO_PANTALLA=false
TMP_FILE="/tmp/encuestas_$$.tmp"

# -------- Limpieza en salida o error --------
trap 'rm -f "$TMP_FILE"' EXIT

# -------- Funciones --------

mostrar_ayuda() {
    cat << EOF
Uso: $0 -d <directorio> [-a <archivo_salida.json> | -p]

Opciones:
  -d <directorio>       Directorio donde están los archivos de encuestas
  -a <archivo_salida>   Ruta completa del archivo JSON de salida
  -p                    Muestra la salida por pantalla (no se puede usar con -a)
  -h, --help            Muestra esta ayuda

Descripción:
  El script procesa todos los archivos de encuestas en el directorio indicado.
  Calcula el tiempo de respuesta promedio y la nota de satisfacción promedio
  por canal y por día, mostrando el resultado en formato JSON.

Ejemplo:
  $0 -d ./datos -a ./salida.json
  $0 -d ./datos -p
EOF
}

validar_parametros() {
    if [[ -z "$DIR_INPUT" ]]; then
        echo "Error: Debe indicar un directorio con -d" >&2
        mostrar_ayuda
        exit 1
    fi

    if [[ ! -d "$DIR_INPUT" ]]; then
        echo "Error: El directorio '$DIR_INPUT' no existe o no es válido" >&2
        exit 1
    fi

    if [[ -n "$ARCHIVO_SALIDA" && "$MODO_PANTALLA" = true ]]; then
        echo "Error: No se puede usar -a y -p al mismo tiempo" >&2
        exit 1
    fi

    if [[ -z "$ARCHIVO_SALIDA" && "$MODO_PANTALLA" = false ]]; then
        echo "Error: Debe usar -a o -p para indicar la salida" >&2
        exit 1
    fi
}

procesar_archivos() {
    awk -F"|" '
    {
        fecha = substr($2,1,10)   # yyyy-mm-dd
        canal = $3
        tiempo = $4
        nota = $5

        suma_tiempo[fecha "|" canal] += tiempo
        suma_nota[fecha "|" canal]   += nota
        conteo[fecha "|" canal]++
    }
    END {
        printf "{\n"
        first_date = 1
        for (key in conteo) {
            split(key, arr, "|")
            fecha = arr[1]
            canal = arr[2]

            tiempo_prom = suma_tiempo[key] / conteo[key]
            nota_prom   = suma_nota[key]   / conteo[key]

            if (!(fecha in fechas)) {
                fechas[fecha] = 1
                lista_fechas[++n_fechas] = fecha
            }

            datos[fecha, canal] = sprintf("{ \"tiempo_promedio\": %.2f, \"nota_promedio\": %.2f }", tiempo_prom, nota_prom)
        }

        n = asort(lista_fechas, ordenadas)

        for (i=1; i<=n; i++) {
            fecha = ordenadas[i]
            if (!first_date) printf ",\n"
            first_date=0
            printf "  \"%s\": {\n", fecha

            first_canal=1
            for (k in datos) {
                split(k, arr, SUBSEP)
                if (arr[1] == fecha) {
                    if (!first_canal) printf ",\n"
                    first_canal=0
                    printf "    \"%s\": %s", arr[2], datos[k]
                }
            }
            printf "\n  }"
        }
        printf "\n}\n"
    }' "$DIR_INPUT"/*.txt > "$TMP_FILE"
}

mostrar_resultado() {
    if [[ "$MODO_PANTALLA" = true ]]; then
        cat "$TMP_FILE"
    else
        mv "$TMP_FILE" "$ARCHIVO_SALIDA"
        echo "Archivo JSON generado en: $ARCHIVO_SALIDA"
    fi
}

# -------- Programa principal --------

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "Error: Falta la ruta del directorio después de -d" >&2
                mostrar_ayuda
                exit 1
            fi
            DIR_INPUT="$2"
            shift 2
            ;;
        -a)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "Error: Falta la ruta del archivo después de -a" >&2
                mostrar_ayuda
                exit 1
            fi
            ARCHIVO_SALIDA="$2"
            shift 2
            ;;
        -p)
            MODO_PANTALLA=true
            shift
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


validar_parametros
procesar_archivos
mostrar_resultado
