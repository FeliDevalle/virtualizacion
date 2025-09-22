param(
    [Parameter(Mandatory=$true)]
    [string[]]$nombre,

    [Parameter(Mandatory=$true)]
    [int]$ttl
)

# Archivo de caché
$cacheFile = "C:\APL\5\POWERSHELL\cache_paises.json"

# Cargar cache existente y convertir a Hashtable
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


# Función para guardar el caché
function Guardar-Cache {
    param($cache)
    try {
        $cache | ConvertTo-Json -Depth 5 | Set-Content -Path $cacheFile -Encoding UTF8
    } catch {
        Write-Warning "No se pudo guardar la cache en ${cacheFile}: ${_}"
    }
}

# Función para consultar país
function Consultar-Pais {
    param($nombre, $ttl)

    $paisKey = $nombre.ToLower()

    if ($cache.ContainsKey($paisKey)) {
        $entrada = $cache[$paisKey]
        $timestamp = [datetime]::Parse($entrada.timestamp)

        if ((Get-Date) - $timestamp -lt (New-TimeSpan -Seconds $ttl)) {
            # Usar datos del caché
            $data = $entrada.data
            Mostrar-Pais $data
            return
        }
    }

    # Consultar API si no está en caché o TTL vencido
    try {
        $url = "https://restcountries.com/v3.1/name/$nombre"
        $response = Invoke-RestMethod -Uri $url -ErrorAction Stop
        $data = $response[0]

        # Guardar en caché
        $cache[$paisKey] = @{
            timestamp = (Get-Date).ToString("o")
            data      = $data
        }

        Guardar-Cache $cache
        Mostrar-Pais $data
    } catch {
        Write-Warning "Error al consultar API para $nombre ${_}"
    }
}

# Función para mostrar datos del país
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

# Ejecutar para cada país
foreach ($p in $nombre) {
    Consultar-Pais -nombre $p -ttl $ttl
}
