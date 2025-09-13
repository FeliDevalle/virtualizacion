#!/bin/bash

REPO=""
CONFIG=""
LOGFILE="./audit.log"
PIDFILE=""
SLEEP_INTERVAL=10

uso() {
    echo "Uso: $0 -r <repo> -c <config> [-l <log>] [-k]"
    echo "  -r | --repo          Ruta al repositorio Git"
    echo "  -c | --configuracion Ruta al archivo de patrones"
    echo "  -l | --log           Ruta al archivo de log (default ./audit.log)"
    echo "  -k | --kill          Detiene el demonio en ejecución"
    exit 1
}
<


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

if [[ -z "$REPO" ]]; then uso; fi
PIDFILE="/tmp/audit_$(echo $REPO | sed 's#[/ ]#_#g').pid"

if [[ "$KILL" == 1 ]]; then
    if [[ -f "$PIDFILE" ]]; then
        kill "$(cat $PIDFILE)" && rm -f "$PIDFILE"
        echo "Demonio detenido."
    else
        echo "No hay demonio en ejecución para este repositorio."
    fi
    exit 0
fi

if [[ ! -d "$REPO/.git" ]];then
    echo "Error: $REPO no es un repositorio Git válido."
    exit 1
fi
if [[ ! -f "$CONFIG" ]]; then
    echo "Error: Archivo de configuración $CONFIG no encontrado."
    exit 1
fi

if [[ -f "$PIDFILE" ]] && kill -0 "$(cat $PIDFILE)" 2>/dev/null; then
    echo "Error: Ya hay un demonio en ejecución para este repositorio."
    exit 1
fi

# Detectar rama principal (master o main)
BRANCH=$(git -C "$REPO" remote show origin | grep 'HEAD branch' | awk '{print $NF}')
if [[ -z "$BRANCH" ]]; then
    BRANCH="master"
fi

# Verificar que la rama remota existe
if ! git -C "$REPO" ls-remote --exit-code origin "$BRANCH" &>/dev/null; then
    echo "Error: La rama remota '$BRANCH' no existe en el remoto 'origin'."
    exit 1
fi

(
    cd "$REPO" || exit 1
    git fetch origin "$BRANCH" &> /dev/null
    LAST_COMMIT=$(git rev-parse "origin/$BRANCH")
    echo $$ > "$PIDFILE"
    echo "Demonio iniciado con PID $$, monitoreando $REPO"
    while true; do
        git fetch origin "$BRANCH" &> /dev/null
        NEW_COMMIT=$(git rev-parse "origin/$BRANCH")
        if [[ "$NEW_COMMIT" != "$LAST_COMMIT" ]]; then
            FILES=$(git diff --name-only "$LAST_COMMIT" "$NEW_COMMIT")
            for FILE in $FILES; do
                if [[ -f "$FILE" ]]; then
                    while IFS= read -r PATTERN; do
                        if grep -qE "$PATTERN" "$FILE"; then
                            echo "$(date '+%Y-%m-%d %H:%M:%S') - ALERT: Pattern '$PATTERN' found in file '$FILE' in commit '$NEW_COMMIT'" >> "$LOGFILE"
                        fi
                    done < "$CONFIG"
                fi
            done
            LAST_COMMIT="$NEW_COMMIT"
        fi
        sleep "$SLEEP_INTERVAL"
    done
) &
