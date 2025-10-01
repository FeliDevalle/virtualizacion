<#
.SYNOPSIS
    Script que analiza archivos de logs en un directorio para contar la ocurrencia de palabras claves específicas.
.DESCRIPTION
    Grupo 1
    Integrantes:
    CORONEL, THIAGO MARTÍN
    DEVALLE, FELIPE PEDRO
    MURILLO, JOEL ADAN
    RUIZ, RAFAEL DAVID NAZARENO

    El script analiza todos los archivos de logs (.log) en un directorio
    y cuenta la ocurrencia de eventos/palabras clave proporcionadas.

.PARAMETER directorio
    Ruta del directorio con los archivos logs.
.PARAMETER palabras
    Lista de palabras clave a buscar en los archivos logs (separadas por coma o espacio).
.EXAMPLE
    ./apl3.ps1 -d directorio -p palabra1,palabra2
.EXAMPLE
    ./apl3.ps1 -d directorio -p palabra1 palabra2
.OUTPUTS
    Conteo de ocurrencias por palabra clave.
    Exit codes:
        0 - Ejecución correcta
        2 - El directorio no existe
        3 - El directorio no tiene archivos
        4 - No se proporcionaron palabras clave válidas
#>
param(
    [Alias("p")]
    [Parameter(Mandatory = $true)]
    [string[]]$palabras,  

    [Alias("d")]
    [Parameter(Mandatory = $true)]
    [string]$directorio
)

function Validaciones {
    param(
        [string]$directorio, 
        [string[]]$palabras
    )

    #Validar directorio
    if (-not (Test-Path -Path $directorio -PathType Container)) {
        Write-Error "El directorio '$directorio' no existe."
        exit 2
    }

    #Validar archivos .log
    $archivos = Get-ChildItem -Path $directorio -Filter *.log -File
    if (-not $archivos) {
        Write-Error "El directorio '$directorio' no contiene archivos .log."
        exit 3
    }

    # Validar palabras clave
    if (-not $palabras -or $palabras.Where({ -not [string]::IsNullOrWhiteSpace($_) }).Count -eq 0) {
        Write-Error "No se proporcionaron palabras clave validas."
        exit 4
    }
}

function procesar {
    param(
        [System.IO.FileInfo[]]$archivos,
        [string[]]$palabras
    )

    $resultados = @{}
    foreach ($palabra in $palabras) {
        $resultados[$palabra.Trim()] = 0
    }

    foreach ($archivo in $archivos) {
        $lineas = Get-Content -Path $archivo.FullName
        foreach ($linea in $lineas) {
            $lineaLower = $linea.ToLower()
            foreach ($palabra in $palabras) {
                $palabraLower = $palabra.Trim().ToLower()
                if ($lineaLower.Contains($palabraLower)) {
                    $resultados[$palabra.Trim()]++
                }
            }
        }
    }
    return $resultados
}


function main {
    validaciones -directorio $directorio -palabras $palabras

    $archivos = Get-ChildItem -Path $directorio -Filter *.log -File
    $resultados = procesar -archivos $archivos -palabras $palabras

    foreach ($key in $resultados.Keys) {
        Write-Host "$key : $($resultados[$key])"
    }
}

main
