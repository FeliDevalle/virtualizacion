#!/bin/bash

#archivo="mapa_transporte.txt"
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
		-h|--hub)
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
	IFS="$SEPARADOR" read -r -a fila <<< "$linea"

	if [ $filas -eq 0 ]; then
		columnas=${#fila[@]}
	fi

	if [ ${#fila[@]} -ne $columnas ]; then
		echo "La matriz no es cuadrada: fila $((filas+1))"
		exit 1
	fi

	for valor in "${fila[@]}"; do 
		if ! [[ $valor =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
			echo "Valor invalido en fila $((filas+1)): $valor"
			exit 1
		fi
		matriz+=("$valor")
	done
	
	filas=$((filas+1))
done < "$MATRIZ"
echo "$filas-$columnas"
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
	echo "Buscando camino corto..."
fi

