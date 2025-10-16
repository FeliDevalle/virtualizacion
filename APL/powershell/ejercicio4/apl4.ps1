<#
.SYNOPSIS
  apl4.ps1 - Monitoreo de repositorios Git para patrones sensibles

.DESCRIPTION
  Demonio que monitoriza cambios en la rama principal y registra alertas cuando encuentra patrones sensibles.
  Uso:
    Iniciar:  .\apl4.ps1 -repo "C:\miRepo" -configuracion ".\patrones.conf" -alerta 10 -log "C:\audit.log"
    Detener:  .\apl4.ps1 -repo "C:\miRepo" -kill

.PARAMETER repo
  Ruta del repositorio Git a monitorear (acepta rutas relativas, absolutas y con espacios).

.PARAMETER configuracion
  Ruta del archivo de configuración con patrones. Soporta comentarios con '#' y prefijos 'regex:'.

.PARAMETER log
  Ruta del archivo donde se registran las alertas (por defecto"C:\audit.log).

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

function Get-TempDir {
    $tempPath = ''
    $lastError = ''

    try {
        $userTemp = [System.IO.Path]::GetTempPath()
        if (-not [string]::IsNullOrWhiteSpace($userTemp)) {
            $testFile = Join-Path $userTemp ([System.Guid]::NewGuid().ToString())
            New-Item -Path $testFile -ItemType File -Force > $null
            Remove-Item -Path $testFile -Force
            $tempPath = $userTemp
        }
    } catch {
        $lastError = $_.Exception.Message
    }
    
    if ([string]::IsNullOrWhiteSpace($tempPath)) {
        # recurrimos a las rutas de sistema como último recurso.
        if ($IsWindows) {
            $tempPath = Join-Path $env:windir "Temp"
        } else {
            $tempPath = "/tmp"
        }
    }

    if (-not (Test-Path $tempPath)) {
        try {
            New-Item -ItemType Directory -Path $tempPath -Force -ErrorAction Stop | Out-Null
        } catch {
            throw "No se pudo encontrar ni crear un directorio temporal válido. Último error: $lastError"
        }
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

# --- MODO LANZADOR ---
if (-not $daemon) {
    if (-not $repo) { Fail "Error: El parámetro -repo es obligatorio." }

    $pidFile = Get-PidFilePath $repo
    $errorFile = Get-ErrorFilePath $repo 

    if ($kill) {
        if (Test-Path $pidFile) {
            try {
                $pidToKill = [int](Get-Content $pidFile -ErrorAction Stop)
                if (Test-ProcessRunning $pidToKill) {
                    Stop-Process -Id $pidToKill -Force -ErrorAction SilentlyContinue
                    Write-Host "Demonio detenido (PID $pidToKill)."
                } else { Write-Host "El proceso del demonio (PID $pidToKill) ya no existía. Limpiando archivo PID." }
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
    
    Remove-Item $errorFile -ErrorAction SilentlyContinue

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
        Remove-Item $errorFile -ErrorAction SilentlyContinue 
        exit 0
    } else {
        $errorDetails = ""
        if (Test-Path $errorFile) {
            $errorDetails = Get-Content $errorFile
            Remove-Item $errorFile -ErrorAction SilentlyContinue
        }
        Fail "Fallo al iniciar el demonio. Causa del error:" $errorDetails
    }
}

# -------------------
# --- MODO DEMONIO ---
# -------------------
try {
    if (-not $repo) { throw "Parámetro -repo no fue recibido." }
    if (-not $configuracion) { throw "Parámetro -configuracion no fue recibido." }

    $repoFull = (Resolve-Path $repo -ErrorAction Stop).ProviderPath
    $configFull = (Resolve-Path $configuracion -ErrorAction Stop).ProviderPath
    $logFull = (Resolve-Path $log -ErrorAction Stop).ProviderPath

    if (-not (Test-Path (Join-Path $repoFull ".git"))) { throw "'$repoFull' no es un repositorio Git válido." }

    $pidFile = Get-PidFilePath $repoFull
    if (Test-Path $pidFile) {
        try {
            $otherPid = [int](Get-Content $pidFile -ErrorAction Stop)
            if (Test-ProcessRunning $otherPid) { exit 1 }
        } catch {}
    }
    $PID | Out-File -FilePath $pidFile -Encoding ascii -Force
} catch {
    $errorFileForDaemon = Get-ErrorFilePath $repo
    $_.Exception.Message | Out-File -FilePath $errorFileForDaemon -Encoding utf8
    exit 1
}

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