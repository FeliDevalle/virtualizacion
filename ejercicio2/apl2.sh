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

ayuda()
{
	echo "
	Analiza rutas en una red de transporte público representada como una matriz de adyacencia.
	Opciones:
  		-m, --matriz <archivo>       Ruta del archivo que contiene la matriz de adyacencia.
  		-h, --hub                    Determina qué estación es el "hub" de la red.
        	                        No se puede usar junto con -c / --camino.
  		-c, --camino                 Encuentra el camino más corto en tiempo entre todas
        	                        las estaciones usando el algoritmo de Dijkstra.
            	                    No se puede usar junto con -h / --hub.
  		-s, --separador <carácter>   Carácter utilizado como separador de columnas en la matriz.
  		--help                       Muestra este mensaje de ayuda y sale del script.

	Consideraciones:
  		1. El archivo de entrada debe contener una matriz cuadrada y simétrica.
  		2. Los valores de la matriz deben ser numéricos (enteros o decimales).
  		3. El script generará un archivo de salida llamado:
        	informe.<nombreArchivoEntrada> en el mismo directorio del archivo original."
}



MATRIZ=""
HUB=false
CAMINO=false
SEPARADOR=""
matriz=()
filas=0
columnas=0

while [[ $# -gt 0 ]]; do
	case $1 in
		-m|--matriz)
			MATRIZ="$2"
			shift 2
			;;
		-u|--hub)
			HUB=true
			shift
			;;
		-c|--camino)
			CAMINO=true
			shift
			;;
		-s|--separador)
			SEPARADOR="$2"
			shift 2
			;;
		*)
			echo "Parametro desconocido: $1"
			exit 1
			;;
	esac
done

if [ "$HUB" = false ] && [ "$CAMINO" = false ];then
	echo "No se especifico que hacer"
	exit 1
fi

if [ "$HUB" = true ] && [ "$CAMINO" = true ]; then
	echo "No se puede usar -h/-hub junto con -c/--camino"
	exit 1
fi

if [ -z "$MATRIZ" ]; then
	echo "Debe especificar la matriz"
	exit 1
fi

while IFS= read -r linea; do
	linea="${linea//$'\r'/}"
	IFS="$SEPARADOR" read -r -a fila <<< "$linea"

	if [ $filas -eq 0 ]; then
		columnas=${#fila[@]}
	fi

	if [ ${#fila[@]} -ne $columnas ]; then
		echo "La matriz no es cuadrada: fila $((filas+1))"
		exit 1
	fi

	for valor in "${fila[@]}"; do 
		
		if ! [[ "$valor" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
			echo "Valor invalido en fila $((filas+1)): $valor"
			exit 1
		fi
		matriz+=("$valor")
	done
	
	filas=$((filas+1))
done < "$MATRIZ"
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

if [ "$HUB" = true ]; then
	max_conex=0
	hubs=()
	for((i=0; i<filas; i++)); do
		conexiones=0
		for((j=0; j<columnas; j++)); do
			if [ $i -eq $j ]; then
				continue
			fi
			val="${matriz[$((i*filas + j))]}"
			if ! [[ $val =~ ^0+([.][0]+)?$ ]]; then
				conexiones=$((conexiones+1))
			fi
		done

		if [ $conexiones -gt $max_conex ]; then
			max_conex=$conexiones
			hubs=("$((i+1))")
		elif [ $conexiones -eq $max_conex ];then
			hubs+=("$((i+1))")
		fi
	done
	if [ $max_conex -eq 0 ]; then
  		echo "Ninguna estación tiene conexiones directas."
	else
  		if [ ${#hubs[@]} -eq 1 ]; then
			echo "Hub de la red: Estación ${hubs[0]}: (${max_conex})"
  		else
    			echo "Hubs (empate): Estaciones ${hubs[*]}"
  		fi
	fi
fi

if [ "$CAMINO" = true ]; then
    INF=999999
    # inicializar matriz de distancias
    dist=()
    next=()

    for ((i=0; i<filas; i++)); do
        for ((j=0; j<columnas; j++)); do
            val=${matriz[$((i*filas + j))]}
            if [[ $i -eq $j ]]; then
                dist[$((i*filas + j))]=0
                next[$((i*filas + j))]=-1
            elif [[ $val -ne 0 ]]; then
                dist[$((i*filas + j))]=$val
                next[$((i*filas + j))]=$j
            else
                dist[$((i*filas + j))]=$INF
                next[$((i*filas + j))]=-1
            fi
        done
    done

    # algoritmo de Floyd–Warshall
    for ((k=0; k<filas; k++)); do
        for ((i=0; i<filas; i++)); do
            for ((j=0; j<columnas; j++)); do
                if (( dist[i*filas + k] + dist[k*filas + j] < dist[i*filas + j] )); then
                    dist[$((i*filas + j))]=$((dist[i*filas + k] + dist[k*filas + j]))
                    next[$((i*filas + j))]=${next[$((i*filas + k))]}
                fi
            done
        done
    done

    # reconstrucción del camino
    reconstruir_camino_floyd() {
        local u=$1
        local v=$2
        if [[ ${next[$((u*filas + v))]} -eq -1 ]]; then
            echo ""
            return
        fi
        local path=($((u+1)))
        while [[ $u -ne $v ]]; do
            u=${next[$((u*filas + v))]}
            path+=($((u+1)))
        done
        echo "${path[*]}"
    }

    # imprimir resultados
    for ((i=0; i<filas; i++)); do
        for ((j=0; j<columnas; j++)); do
            if [[ $i -ne $j ]]; then
                if [[ ${dist[$((i*filas + j))]} -eq $INF ]]; then
                    echo "No hay camino entre $((i+1)) y $((j+1))"
                else
                    camino=$(reconstruir_camino_floyd $i $j)
                    echo "Camino más corto de $((i+1)) a $((j+1)): tiempo ${dist[$((i*filas + j))]}, ruta $camino"
                fi
            fi
        done
    done
fi
exit 0

