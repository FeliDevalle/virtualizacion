#!/bin/bash
#Integrantes:
#   CORONEL, THIAGO MARTÍN
#   DEVALLE, FELIPE PEDRO
#   MURILLO, JOEL ADAN
#   RUIZ, RAFAEL DAVID NAZARENO

# --- Función de Ayuda ---
uso() {
    echo "Uso: $0 -r <repo> -c <config> [-l <log>]"
    echo "       $0 -r <repo> -k"
    echo ""
    echo "  -r, --repo            Ruta al repositorio Git a monitorear. (Obligatorio)"
    echo "  -c, --configuracion   Nombre del archivo de patrones de búsqueda (debe estar en el mismo directorio del script). (Obligatorio para iniciar)" ### CAMBIO ###
    echo "  -l, --log             Nombre del archivo de log (se creará en el mismo directorio del script). (Default: audit.log)" ### CAMBIO ###
    echo "  -k, --kill            Detiene el demonio en ejecución para el repositorio especificado."
    exit 1
}

REPO=""
CONFIG_NAME="patrones.conf" 
LOGFILE_NAME="audit.log"    
KILL_FLAG=false

if [ $# -eq 0 ]; then
    uso
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -r|--repo)
            REPO="$2"; shift 2;;
        -c|--configuracion)
            CONFIG_NAME="$2"; shift 2;; ### CAMBIO ### Ahora guarda solo el nombre del archivo
        -l|--log)
            LOGFILE_NAME="$2"; shift 2;; ### CAMBIO ### Ahora guarda solo el nombre del archivo
        -k|--kill)
            KILL_FLAG=true; shift;;
        *)
            echo "Error: Parámetro desconocido: $1" >&2
            uso;;
    esac
done


if [[ -z "$REPO" ]]; then
    echo "Error: La ruta al repositorio (-r) es obligatoria." >&2
    uso
fi


SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
CONFIG="$SCRIPT_DIR/$CONFIG_NAME"       
LOGFILE="$SCRIPT_DIR/$LOGFILE_NAME"     

REPO_ABS=$(readlink -f "$REPO")
PIDFILE="/tmp/git_monitor_$(echo "$REPO_ABS" | sha256sum | awk '{print $1}').pid"


if $KILL_FLAG; then
    if [[ -f "$PIDFILE" ]]; then
        PID_TO_KILL=$(cat "$PIDFILE")
        if ps -p "$PID_TO_KILL" > /dev/null; then
            echo "Deteniendo el demonio con PID $PID_TO_KILL para el repositorio '$REPO'..."
            kill "$PID_TO_KILL"
            sleep 1
            if ! ps -p "$PID_TO_KILL" > /dev/null; then
                echo "Demonio detenido con éxito."
                rm -f "$PIDFILE"
            else
                echo "Error: No se pudo detener el demonio. Intente con 'kill -9 $PID_TO_KILL'." >&2
            fi
        else
            echo "Advertencia: Se encontró un archivo PID obsoleto. El proceso $PID_TO_KILL no existe. Limpiando..."
            rm -f "$PIDFILE"
        fi
    else
        echo "No se encontró un demonio en ejecución para este repositorio."
    fi
    exit 0
fi

if [[ -z "$CONFIG_NAME" ]]; then 
    echo "Error: El nombre del archivo de configuración (-c) es obligatorio para iniciar el demonio." >&2
    uso
fi
if [[ ! -d "$REPO/.git" ]]; then
    echo "Error: La ruta '$REPO' no parece ser un repositorio Git válido." >&2
    exit 1
fi
if [[ ! -f "$CONFIG" ]]; then 
    echo "Error: Archivo de configuración '$CONFIG' no encontrado en el directorio del script." >&2
    exit 1
fi

if [[ ! -w "$(dirname "$LOGFILE")" ]]; then 
    echo "Error: No se puede escribir en el directorio de logs '$LOGFILE'." >&2
    exit 1
fi

if [[ -f "$PIDFILE" ]]; then
    if ps -p "$(cat "$PIDFILE")" > /dev/null; then
        echo "Error: Ya hay un demonio en ejecución para este repositorio (PID: $(cat "$PIDFILE"))." >&2
        exit 1
    else
        echo "Advertencia: Se encontró un archivo PID obsoleto. Limpiando..."
        rm -f "$PIDFILE"
    fi
fi

iniciar_demonio() {
    cd "$REPO" || exit 1

    BRANCH=$(git rev-parse --abbrev-ref HEAD)
    if [[ -z "$BRANCH" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: No se pudo detectar la rama principal del repositorio." >> "$LOGFILE"
        exit 1
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') - Demonio iniciado. Monitoreando '$REPO_ABS' en la rama '$BRANCH'." >> "$LOGFILE"

    LAST_COMMIT=$(git rev-parse HEAD)

    while true; do
        CURRENT_COMMIT=$(git rev-parse HEAD)

        if [[ "$CURRENT_COMMIT" != "$LAST_COMMIT" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Nuevos cambios detectados. Analizando commits desde $LAST_COMMIT a $CURRENT_COMMIT." >> "$LOGFILE"
            git diff --name-only "$LAST_COMMIT" "$CURRENT_COMMIT" | while IFS= read -r FILE; do
                [[ -z "$FILE" || ! -f "$FILE" ]] && continue
                while IFS= read -r PATTERN_LINE; do
                    if [[ -z "$PATTERN_LINE" ]] || [[ "$PATTERN_LINE" == \#* ]]; then
                        continue
                    fi
                    if [[ "$PATTERN_LINE" == regex:* ]]; then
                        PATTERN="${PATTERN_LINE#regex:}"
                        if grep -qE -- "$PATTERN" "$FILE"; then

                             echo "$(date '+%Y-%m-%d %H:%M:%S') - Alerta [Regex]: Patrón '$PATTERN' encontrado en el archivo '$FILE'." >> "$LOGFILE"
                        fi
                    else
                        PATTERN="$PATTERN_LINE"
                        if grep -qF -- "$PATTERN" "$FILE"; then
                             
                             echo "$(date '+%Y-%m-%d %H:%M:%S') - Alerta [Texto]: Patrón '$PATTERN' encontrado en el archivo '$FILE'." >> "$LOGFILE"
                        fi
                    fi
                done < "$CONFIG" 
            done
            LAST_COMMIT="$CURRENT_COMMIT"
        fi
        
        sleep 10
    done
}


(
    trap 'rm -f "$PIDFILE"' EXIT
    iniciar_demonio
) &

echo $! > "$PIDFILE"

echo "Demonio iniciado en segundo plano con PID $(cat "$PIDFILE")."

exit 0