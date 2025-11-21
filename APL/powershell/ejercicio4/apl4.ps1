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
  Ruta del archivo donde se registran las alertas (por defecto "audit.log").

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

# Función auxiliar para obtener ruta absoluta incluso si el archivo no existe
function Get-AbsolutePath([string]$path) {
    # Expansión manual de ~ para Linux/Mac si es necesario
    if ($path.StartsWith("~")) {
        $homeDir = [System.Environment]::GetFolderPath('UserProfile')
        $path = $path.Replace("~", $homeDir)
    }
    return [System.IO.Path]::GetFullPath($path)
}

function Get-TempDir {
    $tempPath = ''
    $lastError = ''

    try {
        $userTemp = [System.IO.Path]::GetTempPath()
        if (-not [string]::IsNullOrWhiteSpace($userTemp)) {
            # Verificamos escritura creando un archivo dummy
            $testFile = Join-Path $userTemp ([System.Guid]::NewGuid().ToString())
            New-Item -Path $testFile -ItemType File -Force > $null
            Remove-Item -Path $testFile -Force
            $tempPath = $userTemp
        }
    } catch {
        $lastError = $_.Exception.Message
    }

    if ([string]::IsNullOrWhiteSpace($tempPath)) {
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
    # Normalizamos a una cadena segura para nombre de archivo
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

    # Resolvemos repo de forma absoluta para generar IDs consistentes
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
                } else { Write-Host "El proceso del demonio (PID $pidToKill) ya no existía. Limpiando archivo PID." }
            } catch { Write-Host "El archivo PID estaba corrupto o no se pudo leer." }
            finally { Remove-Item $pidFile -ErrorAction SilentlyContinue }
        } else { Write-Host "No se encontró un demonio en ejecución para este repositorio." }
        exit 0
    }

    # --- Lógica START ---
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

    # Preparamos rutas absolutas para pasarlas al hijo
    $scriptFullPath = $MyInvocation.MyCommand.Definition
    $repoAbs = $repoResolved
    $configAbs = (Resolve-Path $configuracion).Path
    
    # Corrección: Usamos nuestra función auxiliar para el log, ya que puede no existir
    $logAbs = Get-AbsolutePath $log

    $argList = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", "`"$scriptFullPath`"",
        "-repo", "`"$repoAbs`"",
        "-configuracion", "`"$configAbs`"",
        "-log", "`"$logAbs`"",
        "-alerta", $alerta, "-daemon"
    )

    # Corrección: Detectar binario (pwsh vs powershell) y evitar -WindowStyle en Linux
    $psBinary = "powershell"
    if ($IsLinux) { $psBinary = "pwsh" }

    $startParams = @{
        FilePath = $psBinary
        ArgumentList = $argList
        PassThru = $true
    }

    # Solo agregamos WindowStyle Hidden si NO es Linux/Unix
    if (-not $IsLinux) {
        $startParams["WindowStyle"] = "Hidden"
    }

    $process = Start-Process @startParams
    Start-Sleep -Seconds 1

    $wait = 0
    while (($wait -lt 5) -and (-not (Test-Path $pidFile))) {
        Start-Sleep -Milliseconds 200
        $wait += 1
    }

    if (Test-Path $pidFile) {
        $daemonPid = Get-Content $pidFile -ErrorAction SilentlyContinue
        Write-Host "Demonio iniciado en segundo plano (PID $daemonPid)."
        Write-Host "Monitoreando: $repoAbs"
        Write-Host "Log: $logAbs"
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

# -----------------------
# --- MODO DEMONIO ---
# -----------------------
try {
    # En modo demonio, las rutas ya vienen resueltas (absolutas) desde el lanzador
    if (-not $repo) { throw "Parámetro -repo no fue recibido." }
    if (-not $configuracion) { throw "Parámetro -configuracion no fue recibido." }
    
    $repoFull = $repo
    $configFull = $configuracion
    $logFull = $log

    # Verificación del log
    if (Test-Path -Path $logFull -PathType Container) {
        throw "La ruta para el archivo de log ('$logFull') no puede ser un directorio."
    }
    
    # Asegurar directorio del log
    $logDir = Split-Path -Parent $logFull
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    if (-not (Test-Path (Join-Path $repoFull ".git"))) { throw "'$repoFull' no es un repositorio Git válido." }

    $pidFile = Get-PidFilePath $repoFull
    
    # Doble chequeo de singleton
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
# Detectar la rama remota por defecto (generalmente main o master)
$branch = (git symbolic-ref refs/remotes/origin/HEAD -q) -replace 'refs/remotes/origin/', ''
if ([string]::IsNullOrWhiteSpace($branch)) { $branch = 'main' }

try {
    git fetch origin $branch 2>$null | Out-Null
    $lastCommit = (git rev-parse "origin/$branch" 2>$null).Trim()
} catch { $lastCommit = "" }

if ([string]::IsNullOrWhiteSpace($lastCommit)) {
    # Si falla el git inicial, escribimos error y salimos para no quedar zombies
    "No se pudo obtener el commit inicial de origin/$branch" | Out-File -FilePath (Get-ErrorFilePath $repoFull)
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
        try {
            git fetch origin $branch 2>$null | Out-Null
            $newCommit = (git rev-parse "origin/$branch" 2>$null).Trim()

            if (-not [string]::IsNullOrWhiteSpace($newCommit) -and $newCommit -ne $lastCommit) {
                
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
            }
        } catch {
            $errTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            ("[$errTs] ERROR durante el ciclo de monitoreo: {0}" -f $_.Exception.ToString()) | Out-File -FilePath $logFull -Append -Encoding utf8
        }
        
        Start-Sleep -Seconds $alerta

        # Verificación de vida: si el archivo PID fue borrado (por comando kill), salir
        if (-not (Test-Path $pidFile)) { exit 0 }
    }
} finally {
    Remove-Item $pidFile -ErrorAction SilentlyContinue
}