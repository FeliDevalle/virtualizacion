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
#     CORONEL, THIAGO MARTÍN
#     DEVALLE, FELIPE PEDRO
#     MURILLO, JOEL ADAN
#     RUIZ, RAFAEL DAVID NAZARENO

param(
    [Parameter(Mandatory=$true, HelpMessage="La ruta al repositorio Git es obligatoria.")]
    [string]$repo,
    
    # <-- CAMBIO: Hice el parámetro de configuración no mandatorio en el bloque param
    # para poder manejar la lógica de -kill más limpiamente. La validación manual se mantiene.
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
    # Genera un nombre de archivo seguro para el PID basado en la ruta del repositorio
    $safe = ($repoPath -replace '[\\/: ]','_') -replace '[^\w\-_\.]','_'
    return Join-Path $env:TEMP "audit_$safe.pid"
}

function Test-ProcessRunning([int]$pid1) {
    # Verifica si un proceso con un PID específico está en ejecución
    return $(try { Get-Process -Id $pid1 -ErrorAction Stop } catch { $false }) -ne $false
}

# --- MODO LANZADOR ---
# Esta sección se ejecuta cuando el script no se llama a sí mismo como demonio.
# Su responsabilidad es validar parámetros y lanzar/detener el proceso en segundo plano.
if (-not $daemon) {
    if (-not $repo) { Fail "Error: El parámetro -repo es obligatorio." }
    
    $pidFile = Get-PidFilePath $repo

    # Lógica para detener (kill) el demonio
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
            } catch {
                Write-Host "El archivo PID estaba corrupto o no se pudo leer."
            } finally {
                Remove-Item $pidFile -ErrorAction SilentlyContinue
            }
        } else {
            Write-Host "No se encontró un demonio en ejecución para este repositorio."
        }
        exit 0
    }

    # Si no es -kill, el archivo de configuración es obligatorio
    if (-not $configuracion) { Fail "Error: El parámetro -configuracion es obligatorio para iniciar el demonio." }

    # Prevenir que se inicie un segundo demonio para el mismo repositorio
    if (Test-Path $pidFile) {
        try {
            $existingPid = [int](Get-Content $pidFile -ErrorAction Stop)
            if (Test-ProcessRunning $existingPid) {
                Fail "Error: Ya existe un demonio en ejecución para este repositorio (PID: $existingPid)."
            } else {
                # Limpiar archivo PID de un proceso que ya no existe
                Remove-Item $pidFile -ErrorAction SilentlyContinue
            }
        } catch {
            Remove-Item $pidFile -ErrorAction SilentlyContinue
        }
    }

    # Lanzar el script en modo demonio en un nuevo proceso de PowerShell
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
    Start-Process -FilePath powershell.exe -ArgumentList $argList -WindowStyle Hidden -PassThru | Out-Null
    Start-Sleep -Seconds 1

    # Esperar un poco a que el demonio cree su archivo PID
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
        Fail "Fallo al iniciar el demonio. Verifique los permisos y las rutas."
    }
}

# -------------------
# --- MODO DEMONIO ---
# Ejecución del bucle de monitoreo. Esta parte corre en segundo plano.
# -------------------

# Validaciones críticas dentro del demonio
if (-not $repo) { exit 1 }
if (-not $configuracion) { exit 1 }

# Convertir todas las rutas a absolutas para evitar problemas con el directorio de trabajo
try {
    $repoFull = (Resolve-Path $repo).ProviderPath
    $configFull = (Resolve-Path $configuracion).ProviderPath
    $logFull = (Resolve-Path $log).ProviderPath
} catch {
    # Si alguna ruta falla, el demonio no puede continuar
    ("Error fatal al resolver rutas: " + $_.Exception.Message) | Out-File (Join-Path $env:TEMP "audit_error.log") -Append
    exit 1
}

if (-not (Test-Path (Join-Path $repoFull ".git"))) {
    Fail "Error: '$repoFull' no parece ser un repositorio Git válido."
}

$pidFile = Get-PidFilePath $repoFull

# Doble chequeo para evitar condiciones de carrera
if (Test-Path $pidFile) {
    try {
        $otherPid = [int](Get-Content $pidFile -ErrorAction Stop)
        if (Test-ProcessRunning $otherPid) { exit 1 }
    } catch { }
}
$PID | Out-File -FilePath $pidFile -Encoding ascii -Force

# Establecer el directorio de trabajo en el repositorio
Set-Location $repoFull

# Detectar la rama principal del repositorio
$branch = (git symbolic-ref refs/remotes/origin/HEAD -q) -replace 'refs/remotes/origin/', ''
if ([string]::IsNullOrWhiteSpace($branch)) { $branch = 'main' } # Fallback a 'main'

# Obtener el hash del último commit como punto de partida
try {
    git fetch origin $branch 2>$null | Out-Null
    $lastCommit = (git rev-parse "origin/$branch" 2>$null).Trim()
} catch { $lastCommit = "" }

if ([string]::IsNullOrWhiteSpace($lastCommit)) {
    $msg = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR: No se pudo resolver el commit inicial para origin/$branch."
    $msg | Out-File -FilePath $logFull -Append -Encoding utf8
    Remove-Item $pidFile -ErrorAction SilentlyContinue
    exit 1
}

function Write-Alert([string]$pattern, [string]$file) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] Alerta: patrón '$pattern' encontrado en el archivo '$file'."
    $line | Out-File -FilePath $logFull -Append -Encoding utf8
}

# Bucle principal de monitoreo
try {
    while ($true) {
        git fetch origin $branch 2>$null | Out-Null
        $newCommit = (git rev-parse "origin/$branch" 2>$null).Trim()

        if (-not [string]::IsNullOrWhiteSpace($newCommit) -and $newCommit -ne $lastCommit) {
            try {
                $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                ("[$ts] Nuevo commit detectado: {0}" -f $newCommit) | Out-File -FilePath $logFull -Append -Encoding utf8
                
                # <-- CAMBIO PRINCIPAL 1: Leer y procesar los patrones UNA SOLA VEZ por commit.
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

                # Obtener la lista de archivos modificados
                $files = git diff --name-only $lastCommit $newCommit 2>$null
                
                foreach ($file in $files) {
                    $spec = "{0}:{1}" -f $newCommit, $file
                    $content = git show $spec 2>$null
                    
                    # <-- CAMBIO PRINCIPAL 2: Validar que el contenido del archivo no sea nulo.
                    if ($null -ne $content) {
                        # <-- CAMBIO PRINCIPAL 3: Iterar sobre los patrones ya procesados.
                        foreach ($patternObj in $patterns) {
                            if ($patternObj.Type -eq 'Regex') {
                                try {
                                    if ($content -match $patternObj.Value) {
                                        Write-Alert $patternObj.Value $file
                                    }
                                } catch {
                                    $err = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR: patrón regex inválido '$($patternObj.Value)' en $configFull."
                                    $err | Out-File -FilePath $logFull -Append -Encoding utf8
                                }
                            } else { # Literal
                                if ($content.IndexOf($patternObj.Value, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                                    Write-Alert $patternObj.Value $file
                                }
                            }
                        }
                    }
                }
                # Actualizar el último commit solo si todo el proceso fue exitoso
                $lastCommit = $newCommit
            } catch {
                $errTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                ("[$errTs] ERROR procesando commit {0}: {1}" -f $newCommit, $_.Exception.ToString()) | Out-File -FilePath $logFull -Append -Encoding utf8
            }
        }
        
        Start-Sleep -Seconds $alerta

        # Salir limpiamente si el archivo PID fue eliminado por el comando -kill
        if (-not (Test-Path $pidFile)) {
            exit 0
        }
    }
} finally {
    # Asegurarse de que el archivo PID se elimine al salir
    Remove-Item $pidFile -ErrorAction SilentlyContinue
}