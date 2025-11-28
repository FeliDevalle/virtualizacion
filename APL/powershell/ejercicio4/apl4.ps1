<#
.SYNOPSIS
  apl4.ps1 - Monitoreo de repositorios Git para patrones sensibles
#>

# ... (Toda la cabecera de documentación e integrantes se mantiene igual) ...

param(
    [Parameter(Mandatory=$true, ParameterSetName='Run')]
    [Parameter(Mandatory=$true, ParameterSetName='Kill')]
    [string]$repo,

    [Parameter(Mandatory=$true, ParameterSetName='Run')]
    [string]$configuracion,

    [Parameter(Mandatory=$true, ParameterSetName='Run')]
    [string]$log,

    [Parameter(Mandatory=$false, ParameterSetName='Run')]
    [int]$alerta = 10,

    [Parameter(Mandatory=$true, ParameterSetName='Kill')]
    [switch]$kill,

    [switch]$daemon
)

function Fail([string]$msg, [string]$details = $null) {
    Write-Host $msg -ForegroundColor Red
    if ($details) {
        Write-Host $details -ForegroundColor Yellow
    }
    exit 1
}

# Función auxiliar para obtener ruta absoluta
function Get-AbsolutePath([string]$path) {
    if ($path.StartsWith("~")) {
        $homeDir = [System.Environment]::GetFolderPath('UserProfile')
        $path = $path.Replace("~", $homeDir)
    }
    # Si la ruta no existe, usamos el directorio actual como base para resolver
    if (-not (Test-Path $path)) {
        $full = [System.IO.Path]::GetFullPath($path)
        return $full
    }
    return (Resolve-Path $path).Path
}

function Get-TempDir {
    $tempPath = ''
    try {
        $userTemp = [System.IO.Path]::GetTempPath()
        if (-not [string]::IsNullOrWhiteSpace($userTemp)) {
            $tempPath = $userTemp
        }
    } catch {}

    if ([string]::IsNullOrWhiteSpace($tempPath)) {
        if ($IsWindows) { $tempPath = Join-Path $env:windir "Temp" } else { $tempPath = "/tmp" }
    }
    return $tempPath.TrimEnd('\','/')
}

function Make-SafeName([string]$path) {
    if (-not $path) { return 'unknown_repo' }
    $safe = ($path -replace '[\\/: ]','_') -replace '[^\w\-_\.]','_'
    return $safe
}

function Get-PidFilePath([string]$repoPath) {
    $safe = Make-SafeName $repoPath
    $tmpDir = Get-TempDir
    return Join-Path $tmpDir "audit_$safe.pid"
}

function Get-ErrorFilePath([string]$repoPath) {
    $safe = Make-SafeName $repoPath
    $tmpDir = Get-TempDir
    return Join-Path $tmpDir "audit_error_$safe.tmp"
}

function Test-ProcessRunning([int]$pid1) {
    return $(try { Get-Process -Id $pid1 -ErrorAction Stop } catch { $false }) -ne $false
}

# -----------------------
# --- MODO LANZADOR ---
# -----------------------
if (-not $daemon) {
    if (-not $repo) { Fail "Error: El parámetro -repo es obligatorio." }

    # Resolvemos repo
    try {
        $repoResolved = (Resolve-Path $repo -ErrorAction Stop).ProviderPath
    } catch {
        Fail "El repositorio '$repo' no existe o no es accesible."
    }

    $pidFile = Get-PidFilePath $repoResolved
    $errorFile = Get-ErrorFilePath $repoResolved

    # --- Lógica KILL ---
    if ($kill) {
        if (Test-Path $pidFile) {
            try {
                $pidToKill = [int](Get-Content $pidFile -ErrorAction Stop)
                if (Test-ProcessRunning $pidToKill) {
                    Stop-Process -Id $pidToKill -Force -ErrorAction SilentlyContinue
                    Write-Host "Demonio detenido (PID $pidToKill)."
                } else { Write-Host "El proceso del demonio ya no existía." }
            } catch { Write-Host "Error leyendo PID file." }
            finally { Remove-Item $pidFile -ErrorAction SilentlyContinue }
        } else { Write-Host "No se encontró un demonio en ejecución." }
        exit 0
    }

    # --- Lógica START ---
    if (-not $configuracion) { Fail "Error: -configuracion es obligatorio." }

    if (Test-Path $pidFile) {
        try {
            $existingPid = [int](Get-Content $pidFile -ErrorAction Stop)
            if (Test-ProcessRunning $existingPid) {
                Fail "Error: Ya existe un demonio (PID: $existingPid)."
            } else { Remove-Item $pidFile -ErrorAction SilentlyContinue }
        } catch { Remove-Item $pidFile -ErrorAction SilentlyContinue }
    }
    
    Remove-Item $errorFile -ErrorAction SilentlyContinue

    $scriptFullPath = $MyInvocation.MyCommand.Definition
    $repoAbs = $repoResolved
    $configAbs = (Resolve-Path $configuracion).Path
    $logAbs = Get-AbsolutePath $log # Usamos la función corregida

    $argList = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", "`"$scriptFullPath`"",
        "-repo", "`"$repoAbs`"",
        "-configuracion", "`"$configAbs`"",
        "-log", "`"$logAbs`"",
        "-alerta", $alerta, "-daemon"
    )

    $psBinary = "powershell"
    if ($IsLinux) { $psBinary = "pwsh" }

    $startParams = @{
        FilePath = $psBinary
        ArgumentList = $argList
        PassThru = $true
    }
    if (-not $IsLinux) { $startParams["WindowStyle"] = "Hidden" }

    $process = Start-Process @startParams
    Start-Sleep -Seconds 2 # Damos un segundo extra

    if (Test-Path $pidFile) {
        $daemonPid = Get-Content $pidFile -ErrorAction SilentlyContinue
        Write-Host "Demonio iniciado en segundo plano (PID $daemonPid)."
        Write-Host "Monitoreando: $repoAbs"
        Write-Host "Log: $logAbs"
        exit 0
    } else {
        $errorDetails = ""
        if (Test-Path $errorFile) {
            $errorDetails = Get-Content $errorFile
            Remove-Item $errorFile -ErrorAction SilentlyContinue
        }
        Fail "Fallo al iniciar el demonio." $errorDetails
    }
}

# -----------------------
# --- MODO DEMONIO ---
# -----------------------
try {
    if (-not $repo) { throw "Falta -repo" }
    
    $repoFull = $repo
    $configFull = $configuracion
    $logFull = $log

    # Asegurar directorio del log
    $logDir = Split-Path -Parent $logFull
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    ### CORRECCIÓN 1: Crear el archivo de log INMEDIATAMENTE al iniciar ###
    $initDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$initDate] Demonio iniciado. Monitoreando: $repoFull" | Out-File -FilePath $logFull -Encoding utf8 -Force
    #######################################################################

    if (-not (Test-Path (Join-Path $repoFull ".git"))) { throw "No es un repo git válido." }

    $pidFile = Get-PidFilePath $repoFull
    $PID | Out-File -FilePath $pidFile -Encoding ascii -Force

} catch {
    $errorFileForDaemon = Get-ErrorFilePath $repo
    $_.Exception.Message | Out-File -FilePath $errorFileForDaemon -Encoding utf8
    exit 1
}

Set-Location $repoFull

### CORRECCIÓN 2: Monitorear HEAD local en lugar de origin remoto ###
# Esto permite que detecte cambios al hacer commit localmente sin necesidad de push
try {
    $lastCommit = (git rev-parse HEAD 2>$null).Trim()
} catch { 
    $lastCommit = "0000000000000000000000000000000000000000" # Dummy si es un repo vacío
}

function Write-Alert([string]$pattern, [string]$file, [string]$logPath) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] Alerta: patrón '$pattern' encontrado en el archivo '$file'."
    $line | Out-File -FilePath $logPath -Append -Encoding utf8
}

try {
    # LOG DE DEBUG: Confirmar que entramos al bucle
    "DEBUG: Iniciando bucle de monitoreo sobre $branch" | Out-File -FilePath $logFull -Append -Encoding utf8

    while ($true) {
        try {
            # 1. Intentamos leer el commit actual
            $gitOutput = git rev-parse HEAD 2>&1
            if ($LASTEXITCODE -ne 0) {
                "ERROR CRÍTICO GIT: $gitOutput" | Out-File -FilePath $logFull -Append -Encoding utf8
                throw "Git falló al leer HEAD"
            }
            $newCommit = "$gitOutput".Trim()

            # LOG DE DEBUG: Escribir qué commits estamos comparando (Solo para ver si está vivo)
            # Descomenta la siguiente linea si quieres ver que el script respira cada 10 segs:
            # "DEBUG Check: Nuevo=$newCommit | Viejo=$lastCommit" | Out-File -FilePath $logFull -Append

            if (-not [string]::IsNullOrWhiteSpace($newCommit) -and $newCommit -ne $lastCommit) {
                
                $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                ("[$ts] CAMBIO DETECTADO. Procesando commit: $newCommit") | Out-File -FilePath $logFull -Append -Encoding utf8
                
                # 2. Manejo del caso "Primer arranque" o repo vacío
                if ($lastCommit -eq "0000000000000000000000000000000000000000") {
                    "DEBUG: Es la primera ejecución, saltamos diff y actualizamos referencia." | Out-File -FilePath $logFull -Append
                    $lastCommit = $newCommit
                    continue 
                }

                # 3. Cargar Patrones
                $patterns = @()
                if (Test-Path $configFull) {
                    $patternLines = Get-Content $configFull
                    foreach ($line in $patternLines) {
                        $lineTrim = $line.Trim()
                        if ([string]::IsNullOrWhiteSpace($lineTrim) -or $lineTrim.StartsWith('#')) { continue }
                        if ($lineTrim.StartsWith("regex:")) {
                            $patterns += [pscustomobject]@{ Type = 'Regex'; Value = $lineTrim.Substring(6) }
                        } else {
                            $patterns += [pscustomobject]@{ Type = 'Literal'; Value = $lineTrim }
                        }
                    }
                    "DEBUG: Patrones cargados: $($patterns.Count)" | Out-File -FilePath $logFull -Append
                } else {
                    "ERROR: No encuentro archivo conf: $configFull" | Out-File -FilePath $logFull -Append
                }

                # 4. Git Diff
                # Quitamos el 2>$null para ver si explota aquí
                $files = git diff --name-only $lastCommit $newCommit 
                "DEBUG: Archivos modificados: $files" | Out-File -FilePath $logFull -Append
                
                foreach ($file in $files) {
                    if ([string]::IsNullOrWhiteSpace($file)) { continue }

                    # 5. Git Show
                    $spec = "${newCommit}:${file}"
                    # Importante: forzar encoding string para que powershell no se lie con bytes
                    $content = git show $spec 2>&1 | Out-String
                    
                    if ($LASTEXITCODE -ne 0) {
                         "ERROR leyendo archivo $file : $content" | Out-File -FilePath $logFull -Append
                         continue
                    }

                    foreach ($patternObj in $patterns) {
                        $found = $false
                        if ($patternObj.Type -eq 'Regex') {
                            if ($content -match $patternObj.Value) { $found = $true }
                        } else {
                            if ($content -match [regex]::Escape($patternObj.Value)) { $found = $true }
                        }

                        if ($found) {
                             Write-Alert $patternObj.Value $file $logFull
                             "DEBUG: ¡Alerta generada para $file!" | Out-File -FilePath $logFull -Append
                        }
                    }
                }
                # Actualizamos el puntero AL FINAL
                $lastCommit = $newCommit
            }
        } catch {
             $errTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
             # AQUÍ ESTÁ LA CLAVE: Si falla, escribimos la excepción real en el log
             ("[$errTs] EXCEPTION en bucle: " + $_.Exception.ToString()) | Out-File -FilePath $logFull -Append -Encoding utf8
        }
        
        Start-Sleep -Seconds $alerta
        if (-not (Test-Path $pidFile)) { 
            "DEBUG: PID file borrado, saliendo." | Out-File -FilePath $logFull -Append
            exit 0 
        }
    }
} finally {
    Remove-Item $pidFile -ErrorAction SilentlyContinue
}