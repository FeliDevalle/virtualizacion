<#
.SYNOPSIS
  apl4.ps1 - Monitoreo de repositorios Git para patrones sensibles

.DESCRIPTION
  Demonio que monitoriza cambios en la rama principal y registra alertas cuando encuentra patrones sensibles.
  Uso:
    Iniciar:  .\apl4.ps1 -repo "C:\miRepo" -configuracion ".\patrones.conf" -alerta 10 -log ".\audit.log"
    Detener:  .\apl4.ps1 -repo "C:\miRepo" -kill

.PARAMETER repo
  Ruta del repositorio Git a monitorear (acepta rutas relativas, absolutas y con espacios).

.PARAMETER configuracion
  Ruta del archivo de configuración con patrones. Soporta comentarios con '#' y prefijos 'regex:'.

.PARAMETER log
  Ruta del archivo donde se registran las alertas (por defecto .\audit.log).

.PARAMETER alerta
  Intervalo en segundos entre comprobaciones (por defecto 10).

.PARAMETER kill
  Flag para detener el demonio asociado al repo especificado.

.EXAMPLE
  Get-Help .\apl4.ps1 -Full
#>

#Integrantes:
#    CORONEL, THIAGO MARTÍN
#    DEVALLE, FELIPE PEDRO
#    MURILLO, JOEL ADAN
#    RUIZ, RAFAEL DAVID NAZARENO

param(
    [Parameter(Mandatory=$true)]
    [string]$repo,

    [Parameter(Mandatory=$true)]
    [string]$configuracion,

    [string]$log = ".\audit.log",

    [switch]$kill,

    [int]$alerta = 10,

    [switch]$daemon
)

function Fail([string]$msg) {
    Write-Host $msg -ForegroundColor Red
    exit 1
}

function Get-PidFilePath([string]$repoPath) {
    $safe = ($repoPath -replace '[\\/: ]','_') -replace '[^\w\-_\.]','_'
    return Join-Path $env:TEMP "audit_$safe.pid"
}

function Test-ProcessRunning([int]$pid1) {
    try {
        Get-Process -Id $pid1 -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

# Validaciones básicas (si viene en modo demonio, las validaciones se repiten dentro del demonio)
if (-not $daemon) {
    if (-not $repo) { Fail "Error: parámetro -repo es obligatorio." }
    if (-not $configuracion) { Fail "Error: parámetro -configuracion es obligatorio." }

    $pidFile = Get-PidFilePath $repo

    if ($kill) {
        if (Test-Path $pidFile) {
            try {
                $pidToKill = [int](Get-Content $pidFile -ErrorAction Stop)
            } catch {
                Remove-Item $pidFile -ErrorAction SilentlyContinue
                Write-Host "Archivo PID corrupto, removido." 
                exit 0
            }
            if (Test-ProcessRunning $pidToKill) {
                Stop-Process -Id $pidToKill -Force -ErrorAction SilentlyContinue
                Remove-Item $pidFile -ErrorAction SilentlyContinue
                Write-Host "Demonio detenido (PID $pidToKill)."
            } else {
                Remove-Item $pidFile -ErrorAction SilentlyContinue
                Write-Host "Proceso no existía. Archivo PID limpiado."
            }
        } else {
            Write-Host "No se encontró un demonio en ejecución para este repositorio."
        }
        exit 0
    }

    # Si ya existe PID y proceso vivo, evitar iniciar otro
    if (Test-Path $pidFile) {
        try {
            $existingPid = [int](Get-Content $pidFile -ErrorAction Stop)
            if (Test-ProcessRunning $existingPid) {
                Fail "Error: Ya existe un demonio en ejecución para este repositorio (PID: $existingPid)."
            } else {
                # limpiar PID huérfano
                Remove-Item $pidFile -ErrorAction SilentlyContinue
            }
        } catch {
            Remove-Item $pidFile -ErrorAction SilentlyContinue
        }
    }

    # Lanzar la misma script en modo demonio (nuevo proceso PowerShell)
    $scriptFullPath = $MyInvocation.MyCommand.Definition
    $argList = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$scriptFullPath`"",
        "-repo", "`"$repo`"",
        "-configuracion", "`"$configuracion`"",
        "-log", "`"$((Resolve-Path $log).ProviderPath)`"",
        "-alerta", $alerta,
        "-daemon"
    )
    # Start-Process para que corra en background y no dependa de la terminal actual
    Start-Process -FilePath (Get-Command powershell).Source -ArgumentList $argList -WindowStyle Hidden -PassThru | Out-Null
    Start-Sleep -Seconds 1

    # Esperar hasta que el demonio haya escrito su PID (timeout corto)
    $pidFile = Get-PidFilePath $repo
    $wait = 0
    while (($wait -lt 5) -and (-not (Test-Path $pidFile))) {
        Start-Sleep -Milliseconds 200
        $wait += 1
    }

    if (Test-Path $pidFile) {
        $daemonPid = Get-Content $pidFile -ErrorAction SilentlyContinue
        Write-Host "Demonio iniciado en segundo plano (PID $daemonPid). Monitoreando '$repo' cada $alerta segundos."
        exit 0
    } else {
        Fail "Fallo al iniciar demonio. Verifique permisos y rutas."
    }
}

# -------------------
# MODO DEMONIO: ejecución del bucle de monitoreo
# -------------------
# Validaciones dentro del demonio (según el directorio del repo)
if (-not $repo) { Fail "Error (daemon): parametro -repo es obligatorio." }
if (-not $configuracion) { Fail "Error (daemon): parametro -configuracion es obligatorio." }

# Rutas absolutas
try {
    $repoFull = (Resolve-Path $repo).ProviderPath
} catch {
    Fail "Error: repositorio '$repo' no encontrado."
}
if (-not (Test-Path (Join-Path $repoFull ".git"))) {
    Fail "Error: '$repoFull' no parece ser un repositorio Git válido (.git ausente)."
}
try {
    $configFull = (Resolve-Path $configuracion).ProviderPath
} catch {
    Fail "Error: archivo de configuración '$configuracion' no encontrado."
}
$logFull = if ($log) { (Resolve-Path $log).ProviderPath } else { Join-Path $repoFull "audit.log" }

$pidFile = Get-PidFilePath $repoFull

# Si ya hay PID de otro proceso (posible carrera), abortar
if (Test-Path $pidFile) {
    try {
        $otherPid = [int](Get-Content $pidFile -ErrorAction Stop)
        if (Test-ProcessRunning $otherPid) {
            Fail "Error (daemon): ya existe un demonio corriendo para este repo (PID $otherPid)."
        } else {
            Remove-Item $pidFile -ErrorAction SilentlyContinue
        }
    } catch {
        Remove-Item $pidFile -ErrorAction SilentlyContinue
    }
}

# Escribimos nuestro PID
$PID | Out-File -FilePath $pidFile -Encoding ascii -Force

# Cambiar al directorio del repositorio
Set-Location $repoFull

# Detectar rama principal (HEAD branch)
$branch = ""
try {
    $remoteShow = git remote show origin 2>$null
    if ($remoteShow) {
        $m = ($remoteShow | Select-String 'HEAD branch' -SimpleMatch).Line
        if ($m) {
            $parts = $m -split '\s+'
            $branch = $parts[-1]
        }
    }
} catch { $branch = "" }

if ([string]::IsNullOrWhiteSpace($branch)) {
    # intento alternativo: comprobar si 'main' o 'master' existen en remoto
    try {
        git ls-remote --heads origin main 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $branch = "main" }
        else { $branch = "master" }
    } catch { $branch = "main" }
}

# Obtener último commit inicial
try {
    git fetch origin $branch 2>$null | Out-Null
    $lastCommit = git rev-parse "origin/$branch" 2>$null
    $lastCommit = $lastCommit.Trim()
} catch {
    $lastCommit = ""
}
if ([string]::IsNullOrWhiteSpace($lastCommit)) {
    $msg = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR: No se pudo resolver commit inicial para origin/$branch."
    $msg | Out-File -FilePath $logFull -Append -Encoding utf8
    Remove-Item $pidFile -ErrorAction SilentlyContinue
    Fail $msg
}

# Función para anotar log
function Write-Alert([string]$pattern, [string]$file) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] Alerta: patrón '$pattern' encontrado en el archivo '$file'."
    $line | Out-File -FilePath $logFull -Append -Encoding utf8
}

# Bucle principal
try {
    while ($true) {
        # Intentar detectar cambios en remoto
        git fetch origin $branch 2>$null | Out-Null
        $newCommit = git rev-parse "origin/$branch" 2>$null
        $newCommit = $newCommit.Trim()
        if (-not [string]::IsNullOrWhiteSpace($newCommit) -and $newCommit -ne $lastCommit) {
            $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            ("[$ts] Nuevo commit detectado: {0}" -f $newCommit) | Out-File -FilePath $logFull -Append -Encoding utf8

            # Obtener lista de archivos modificados entre commits
            $files = git diff --name-only $lastCommit $newCommit 2>$null
            if ($files) {
                $files = $files -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
                foreach ($file in $files) {
                    # Evitar archivos binarios grandes: si git show falla, ignorar
                    try {
                            # Construir especificador commit:file evitando ambigüedad de variables
                            $spec = "$($newCommit):$file"

                            # Ejecutar git show y unir líneas en un único string
                            $content = (git show $spec 2>$null) -join "`n"

                            # Si git falló o no devolvió contenido, saltar
                            if (-not $content) { continue }
                    } catch {
                        continue
                    }

                    # Leer patrones
                    $patternLines = Get-Content $configFull -ErrorAction SilentlyContinue
                    foreach ($line in $patternLines) {
                        $lineTrim = $line.Trim()
                        if ([string]::IsNullOrWhiteSpace($lineTrim) -or $lineTrim.StartsWith('#')) { continue }

                        if ($lineTrim.StartsWith("regex:")) {
                            $pattern = $lineTrim.Substring(6)
                            try {
                                if ([regex]::IsMatch($content, $pattern)) {
                                    Write-Alert $pattern $file
                                }
                            } catch {
                                # patrón regex inválido: escribir una entrada de error en log (no detener demonio)
                                $err = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR: patrón regex inválido '$pattern' en $configFull."
                                $err | Out-File -FilePath $logFull -Append -Encoding utf8
                                continue
                            }
                        } else {
                            $pattern = $lineTrim
                            if ($content.IndexOf($pattern, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                                Write-Alert $pattern $file
                            }
                        }
                    }
                }
            }

            # Actualizar último commit revisado
            $lastCommit = $newCommit
        }

        Start-Sleep -Seconds $alerta

        # Comprobar archivo PID: si fue eliminado externamente (stop), salir limpiamente
        if (-not (Test-Path $pidFile)) {
            # salir
            exit 0
        }
    }
} finally {
    # Limpieza: eliminar PID si existe
    Remove-Item $pidFile -ErrorAction SilentlyContinue
}
