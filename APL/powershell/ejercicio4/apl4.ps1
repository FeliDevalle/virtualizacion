<#
.SYNOPSIS
  apl4.ps1 - Monitoreo de repositorios Git para patrones sensibles (VERSIÓN DE DEPURACIÓN)
#>

# ... (toda la sección de ayuda se mantiene igual) ...

param(
    [Parameter(Mandatory=$true, HelpMessage="La ruta al repositorio Git es obligatoria.")]
    [string]$repo,
    [string]$configuracion,
    [string]$log = ".\audit.log",
    [switch]$kill,
    [int]$alerta = 10,
    [switch]$daemon
)

# --- (Todas las funciones Fail, Get-PidFilePath, Test-ProcessRunning se mantienen igual) ---
function Fail([string]$msg) {
    Write-Host $msg -ForegroundColor Red
    exit 1
}

function Get-PidFilePath([string]$repoPath) {
    $safe = ($repoPath -replace '[\\/: ]','_') -replace '[^\w\-_\.]','_'
    return Join-Path $env:TEMP "audit_$safe.pid"
}

function Test-ProcessRunning([int]$pid1) {
    return $(try { Get-Process -Id $pid1 -ErrorAction Stop } catch { $false }) -ne $false
}


# --- MODO LANZADOR ---
if (-not $daemon) {
    if (-not $repo) { Fail "Error: El parámetro -repo es obligatorio." }
    $pidFile = Get-PidFilePath $repo
    if ($kill) {
        if (Test-Path $pidFile) {
            try {
                $pidToKill = [int](Get-Content $pidFile -ErrorAction Stop)
                if (Test-ProcessRunning $pidToKill) {
                    Stop-Process -Id $pidToKill -Force -ErrorAction SilentlyContinue
                    Write-Host "Demonio detenido (PID $pidToKill)."
                } else {
                    Write-Host "El proceso del demonio (PID $pidToKill) ya no existía. Limpiando archivo PID."
                }
            } catch { Write-Host "El archivo PID estaba corrupto o no se pudo leer." }
            finally { Remove-Item $pidFile -ErrorAction SilentlyContinue }
        } else { Write-Host "No se encontró un demonio en ejecución para este repositorio." }
        exit 0
    }
    if (-not $configuracion) { Fail "Error: El parámetro -configuracion es obligatorio para iniciar el demonio." }
    if (Test-Path $pidFile) {
        try {
            $existingPid = [int](Get-Content $pidFile -ErrorAction Stop)
            if (Test-ProcessRunning $existingPid) {
                Fail "Error: Ya existe un demonio en ejecución para este repositorio (PID: $existingPid)."
            } else { Remove-Item $pidFile -ErrorAction SilentlyContinue }
        } catch { Remove-Item $pidFile -ErrorAction SilentlyContinue }
    }
    $scriptFullPath = $MyInvocation.MyCommand.Definition
    $argList = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", "`"$scriptFullPath`"",
        "-repo", "`"$repo`"",
        "-configuracion", "`"$configuracion`"",
        "-log", "`"$((Resolve-Path $log).ProviderPath)`"",
        "-alerta", $alerta, "-daemon"
    )
    Start-Process -FilePath powershell.exe -ArgumentList $argList -WindowStyle Hidden -PassThru | Out-Null
    Start-Sleep -Seconds 1
    $wait = 0
    while (($wait -lt 5) -and (-not (Test-Path $pidFile))) {
        Start-Sleep -Milliseconds 200
        $wait += 1
    }
    if (Test-Path $pidFile) {
        $daemonPid = Get-Content $pidFile -ErrorAction SilentlyContinue
        Write-Host "Demonio iniciado en segundo plano (PID $daemonPid). Monitoreando '$repo' cada $alerta segundos."
        exit 0
    } else { Fail "Fallo al iniciar el demonio. Verifique los permisos y las rutas." }
}

# -------------------
# --- MODO DEMONIO ---
# -------------------

# <-- CAMBIO: Ruta fija para un log de errores fatales del demonio.
$fatalErrorLog = Join-Path $env:TEMP "audit_daemon_fatal_error.log"

# <-- CAMBIO: Escribimos al log de errores fatales para saber que el demonio al menos se inició.
"$(Get-Date) - Demonio iniciado. PID: $PID. Intentando resolver rutas..." | Out-File -FilePath $fatalErrorLog -Append

try {
    # Verificamos los parámetros recibidos
    if (-not $repo) { throw "El parámetro -repo no fue recibido por el demonio." }
    if (-not $configuracion) { throw "El parámetro -configuracion no fue recibido por el demonio." }

    "$(Get-Date) - Parámetros recibidos: repo=[$repo], configuracion=[$configuracion], log=[$log]" | Out-File -FilePath $fatalErrorLog -Append

    $repoFull = (Resolve-Path $repo).ProviderPath
    "$(Get-Date) - Ruta -repo resuelta a: $repoFull" | Out-File -FilePath $fatalErrorLog -Append
    
    $configFull = (Resolve-Path $configuracion).ProviderPath
    "$(Get-Date) - Ruta -configuracion resuelta a: $configFull" | Out-File -FilePath $fatalErrorLog -Append

    $logFull = (Resolve-Path $log).ProviderPath
    "$(Get-Date) - Ruta -log resuelta a: $logFull" | Out-File -FilePath $fatalErrorLog -Append

} catch {
    # <-- CAMBIO CRÍTICO: Si algo falla arriba, lo registramos y salimos.
    $errorMessage = "$(Get-Date) - ERROR FATAL AL INICIAR DEMONIO: $($_.Exception.Message)"
    $errorMessage | Out-File -FilePath $fatalErrorLog -Append
    exit 1
}


# <-- NUEVO: Chequeo de sanidad extra. Si alguna ruta es nula o vacía, el demonio termina.
if ([string]::IsNullOrWhiteSpace($repoFull) -or [string]::IsNullOrWhiteSpace($configFull) -or [string]::IsNullOrWhiteSpace($logFull)) {
    exit 1
}

if (-not (Test-Path (Join-Path $repoFull ".git"))) { exit 1 }

$pidFile = Get-PidFilePath $repoFull

if (Test-Path $pidFile) {
    try {
        $otherPid = [int](Get-Content $pidFile -ErrorAction Stop)
        if (Test-ProcessRunning $otherPid) { exit 1 }
    } catch { }
}
$PID | Out-File -FilePath $pidFile -Encoding ascii -Force

Set-Location $repoFull

$branch = (git symbolic-ref refs/remotes/origin/HEAD -q) -replace 'refs/remotes/origin/', ''
if ([string]::IsNullOrWhiteSpace($branch)) { $branch = 'main' }

try {
    git fetch origin $branch 2>$null | Out-Null
    $lastCommit = (git rev-parse "origin/$branch" 2>$null).Trim()
} catch { $lastCommit = "" }

if ([string]::IsNullOrWhiteSpace($lastCommit)) {
    Remove-Item $pidFile -ErrorAction SilentlyContinue
    exit 1
}

function Write-Alert([string]$pattern, [string]$file, [string]$logPath) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] Alerta: patrón '$pattern' encontrado en el archivo '$file'."
    $line | Out-File -FilePath $logPath -Append -Encoding utf8
}

try {
    while ($true) {
        git fetch origin $branch 2>$null | Out-Null
        $newCommit = (git rev-parse "origin/$branch" 2>$null).Trim()

        if (-not [string]::IsNullOrWhiteSpace($newCommit) -and $newCommit -ne $lastCommit) {
            try {
                $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                ("[$ts] Nuevo commit detectado: {0}" -f $newCommit) | Out-File -FilePath $logFull -Append -Encoding utf8
                
                # <-- ¡AQUÍ ESTÁ LA CLAVE DE LA DEPURACIÓN!
                # Escribimos el valor de las variables en el log ANTES de usarlas.
                $debugMsg = "[$ts] DEBUG: Verificando variables. logFull=[$logFull], configFull=[$configFull]"
                $debugMsg | Out-File -FilePath $logFull -Append -Encoding utf8

                $patterns = @()
                # Esta es la línea que probablemente está fallando.
                $patternLines = Get-Content $configFull -ErrorAction SilentlyContinue
                if ($null -ne $patternLines) {
                    foreach ($line in $patternLines) {
                        $lineTrim = $line.Trim()
                        if ([string]::IsNullOrWhiteSpace($lineTrim) -or $lineTrim.StartsWith('#')) { continue }
                        if ($lineTrim.StartsWith("regex:")) {
                            $patterns += [pscustomobject]@{ Type = 'Regex'; Value = $lineTrim.Substring(6) }
                        } else {
                            $patterns += [pscustomobject]@{ Type = 'Literal'; Value = $lineTrim }
                        }
                    }
                }

                $files = git diff --name-only $lastCommit $newCommit 2>$null
                
                foreach ($file in $files) {
                    $spec = "{0}:{1}" -f $newCommit, $file
                    $content = git show $spec 2>$null
                    
                    if ($null -ne $content) {
                        foreach ($patternObj in $patterns) {
                            if ($patternObj.Type -eq 'Regex') {
                                try {
                                    if ($content -match $patternObj.Value) { Write-Alert $patternObj.Value $file $logFull }
                                } catch {
                                    "[$ts] ERROR: patrón regex inválido '$($patternObj.Value)'" | Out-File -FilePath $logFull -Append -Encoding utf8
                                }
                            } else { # Literal
                                if ($content -match [regex]::Escape($patternObj.Value)) {
                                    Write-Alert $patternObj.Value $file $logFull
                                }
                            }
                        }
                    }
                }
                $lastCommit = $newCommit
            } catch {
                $errTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                ("[$errTs] ERROR procesando commit {0}: {1}" -f $newCommit, $_.Exception.ToString()) | Out-File -FilePath $logFull -Append -Encoding utf8
            }
        }
        
        Start-Sleep -Seconds $alerta

        if (-not (Test-Path $pidFile)) { exit 0 }
    }
} finally {
    Remove-Item $pidFile -ErrorAction SilentlyContinue
}