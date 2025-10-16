#!/bin/bash

#Integrantes:
#   CORONEL, THIAGO MARTÍN
#   DEVALLE, FELIPE PEDRO
#   MURILLO, JOEL ADAN
#   RUIZ, RAFAEL DAVID NAZARENO

reconstruir_camino_floyd() {
    local u=$1
    local v=$2
    
    if [[ ${next[$((u*filas + v))]} -eq -1 ]]; then
        echo "No hay camino"
        return
    fi
    
    local path=("$((u + 1))")
    while [[ $u -ne $v ]]; do
        u=${next[$((u*filas + v))]}
        path+=("$((u + 1))")
    done
    
    echo "${path[*]}"
}

ayuda() {
    echo "
    Uso: $0 -m <archivo> [-h | -c] [-s <separador>]

    Analiza rutas en una red de transporte público.

    Opciones:
        -m, --matriz <archivo>      Ruta del archivo con la matriz de adyacencia. (Obligatorio)
        -h, --hub                   Determina la estación con más conexiones ('hub').
        -c, --camino                Encuentra el camino más corto entre todos los pares de estaciones.
        -s, --separador <carácter>  Separador de columnas en la matriz. Por defecto: '|'.
        --help                      Muestra esta ayuda.

    Consideraciones:
        - Las opciones -h y -c son mutuamente excluyentes.
        - La salida se guarda en 'informe.<nombreArchivoEntrada>' y se sobrescribe en cada ejecución."
}

MATRIZ_PATH=""
HUB=false
CAMINO=false
SEPARADOR="|"
matriz=()
filas=0
columnas=0

while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--matriz)
            MATRIZ_PATH="$2"; shift 2;;
        -h|--hub)
            HUB=true; shift;;
        -c|--camino)
            CAMINO=true; shift;;
        -s|--separador)
            SEPARADOR="$2"; shift 2;;
        --help)
            ayuda; exit 0;;
        *)
            echo "Error: Parámetro desconocido: $1" >&2
            ayuda
            exit 1;;
    esac
done

if [[ -z "$MATRIZ_PATH" ]]; then
    echo "Error: Debe especificar la ruta de la matriz con -m." >&2
    ayuda
    exit 1
fi
if ! [[ -f "$MATRIZ_PATH" && -r "$MATRIZ_PATH" ]]; then
    echo "Error: El archivo '$MATRIZ_PATH' no existe o no se puede leer." >&2
    exit 1
fi
if [ "$HUB" = false ] && [ "$CAMINO" = false ]; then
    echo "Error: Debe especificar una acción: -h (hub) o -c (camino)." >&2
    ayuda
    exit 1
fi
if [ "$HUB" = true ] && [ "$CAMINO" = true ]; then
    echo "Error: No se puede usar -h y -c al mismo tiempo." >&2
    ayuda
    exit 1
fi
if [ -z "$SEPARADOR" ]; then
    echo "Error: El separador (-s) no puede estar vacío." >&2
    exit 1
fi

while IFS= read -r linea; do
    linea="${linea//[$'\r\n']/}"
    if [[ -z "$linea" ]]; then continue; fi
    
    IFS="$SEPARADOR" read -r -a fila <<< "$linea"
    
    if [ $filas -eq 0 ]; then columnas=${#fila[@]}; fi
    
    if [ ${#fila[@]} -ne $columnas ]; then
        echo "Error: La matriz no es uniforme. La fila $((filas+1)) tiene ${#fila[@]} elementos, pero se esperaban $columnas." >&2
        exit 1
    fi
    
    for valor in "${fila[@]}"; do
        if ! [[ "$valor" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            echo "Error: La matriz contiene un valor no numérico: '$valor'." >&2
            exit 1
        fi
        matriz+=("$valor")
    done
    filas=$((filas+1))
done < "$MATRIZ_PATH"

if [ $filas -ne $columnas ]; then
	echo "Error: No es una matriz cuadrada (dimensiones: $filas x $columnas)." >&2
	exit 1
fi

for ((i=0; i<filas; i++)); do
	indice=$((i*columnas + i))
	if (( $(echo "${matriz[$indice]} != 0" | bc -l) )); then
		echo "Error: La diagonal principal debe ser 0. El valor en la posición ($((i+1)),$((i+1))) no es cero." >&2
		exit 1
	fi
done

for ((i=0; i<filas; i++)); do
	for((j=i+1; j<columnas; j++)); do
		if (( $(echo "${matriz[$((i*columnas + j))]} != ${matriz[$((j*columnas + i))]}" | bc -l) )); then
			echo "Error: La matriz no es simétrica. El valor en ($((i+1)),$((j+1))) es distinto al de ($((j+1)),$((i+1)))." >&2
			exit 1
		fi
	done
done
echo "La matriz es válida."

DIR_ENTRADA=$(dirname "$MATRIZ_PATH")
NOMBRE_ARCHIVO_ENTRADA=$(basename "$MATRIZ_PATH")
ARCHIVO_SALIDA="$DIR_ENTRADA/informe.$NOMBRE_ARCHIVO_ENTRADA"

echo "## Informe de Análisis de Red de Transporte" > "$ARCHIVO_SALIDA"
echo "## Archivo analizado: $NOMBRE_ARCHIVO_ENTRADA" >> "$ARCHIVO_SALIDA"
echo "" >> "$ARCHIVO_SALIDA"

if [ "$HUB" = true ]; then
    echo "## Análisis de Hub de la Red" >> "$ARCHIVO_SALIDA"
    max_conex=0; hubs=()
    for((i=0; i<filas; i++)); do
        conexiones=0
        for((j=0; j<columnas; j++)); do
            if [ $i -ne $j ]; then
                val="${matriz[$((i*filas + j))]}"
                if (( $(echo "$val > 0" | bc -l) )); then
                    conexiones=$((conexiones+1))
                fi
            fi
        done
        if [ $conexiones -gt $max_conex ]; then
            max_conex=$conexiones
            hubs=("$((i+1))")
        elif [ $conexiones -eq $max_conex ] && [ $conexiones -ne 0 ]; then
            hubs+=("$((i+1))")
        fi
    done
    if [ $max_conex -eq 0 ]; then
        echo "**Hub de la red:** Ninguna estación tiene conexiones." >> "$ARCHIVO_SALIDA"
    elif [ ${#hubs[@]} -eq 1 ]; then
        echo "**Hub de la red:** Estación ${hubs[0]} ($max_conex conexiones)" >> "$ARCHIVO_SALIDA"
    else<
        echo "**Hubs de la red (empate):** Estaciones ${hubs[*]} ($max_conex conexiones)" >> "$ARCHIVO_SALIDA"
    fi
fi

if [ "$CAMINO" = true ]; then
    echo "## Análisis de Caminos Más Cortos (Floyd-Warshall)" >> "$ARCHIVO_SALIDA"
    INF=999999
    dist=(); next=()

    for ((i=0; i<filas; i++)); do
        for ((j=0; j<columnas; j++)); do
            val=${matriz[$((i*filas + j))]}
            indice=$((i*filas + j))
            if [[ $i -eq $j ]]; then
                dist[$indice]=0
                next[$indice]=$j
            elif (( $(echo "$val > 0" | bc -l) )); then
                dist[$indice]=$val
                next[$indice]=$j
            else
                dist[$indice]=$INF
                next[$indice]=-1
            fi
        done
    done

    for ((k=0; k<filas; k++)); do
        for ((i=0; i<filas; i++)); do
            for ((j=0; j<columnas; j++)); do
                dist_ik=${dist[$((i*filas + k))]}
                dist_kj=${dist[$((k*filas + j))]}
                
                if [[ $dist_ik == $INF || $dist_kj == $INF ]]; then continue; fi
                
                suma_caminos=$(echo "$dist_ik + $dist_kj" | bc)
                dist_ij=${dist[$((i*filas + j))]}
                
                if (( $(echo "$suma_caminos < $dist_ij" | bc -l) )); then
                    dist[$((i*filas + j))]=$suma_caminos
                    next[$((i*filas + j))]=${next[$((i*filas + k))]}
                fi
            done
        done
    done

    for ((i=0; i<filas; i++)); do
        for ((j=0; j<columnas; j++)); do
            if [[ $i -ne $j ]]; then
                distancia_final=${dist[$((i*filas + j))]}
                if [ "$distancia_final" == "$INF" ]; then
                    echo "De Estación $((i+1)) a Estación $((j+1)): No hay camino." >> "$ARCHIVO_SALIDA"
                else
                    camino=$(reconstruir_camino_floyd $i $j)
                    echo "De Estación $((i+1)) a Estación $((j+1)): tiempo $distancia_final, ruta: ${camino// / -> }" >> "$ARCHIVO_SALIDA"
                fi
            fi
        done
    done
fi

echo "Informe generado con éxito en: $ARCHIVO_SALIDA"
exit 0