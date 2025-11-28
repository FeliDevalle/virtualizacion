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
    while ($true) {
        try {
            # Ya no hacemos git fetch origin, miramos el estado local
            $newCommit = (git rev-parse HEAD 2>$null).Trim()

            if (-not [string]::IsNullOrWhiteSpace($newCommit) -and $newCommit -ne $lastCommit) {
                
                $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                ("[$ts] Nuevo commit detectado: {0}" -f $newCommit) | Out-File -FilePath $logFull -Append -Encoding utf8
                
                # Carga de patrones (se mueve adentro para permitir cambios en caliente del archivo conf)
                $patterns = @()
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

                # Diff contra el commit anterior
                $files = git diff --name-only $lastCommit $newCommit 2>$null
                
                foreach ($file in $files) {
                    # Obtenemos el contenido del archivo en ESE commit
                    $spec = "{0}:{1}" -f $newCommit, $file
                    $content = git show $spec 2>$null
                    
                    if ($null -ne $content) {
                        foreach ($patternObj in $patterns) {
                            if ($patternObj.Type -eq 'Regex') {
                                try {
                                    if ($content -match $patternObj.Value) { Write-Alert $patternObj.Value $file $logFull }
                                } catch {
                                    "Error en regex" | Out-File -FilePath $logFull -Append
                                }
                            } else {
                                if ($content -match [regex]::Escape($patternObj.Value)) {
                                    Write-Alert $patternObj.Value $file $logFull
                                }
                            }
                        }
                    }
                }
                $lastCommit = $newCommit
            }
        } catch {
             # Errores silenciosos al log para no matar el demonio
             $_.Exception.Message | Out-File -FilePath $logFull -Append
        }
        
        Start-Sleep -Seconds $alerta
        if (-not (Test-Path $pidFile)) { exit 0 }
    }
} finally {
    Remove-Item $pidFile -ErrorAction SilentlyContinue
}