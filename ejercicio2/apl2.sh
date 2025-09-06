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
	origen=0
	dist=()
	prev=()
	visited=()
	INF=999999
	for ((i=0; i<filas; i++)); do
		dist[$i]=$INF
		prev[$i]=-1
		visited[$i]=0
	done
	dist[$origen]=0

	for ((count=0; count<filas; count++)); do
		u=-1
		min=$INF
		for ((i=0; i<filas; i++)); do
			if [[ ${visited[$i]} -eq 0 && ${dist[$i]} -lt $min ]]; then
				min=${dist[$i]}
				u=$i
			fi
		done

		if [[ $u -eq -1 ]]; then
			break
		fi

		visited[$u]=1

		for ((v=0; v<columnas; v++)); do
			peso=${matriz[$((u*filas + v))]}
			if [[ $peso -ne 0 ]]; then
				if (( dist[$u] + peso < dist[$v] )); then
					dist[$v]=$((dist[$u] + peso))
					prev[$v]=$u
				fi
			fi
		done
	done

	for ((i=0; i<filas; i++)); do
    	if [[ $i -ne $origen ]]; then
        	if [[ ${dist[$i]} -eq $INF ]]; then
            	echo "No hay camino de $((origen+1)) a $((i+1))"
        	else
            	camino=$(reconstruir_camino $i)
            	echo "Camino más corto de $((origen+1)) a $((i+1)): tiempo ${dist[$i]}, ruta $camino"
        	fi
    	fi
	done

fi

