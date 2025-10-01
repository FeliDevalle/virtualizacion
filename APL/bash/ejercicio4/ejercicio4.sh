#!/bin/bash
#Integrantes:
#    CORONEL, THIAGO MARTÍN
#    DEVALLE, FELIPE PEDRO
#    MURILLO, JOEL ADAN
#    RUIZ, RAFAEL DAVID NAZARENO

# Valores por defecto
REPO=""
CONFIG=""
LOGFILE="./audit.log"
PIDFILE=""
SLEEP_INTERVAL=10

uso() {
    echo "Uso: $0 -r <repo> -c <config> [-a <segundos>] [-l <log>] [-k]"
    echo "  -r | --repo           Ruta al repositorio Git"
    echo "  -c | --configuracion  Ruta al archivo de patrones"
    echo "  -l | --log            Ruta al archivo de log (default: ./audit.log)"
    echo "  -k | --kill           Detiene el demonio en ejecución para el repositorio"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -r|--repo)
            REPO="$2"; shift 2;;
        -c|--configuracion)
            CONFIG="$2"; shift 2;;
        -l|--log)
            LOGFILE="$2"; shift 2;;
        -k|--kill)
            KILL=1; shift;;
        *)
            uso;;
    esac
done

if [[ -z "$REPO" ]]; then
    echo "Error: La ruta al repositorio es obligatoria."
    uso
fi

PIDFILE="/tmp/audit_$(echo "$REPO" | sed 's#[/ ]#_#g').pid"

if [[ "$KILL" == 1 ]]; then
    if [[ -f "$PIDFILE" ]]; then
        PID_TO_KILL=$(cat "$PIDFILE")
        if kill -0 "$PID_TO_KILL" 2>/dev/null; then
            kill "$PID_TO_KILL" && rm -f "$PIDFILE"
            echo "Demonio con PID $PID_TO_KILL detenido."
        else
            echo "El proceso del demonio no existía. Limpiando archivo PID."
            rm -f "$PIDFILE"
        fi
    else
        echo "No se encontró un demonio en ejecución para este repositorio."
    fi
    exit 0
fi

if [[ -z "$CONFIG" ]]; then
    echo "Error: El archivo de configuración de patrones es obligatorio."
    uso
fi

if [[ ! -d "$REPO/.git" ]]; then
    echo "Error: $REPO no es un repositorio Git válido."
    exit 1
fi
if [[ ! -f "$CONFIG" ]]; then
    echo "Error: Archivo de configuración $CONFIG no encontrado."
    exit 1
fi

if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "Error: Ya hay un demonio en ejecución para este repositorio (PID: $(cat "$PIDFILE"))."
    exit 1
fi

(
    # Cambiamos al directorio del repositorio para que los comandos git funcionen
    cd "$REPO" || exit 1

    # Detectar rama principal (usualmente 'main' o 'master')
    BRANCH=$(git remote show origin | grep 'HEAD branch' | awk '{print $NF}')
    if [[ -z "$BRANCH" ]]; then
        echo "No se pudo detectar la rama principal. Usando 'main' por defecto." | tee -a "$LOGFILE"
        BRANCH="main"
    fi

    # Obtenemos el último commit de la rama remota como punto de partida
    git fetch origin "$BRANCH" &> /dev/null
    LAST_COMMIT=$(git rev-parse "origin/$BRANCH")

    # Escribimos el PID del proceso actual (el subshell) en el archivo PID
    echo $$ > "$PIDFILE"
    
    echo "Demonio iniciado con PID $$. Monitoreando la rama '$BRANCH' de '$REPO'."
    #echo "$(date '+%Y-%m-%d %H:%M:%S') - Demonio iniciado. Monitoreando '$REPO' en la rama '$BRANCH'." >> "$LOGFILE"

    while true; do
        # Busca cambios en el remoto sin modificar los archivos locales
        git fetch origin "$BRANCH" &> /dev/null
        NEW_COMMIT=$(git rev-parse "origin/$BRANCH")

        # Si el commit más reciente es diferente al que ya revisamos...
        if [[ "$NEW_COMMIT" != "$LAST_COMMIT" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Nuevo commit detectado: $NEW_COMMIT" >> "$LOGFILE"

            # <--- CORRECCIÓN: Bucle robusto para manejar nombres de archivo con espacios
            git diff --name-only "$LAST_COMMIT" "$NEW_COMMIT" | while IFS= read -r FILE; do
                # Procesamos cada patrón del archivo de configuración
                while IFS= read -r PATTERN_LINE; do
                    # Saltamos líneas vacías o comentarios
                    if [[ -z "$PATTERN_LINE" ]] || [[ "$PATTERN_LINE" == \#* ]]; then
                        continue
                    fi

                    # <--- CORRECCIÓN: Manejo del prefijo 'regex:'
                    if [[ "$PATTERN_LINE" == regex:* ]]; then
                        # Si la línea empieza con 'regex:', quitamos el prefijo
                        CURRENT_PATTERN="${PATTERN_LINE#regex:}"
                    else
                        # Si no, es un patrón de texto simple
                        CURRENT_PATTERN="$PATTERN_LINE"
                    fi
                    
                    if git show "$NEW_COMMIT:$FILE" 2>/dev/null | grep -qE -- "$CURRENT_PATTERN"; then
                        # <--- CORRECCIÓN: Usamos '>>' para agregar al log en lugar de sobrescribir
                        echo "$(date '+%Y-%m-%d %H:%M:%S') - Alerta: Patrón '$CURRENT_PATTERN' encontrado en el archivo '$FILE'." >> "$LOGFILE"
                    fi
                done < "$CONFIG"
            done
            # Actualizamos la referencia al último commit revisado
            LAST_COMMIT="$NEW_COMMIT"
        fi
        
        # Esperamos el intervalo definido antes de volver a chequear
        sleep "$SLEEP_INTERVAL"
    done
) & # El '&' al final envía todo el bloque '(..)' a segundo plano, liberando la terminal.
