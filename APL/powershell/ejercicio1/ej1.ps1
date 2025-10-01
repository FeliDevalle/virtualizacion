<#
.SYNOPSIS
    Procesa archivos de encuestas y genera un promedio por canal.
.DESCRIPTION
    Grupo 1
    Integrantes:
    CORONEL, THIAGO MARTÍN
    DEVALLE, FELIPE PEDRO
    MURILLO, JOEL ADAN
    RUIZ, RAFAEL DAVID NAZARENO

    Este script procesara todos los archivos de encuestas en un directorio,
    calculara el tiempo de respuesta promedio y la nota de satisfacción promedio
    por canal de atención y por dia.
    El resultado se mostrara por pantalla o se guardará en un archivo JSON.
.PARAMETER directorio
    Ruta del directorio con los archivos de encuestas.
.PARAMETER archivo
    Ruta + nombre del archivo JSON de salida.
.PARAMETER pantalla
    Switch: muestra por pantalla en lugar de guardar en archivo.
.EXAMPLE
    ./Ej1.ps1 -d directorio -a ./salida.json
.EXAMPLE
    ./Ej1.ps1 -d directorio -p
.OUTPUTS
    JSON con los promedios por canal y por dia.
    Exit codes:
        0 - Ejecución correcta
        2 - El directorio no existe
        3 - El directorio no tiene archivos
#>
param(
    #Pertenece a archivo
    [Alias("a")]
    #Es mandatory dentro de su ParameterSetName
    [Parameter(ParameterSetName = "archivo", Mandatory = $true)]
    [string]$archivo,

    #Archivo y pantalla son mutuamente excluyentes por lo que estaran en diferentes ParameterSetNames

    #Pertenece a pantalla
    [Alias("p")]
    #Es mandatory dentro de su ParameterSetName
    [Parameter(ParameterSetName = "pantalla", Mandatory = $true)]
    [switch]$pantalla,


    #Pertenece a archivo y pantalla
    [Alias("d")]
    [Parameter(ParameterSetName = "archivo")]
    [Parameter(ParameterSetName = "pantalla")]
    #Siempre es obligatorio ya que necesito el directorio para ambos casos
    [Parameter(Mandatory = $true)]
    [string]$directorio
)

# Validaciones iniciales
function validaciones {
    # Verificar que el directorio de entrada existe
    if (-not (Test-Path $directorio)) {
        Write-Error "El directorio '$directorio' no existe."
        exit 2
    }

    # Verificar que haya archivos .txt en el directorio
    $txtFiles = Get-ChildItem -Path $directorio -Filter *.txt
    if ($txtFiles.Count -eq 0) {
        Write-Error "El directorio '$directorio' no tiene archivos .txt."
        exit 3
    }

    # Si se especifico archivo de salida
    if ($archivo) {
        # Convertir a ruta absoluta si es relativa
        $archivoAbsoluto = if ([System.IO.Path]::IsPathRooted($archivo)) {
            $archivo
        } else {
            Join-Path (Get-Location) $archivo
        }

        # Obtener el directorio de salida
        $dirSalida = Split-Path -Path $archivoAbsoluto -Parent

        # Si la ruta quedó vacía (archivo en el directorio actual), usar Get-Location
        if ([string]::IsNullOrEmpty($dirSalida)) {
            $dirSalida = (Get-Location).Path
        }

        # Crear directorio si no existe
        if (-not (Test-Path $dirSalida)) {
            New-Item -Path $dirSalida -ItemType Directory -Force | Out-Null
        }

        # Guardar la ruta absoluta para usarla luego
        $script:archivoAbsoluto = $archivoAbsoluto
    }

    return 0
}


function procesarArchivos {
    param([string]$dir)
    $datos = @{}

    #Por cada archivo .txt en el directorio
    Get-ChildItem -Path "$dir\*.txt" | ForEach-Object {
        $archivoActual = $_.FullName
        #Por cada linea del archivo
        Get-Content $archivoActual | ForEach-Object {
            $campos = $_ -split "\|"  # ID|Fecha|Canal|Tiempo|Nota
            $fecha = ($campos[1].Trim() -split " ")[0]  # Solo fecha sin hora
            $canal = $campos[2].Trim()
            $tiempo = [double]$campos[3].Trim()
            $nota = [double]$campos[4].Trim()

            # Inicializar fecha
            if (-not $datos.ContainsKey($fecha)) {
                $datos[$fecha] = @{}
            }

            # Inicializar canal
            if (-not $datos[$fecha].ContainsKey($canal)) {
                $datos[$fecha][$canal] = @{
                    Cantidad = 0
                    TotalTiempo = 0
                    TotalNota = 0
                }
            }

            # Acumular
            $datos[$fecha][$canal].Cantidad += 1
            $datos[$fecha][$canal].TotalTiempo += $tiempo
            $datos[$fecha][$canal].TotalNota += $nota
        }
    }

    # Calcular promedios y limpiar campos auxiliares
   foreach ($fecha in $datos.Keys) {
    foreach ($canal in @($datos[$fecha].Keys)) {  # <- copiar las claves
        $datos[$fecha][$canal] = @{
            tiempo_respuesta_promedio = [math]::Round($datos[$fecha][$canal].TotalTiempo / $datos[$fecha][$canal].Cantidad, 2)
            nota_satisfaccion_promedio = [math]::Round($datos[$fecha][$canal].TotalNota / $datos[$fecha][$canal].Cantidad, 2)
        }
    }
}
    $datosOrdenados = [ordered]@{}

    foreach ($fecha in ($datos.Keys | Sort-Object { [datetime]::Parse($_) })) {
         $datosOrdenados[$fecha] = $datos[$fecha]
    }
    return $datosOrdenados
}

function main {
    # Ejecutar validaciones (esto prepara $archivoAbsoluto si corresponde)
    $ret = validaciones
    if ($ret -ne 0) {
        exit $ret
    }

    # Obtener ruta absoluta del directorio de entrada
    $directorioAbsoluto = (Resolve-Path $directorio).Path

    # Procesar archivos y calcular promedios
    $resultado = procesarArchivos $directorioAbsoluto

    # Convertir el resultado a JSON
    $resultadoJson = $resultado | ConvertTo-Json -Depth 3

    # Mostrar por pantalla o guardar en archivo
    if ($pantalla) {
        Write-Output $resultadoJson
    } else {
        # usamos $archivoAbsoluto ya validado y creado si era necesario
        $resultadoJson | Out-File -FilePath $archivoAbsoluto -Encoding utf8 -Force
    }

    return 0
}

# Ejecutar main
main
