#Integrantes:
#    CORONEL, THIAGO MARTÍN
#    DEVALLE, FELIPE PEDRO
#    MURILLO, JOEL ADAN
#    RUIZ, RAFAEL DAVID NAZARENO

Param(
    [Alias("M")]
    [string]$Matriz,
    [switch]$Hub,
    [switch]$Camino,
    [string]$Separador = "|",
    [switch]$Help
)

function Show-Help {
    Write-Output @"
Analiza rutas en una red de transporte público representada como una matriz de adyacencia.
Opciones:
    -M, --Matriz <archivo>      Ruta del archivo que contiene la matriz de adyacencia.
    -Hub                        Determina qué estación es el 'hub' de la red.
    -Camino                     Encuentra el camino más corto entre todas las estaciones (usando Floyd-Warshall).
    -Separador <carácter>       Carácter utilizado como separador de columnas en la matriz.
    -Help                       Muestra este mensaje de ayuda.

Consideraciones:
    La salida se guardará en un archivo: informe.<nombreArchivoEntrada>
"@
}

if ($Help) {
    Show-Help
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Matriz)) {
    Write-Error "Debe especificar la matriz con -M"
    exit 1
}
if (-not (Test-Path $Matriz)) {
    Write-Error "El archivo de matriz '$Matriz' no existe en la ruta actual: $PWD"
    exit 1
}

if (-not $Hub -and -not $Camino) {
    Write-Error "No se especificó qué hacer (-Hub o -Camino)"
    exit 1
}
if ($Hub -and $Camino) {
    Write-Error "No se puede usar -Hub junto con -Camino"
    exit 1
}

# Leer la matriz
$matrizDeDatos = @()
$filas = 0
$columnas = 0

Get-Content $Matriz | ForEach-Object {
    $linea = $_.Trim()
    if ($linea -eq "") { return }
    $fila = $linea -split [regex]::Escape($Separador)

    if ($filas -eq 0) { $columnas = $fila.Count }
    if ($fila.Count -ne $columnas) {
        Write-Error "La matriz no es cuadrada"
        exit 1
    }

    foreach ($valor in $fila) {
        if ($valor -notmatch '^\d+(\.\d+)?$') {
            Write-Error "Valor inválido: $valor"
            exit 1
        }
        $matrizDeDatos += [double]$valor
    }
    $filas++
}

if ($filas -ne $columnas) {
    Write-Error "No es una matriz cuadrada ($filas x $columnas)"
    exit 1
}

# Validar diagonal
for ($i=0; $i -lt $filas; $i++) {
    $indice = $i * $columnas + $i
    if ($matrizDeDatos[$indice] -ne 0) {
        Write-Error "La diagonal principal no es 0 en la posición $i,$i"
        exit 1
    }
}

# Validar simetría
for ($i=0; $i -lt $filas; $i++) {
    for ($j=0; $j -lt $columnas; $j++) {
        if ($matrizDeDatos[$i*$columnas + $j] -ne $matrizDeDatos[$j*$columnas + $i]) {
            Write-Error "La matriz no es simétrica: ($i,$j) != ($j,$i)"
            exit 1
        }
    }
}
#Write-Output "La matriz es válida"

# Preparar archivo salida
$dirEntrada = Split-Path $Matriz
$nombreEntrada = Split-Path $Matriz -Leaf
$archivoSalida = Join-Path $dirEntrada "informe.$nombreEntrada"

# --- CORRECCIÓN 2: Asegurar que el informe se sobrescriba ---
# Si el archivo de informe ya existe, lo eliminamos para empezar de cero.
if (Test-Path $archivoSalida) {
    Remove-Item $archivoSalida
}
# -----------------------------------------------------------------

""## Informe de analisis de red de transporte (Algoritmo: Floyd-Warshall)" | Out-File $archivoSalida
"## Archivo analizado: $nombreEntrada`n" | Out-File $archivoSalida -Append

# --- Hub ---
if ($Hub) {
    $maxConex = 0
    $hubs = @()

    for ($i=0; $i -lt $filas; $i++) {
        $conexiones = 0
        for ($j=0; $j -lt $columnas; $j++) {
            if ($i -ne $j) {
                $val = $matrizDeDatos[$i*$filas + $j]
                if ($val -gt 0) { $conexiones++ }
            }
        }
        if ($conexiones -gt $maxConex) {
            $maxConex = $conexiones
            $hubs = @($i+1)
        } elseif ($conexiones -eq $maxConex -and $conexiones -ne 0) {
            $hubs += ($i+1)
        }
    }

    if ($maxConex -eq 0) {
        "**Hub de la red:** Ninguna estación tiene conexiones directas." | Tee-Object -FilePath $archivoSalida -Append
    } elseif ($hubs.Count -eq 1) {
        "**Hub de la red:** Estación $($hubs[0]) ($maxConex conexiones)" | Tee-Object -FilePath $archivoSalida -Append
    } else {
        "**Hubs de la red (empate):** Estaciones $($hubs -join ', ') ($maxConex conexiones)" | Tee-Object -FilePath $archivoSalida -Append
    }
}

# --- Floyd-Warshall ---
function Reconstruir-Camino {
    param($i, $j, $next, $n)
    if ($next[$i*$n + $j] -eq -1) { return "" }
    $caminoInterno = @($i+1) # Usamos una variable interna para no generar conflictos
    while ($i -ne $j) {
        $i = $next[$i*$n + $j]
        $caminoInterno += ($i+1)
    }
    return ($caminoInterno -join " -> ")
}

if ($Camino) {
    $INF = 999999
    
    $totalElementos = $filas * $columnas
    $dist = @(0) * $totalElementos
    $next = @(0) * $totalElementos

    # (El resto del código de inicialización de la matriz de distancias no cambia)
    for ($i=0; $i -lt $filas; $i++) {
        for ($j=0; $j -lt $columnas; $j++) {
            $val = $matrizDeDatos[$i*$filas + $j]
            $indice = $i*$filas + $j
            if ($i -eq $j) {
                $dist[$indice] = 0
                $next[$indice] = $i
            } elseif ($val -gt 0) {
                $dist[$indice] = $val
                $next[$indice] = $j
            } else {
                $dist[$indice] = $INF
                $next[$indice] = -1
            }
        }
    }

    # (El código del algoritmo de Floyd-Warshall no cambia)
    for ($k=0; $k -lt $filas; $k++) {
        for ($i=0; $i -lt $filas; $i++) {
            for ($j=0; $j -lt $columnas; $j++) {
                $ik = $dist[$i*$filas + $k]
                $kj = $dist[$k*$filas + $j]
                $ij = $dist[$i*$filas + $j]
                if ($ik + $kj -lt $ij) {
                    $dist[$i*$filas + $j] = $ik + $kj
                    $next[$i*$filas + $j] = $next[$i*$filas + $k]
                }
            }
        }
    }

    "**Analisis de caminos mas cortos (Floyd-Warshall):**" | Out-File $archivoSalida -Append
    for ($i=0; $i -lt $filas; $i++) {
        for ($j=0; $j -lt $columnas; $j++) {
            if ($i -ne $j) {
                $distancia = $dist[$i*$filas + $j]
                if ($distancia -eq $INF) {
                    "De Estacion $($i+1) a Estacin $($j+1): No hay camino." | Out-File $archivoSalida -Append
                } else {
                    $rutaDelCamino = Reconstruir-Camino $i $j $next $filas
                    "De Estacion $($i+1) a Estacion $($j+1): tiempo $distancia, ruta: $rutaDelCamino" | Out-File $archivoSalida -Append
                }
            }
        }
    }

    # --- NUEVO CÓDIGO AÑADIDO ---
    # Busca la ruta más rápida de todo el sistema.
    $distanciaMasRapida = $INF
    $estacionInicio = -1
    $estacionFin = -1

    for ($i = 0; $i -lt $filas; $i++) {
        for ($j = 0; $j -lt $columnas; $j++) {
            if ($i -ne $j) {
                $distanciaActual = $dist[$i * $filas + $j]
                if ($distanciaActual -lt $distanciaMasRapida) {
                    $distanciaMasRapida = $distanciaActual
                    $estacionInicio = $i + 1
                    $estacionFin = $j + 1
                }
            }
        }
    }

    # Añade el resultado al archivo de informe.
    if ($estacionInicio -ne -1) {
        "`n**Ruta mas rapida de toda la red:**" | Out-File $archivoSalida -Append
        "De Estacion $estacionInicio a Estacion $estacionFin con un tiempo de $distanciaMasRapida." | Out-File $archivoSalida -Append
    }
    # --- FIN DEL NUEVO CÓDIGO ---
}

Write-Output "Informe generado con exito en: $archivoSalida"
exit 0