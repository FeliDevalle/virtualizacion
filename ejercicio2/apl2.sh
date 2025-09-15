#!/bin/bash
reconstruir_camino() {
    local destino=$1
    local path=()
    while [[ $destino -ne -1 ]]; do
        path=("$((destino+1))" "${path[@]}")
        destino=${prev[$destino]}
    done
    echo "${path[*]}"
}

ayuda() {
    echo "
    Analiza rutas en una red de transporte público representada como una matriz de adyacencia.
    Opciones:
        -m, --matriz <archivo>      Ruta del archivo que contiene la matriz de adyacencia.
        -h, --hub                   Determina qué estación es el 'hub' de la red.
        -c, --camino                Encuentra el camino más corto entre todas las estaciones (usando Floyd-Warshall).
        -s, --separador <carácter>  Carácter utilizado como separador de columnas en la matriz.
        --help                      Muestra este mensaje de ayuda.

    Consideraciones:
        La salida se guardará en un archivo: informe.<nombreArchivoEntrada>"
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
        -h|--hub) # <--- CORRECCIÓN: Unificado con la ayuda (-h en vez de -u)
            HUB=true; shift;;
        -c|--camino)
            CAMINO=true; shift;;
        -s|--separador)
            SEPARADOR="$2"; shift 2;;
        --help)
            ayuda; exit 0;;
        *)
            echo "Parámetro desconocido: $1"; ayuda; exit 1;;
    esac
done

if [ "$HUB" = false ] && [ "$CAMINO" = false ];then
    echo "No se especificó qué hacer (-h o -c)"; exit 1
fi
if [ "$HUB" = true ] && [ "$CAMINO" = true ]; then
    echo "No se puede usar -h/-hub junto con -c/--camino"; exit 1
fi
if [ -z "$MATRIZ_PATH" ]; then
    echo "Debe especificar la matriz con -m"; exit 1
fi


while IFS= read -r linea; do
    linea="${linea//[$'\r\n']/}"
    if [[ -z "$linea" ]]; then continue; fi
    IFS="$SEPARADOR" read -r -a fila <<< "$linea"
    if [ $filas -eq 0 ]; then columnas=${#fila[@]}; fi
    if [ ${#fila[@]} -ne $columnas ]; then echo "La matriz no es cuadrada"; exit 1; fi
    for valor in "${fila[@]}"; do 
        if ! [[ "$valor" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            echo "Valor inválido: $valor"; exit 1
        fi
        matriz+=("$valor")
    done
    filas=$((filas+1))
done < "$MATRIZ_PATH"

if [ $filas -ne $columnas ]; then
	echo "No es una matriz cuadrada ($filas x $columnas)"
	exit 1
fi

for ((i=0; i<filas; i++)); do
	indice=$((i*columnas + i))
	if [ "${matriz[$indice]}" != "0" ]; then
		echo "La diagonal principal no es 0 en la posicion $i, $i"
		exit 1
	fi
done

for ((i=0; i<filas; i++)); do
	for((j=0; j<columnas; j++)); do
		if [ "${matriz[$((i*columnas + j))]}" != "${matriz[$((j*columnas + i))]}" ]; then
			echo "La matriz no es simetrica: ($i, $j) != ($j, $i)"
			exit 1
		fi
	done
done
echo "La matriz es valida"

DIR_ENTRADA=$(dirname "$MATRIZ_PATH")
NOMBRE_ARCHIVO_ENTRADA=$(basename "$MATRIZ_PATH")
ARCHIVO_SALIDA="$DIR_ENTRADA/informe.$NOMBRE_ARCHIVO_ENTRADA"> "$ARCHIVO_SALIDA"
echo "## Informe de análisis de red de transporte (Algoritmo: Floyd-Warshall)" >> "$ARCHIVO_SALIDA"
echo "## Archivo analizado: $NOMBRE_ARCHIVO_ENTRADA" >> "$ARCHIVO_SALIDA"
echo "" >> "$ARCHIVO_SALIDA"

if [ "$HUB" = true ]; then
    max_conex=0; hubs=()
    for((i=0; i<filas; i++)); do
        conexiones=0
        for((j=0; j<columnas; j++)); do
            if [ $i -ne $j ]; then
                val="${matriz[$((i*filas + j))]}"
                if [ "$(echo "$val > 0" | bc)" -eq 1 ]; then
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
		echo "**Hub de la red:** Ninguna estación tiene conexiones directas."
        echo "**Hub de la red:** Ninguna estación tiene conexiones directas." >> "$ARCHIVO_SALIDA"
    elif [ ${#hubs[@]} -eq 1 ]; then
		echo "**Hub de la red:** Estación ${hubs[0]} ($max_conex conexiones)"
        echo "**Hub de la red:** Estación ${hubs[0]} ($max_conex conexiones)" >> "$ARCHIVO_SALIDA"
    else
		echo "**Hubs de la red (empate):** Estaciones ${hubs[*]} ($max_conex conexiones)"
        echo "**Hubs de la red (empate):** Estaciones ${hubs[*]} ($max_conex conexiones)" >> "$ARCHIVO_SALIDA"
    fi
fi

if [ "$CAMINO" = true ]; then
    INF=999999
    dist=(); next=()
    for ((i=0; i<filas; i++)); do
        for ((j=0; j<columnas; j++)); do
            val=${matriz[$((i*filas + j))]}
            indice=$((i*filas + j))
            if [[ $i -eq $j ]]; then
                dist[$indice]=0
                next[$indice]=$i
            elif [ "$(echo "$val > 0" | bc)" -eq 1 ]; then
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
                dist_ij=${dist[$((i*filas + j))]}
                
                suma_caminos=$(echo "$dist_ik + $dist_kj" | bc)
                
                if (( $(echo "$suma_caminos < $dist_ij" | bc -l) )); then
                    dist[$((i*filas + j))]=$suma_caminos
                    next[$((i*filas + j))]=${next[$((i*filas + k))]}
                fi
            done
        done
    done
    
    echo "**Análisis de caminos más cortos (Floyd-Warshall):**" >> "$ARCHIVO_SALIDA"
    for ((i=0; i<filas; i++)); do
        for ((j=0; j<columnas; j++)); do
            if [[ $i -ne $j ]]; then
                distancia_final=${dist[$((i*filas + j))]}
                if [ "$distancia_final" == "$INF" ]; then
                    echo "De Estación $((i+1)) a Estación $((j+1)): No hay camino." >> "$ARCHIVO_SALIDA"
                else
                    camino=$(reconstruir_camino_floyd $i $j next)
                    echo "De Estación $((i+1)) a Estación $((j+1)): tiempo $distancia_final, ruta: $camino" >> "$ARCHIVO_SALIDA"
                fi
            fi
        done
    done
fi

echo "Informe generado con éxito en: $ARCHIVO_SALIDA"
exit 0

