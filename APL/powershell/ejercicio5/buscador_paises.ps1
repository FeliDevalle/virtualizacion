<#
.SYNOPSIS
    Consulta la API REST Countries y muestra informacion de paises.

.DESCRIPTION
    Grupo 1
    Integrantes:
    CORONEL, THIAGO MARTÍN
    DEVALLE, FELIPE PEDRO
    MURILLO, JOEL ADAN
    RUIZ, RAFAEL DAVID NAZARENO

    Consulta la API de REST Countries para obtener datos de paises.
    Los resultados se guardan en un archivo de cache en formato JSON.
    Cada entrada del cache tiene un TTL (time to live). Pasado ese tiempo,
    se vuelve a consultar la API para actualizar los datos.

.PARAMETER Nombre
    Nombre del pais o paises a consultar. Puede recibir un array de strings.

.PARAMETER TTL
    Tiempo de validez del cache en segundos. Pasado este tiempo se consulta
    nuevamente la API para actualizar los valores.

.EXAMPLE
    .\buscador_paises.ps1 -Nombre spain -TTL 3600
    Busca informacion de España y la guarda en cache por 1 hora.

.EXAMPLE
    .\buscador_paises.ps1 -Nombre spain argentina brazil -TTL 120
    Busca multiples paises en una sola ejecucion.
#>

param(
    [Parameter(Mandatory=$true)]
    [string[]]$Nombre,

    [Parameter(Mandatory=$true)]
    [int]$TTL
)

# === Archivo de caché seguro ===
$cacheDir = Join-Path -Path $env:TEMP -ChildPath "PS_Cache_Paises"
if (-not (Test-Path $cacheDir)) { New-Item -Path $cacheDir -ItemType Directory | Out-Null }
$cacheFile = Join-Path -Path $cacheDir -ChildPath "cache_paises.json"

# === Cargar cache existente ===
if (Test-Path $cacheFile) {
    try {
        $obj = Get-Content $cacheFile -Raw | ConvertFrom-Json
        $cache = @{}
        foreach ($k in $obj.PSObject.Properties.Name) {
            $cache[$k] = $obj.$k
        }
    } catch {
        Write-Warning "Error al leer el caché. Se reiniciará."
        $cache = @{}
    }
} else {
    $cache = @{}
}

# === Función para guardar cache ===
function Guardar-Cache {
    param($cache)
    try {
        $cache | ConvertTo-Json -Depth 5 | Set-Content -Path $cacheFile -Encoding UTF8
    } catch {
        Write-Warning "No se pudo guardar la cache en $cacheFile ${_}"
    }
}

# === Función para mostrar país ===
function Mostrar-Pais {
    param($data)
    $pais      = $data.name.common
    $capital   = $data.capital -join ", "
    $region    = $data.region
    $poblacion = $data.population
    $monedas   = $data.currencies.PSObject.Properties | ForEach-Object { "$($_.Value.name) ($($_.Name))" }

    Write-Output "País: $pais"
    Write-Output "Capital: $capital"
    Write-Output "Región: $region"
    Write-Output "Población: $poblacion"
    Write-Output "Moneda: $monedas"
    Write-Output ""
}

# === Función para consultar API y usar cache ===
function Consultar-Pais {
    param($paisNombre, $TTL)

    $paisKey = $paisNombre.ToLower()

    if ($cache.ContainsKey($paisKey)) {
        $entrada = $cache[$paisKey]
        $timestamp = [datetime]::Parse($entrada.timestamp)
        if ((Get-Date) - $timestamp -lt (New-TimeSpan -Seconds $TTL)) {
            Mostrar-Pais $entrada.data
            return
        }
    }

    try {
        $url = "https://restcountries.com/v3.1/name/$paisNombre"
        $response = Invoke-RestMethod -Uri $url -ErrorAction Stop
        $data = $response[0]

        $cache[$paisKey] = @{
            timestamp = (Get-Date).ToString("o")
            data      = $data
        }

        Guardar-Cache $cache
        Mostrar-Pais $data
    } catch {
        Write-Warning "Error al consultar API para $paisNombre ${_}"
    }
}

# === Ejecutar para cada país ===
foreach ($p in $Nombre) {
    Consultar-Pais -paisNombre $p -TTL $TTL
}
