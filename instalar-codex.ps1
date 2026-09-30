# instalar-codex.ps1 - Deja lista una laptop Windows para Codex (curso Ed Digital TEC, sesion 3)
#
# Uso (pegar en PowerShell, NO en CMD):
#   irm https://bandeja-eddigital.jorgeeduai.app/instalar-codex.ps1 | iex
# Espejo, si la red bloquea la bandeja:
#   irm https://raw.githubusercontent.com/jorgeeduai/instalador/main/instalar-codex.ps1 | iex
# Prueba local antes de publicar (desde la carpeta donde esta el archivo):
#   powershell -ExecutionPolicy Bypass -File instalar-codex.ps1
#
# Hace, en orden: Python real -> librerias de Office -> Codex (instalador oficial de OpenAI) -> llave de OpenAI
# -> configuracion del curso -> verificacion.
# Se puede correr varias veces sin romper nada. Si un paso falla, solo avisa y los demas siguen.
# Sin acentos a proposito: PowerShell 5.1 los maltrata al leer por irm. Usa return y no exit porque corre dentro de iex.

$ErrorActionPreference = "Continue"
# Revision 29-sep: si en esta misma ventana ya se corrio el instalador oficial de Codex con irm | iex, este dejo
# Set-StrictMode -Version Latest encendido en la ventana. Con eso, en PowerShell 7 un error de red en la prueba de
# la llave detiene el resto del script (simulado en pwsh 7.6 en el Studio). Se apaga aqui; no afecta a nada mas.
Set-StrictMode -Off

# ---------------------------------------------------------------- Valores del curso (cambialos aqui)
$ModeloCurso    = "gpt-6-sol"     # modelo de Codex por API
$EsfuerzoCurso  = "medium"        # esfuerzo de razonamiento sugerido por OpenAI para Sol
$SandboxWindows = "unelevated"    # sandbox nativo que no pide administrador; "elevated" pide permiso de administrador
$PyVersion      = "3.13.15"       # Python de python.org si hace falta instalarlo
$PySha256 = @{
    "amd64" = "edec09c4853aeae9ac36efb8c9f95b6b8e2fee65eee56d9767a8b7c69c574403"
    "arm64" = "c252c676087c49e6b94e95a273536b78921c28a5fc9f86d15d25392328247249"
}
$PyWinget       = "Python.Python.3.13"
$Librerias      = @("openpyxl", "python-docx", "python-pptx")

$carpeta   = "$HOME\Documents\claude-proyectos"
$codexBin  = "$env:LOCALAPPDATA\Programs\OpenAI\Codex\bin"
$codexExe  = "$codexBin\codex.exe"
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { "$env:USERPROFILE\.codex" }
$pendientes = @()
$python = $null

try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072 } catch { }

function Paso($t)  { Write-Host ""; Write-Host "==> $t" -ForegroundColor Cyan }
function Ok($t)    { Write-Host "    OK  $t" -ForegroundColor Green }
function Aviso($t) { Write-Host "    !!  $t" -ForegroundColor Yellow }

# Rearma el PATH de esta ventana: maquina, usuario y lo que ya tenia, sin repetir.
function Refrescar-Path {
    $nuevo = @()
    foreach ($f in @([Environment]::GetEnvironmentVariable("Path", "Machine"), [Environment]::GetEnvironmentVariable("Path", "User"), $env:Path)) {
        if (-not $f) { continue }
        foreach ($p in $f.Split(";")) {
            $q = $p.Trim()
            if ($q -and ($nuevo -notcontains $q)) { $nuevo += $q }
        }
    }
    $env:Path = $nuevo -join ";"
}

# Agrega una carpeta al final del PATH del usuario si no estaba. Devuelve $true si cambio algo.
function Agregar-PathUsuario([string]$dir) {
    $actual = [Environment]::GetEnvironmentVariable("Path", "User")
    $lista = @()
    if ($actual) { $lista = @($actual.Split(";") | Where-Object { $_.Trim() -ne "" }) }
    foreach ($x in $lista) { if ($x.TrimEnd("\") -ieq $dir.TrimEnd("\")) { return $false } }
    [Environment]::SetEnvironmentVariable("Path", (($lista + @($dir)) -join ";"), "User")
    return $true
}

# Pone estas carpetas al principio del PATH del usuario (antes del acceso directo de la Microsoft Store).
function Poner-Primero-PathUsuario([string[]]$dirs) {
    $actual = [Environment]::GetEnvironmentVariable("Path", "User")
    $lista = @()
    if ($actual) { $lista = @($actual.Split(";") | Where-Object { $_.Trim() -ne "" }) }
    $resto = @()
    foreach ($x in $lista) {
        $repetida = $false
        foreach ($d in $dirs) { if ($x.TrimEnd("\") -ieq $d.TrimEnd("\")) { $repetida = $true } }
        if (-not $repetida) { $resto += $x }
    }
    $texto = (@($dirs) + $resto) -join ";"
    if ($texto -ne $actual) {
        [Environment]::SetEnvironmentVariable("Path", $texto, "User")
        return $true
    }
    return $false
}

# Corre un python.exe y devuelve su version si es Python 3.9 o mas nuevo y funciona de verdad.
function Probar-Python([string]$exe) {
    if (-not $exe) { return $null }
    try {
        $v = & $exe -c "import sys; print('%d.%d.%d' % sys.version_info[:3]) if sys.version_info >= (3, 9) else sys.exit(3)" 2>$null
        if ($LASTEXITCODE -eq 0 -and "$v" -match '^3\.\d+\.\d+') { return "$v".Trim() }
    } catch { }
    return $null
}

# Busca un Python real. El acceso directo de la Microsoft Store (carpeta WindowsApps) no cuenta:
# sin Python instalado solo imprime un mensaje y sale con error, y correrlo sin argumentos abre la tienda.
function Buscar-Python {
    $candidatos = @()
    foreach ($c in @(Get-Command python.exe, python3.exe -All -CommandType Application -ErrorAction SilentlyContinue)) {
        $candidatos += $c.Source
    }
    $py = Get-Command py.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    # Revision 29-sep: un py.exe en WindowsApps es el Python install manager de la Store; si no tiene ningun
    # Python, 'py' instala uno solo y sin avisar (automatic_install, docs.python.org/3/using/windows.html).
    # Se trata igual que el acceso directo de la tienda: no se ejecuta.
    if ($py -and $py.Source -notlike "*\Microsoft\WindowsApps\*") {
        try {
            $s = & $py.Source -3 -c "import sys; print(sys.executable)" 2>$null
            if ($LASTEXITCODE -eq 0 -and $s) { $candidatos += "$($s | Select-Object -Last 1)".Trim() }
        } catch { }
    }
    $raiz = "$env:LOCALAPPDATA\Programs\Python"
    if (Test-Path $raiz) {
        $candidatos += @(Get-ChildItem -Path "$raiz\Python3*\python.exe" -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | ForEach-Object { $_.FullName })
    }
    foreach ($exe in ($candidatos | Select-Object -Unique)) {
        if (-not $exe) { continue }
        if ($exe -like "*\Microsoft\WindowsApps\*") { continue }
        $v = Probar-Python $exe
        if ($v) { return @{ Exe = $exe; Version = $v } }
    }
    return $null
}

# El python.exe (o el nombre que se pida, por ejemplo python3.exe) que encontrara una ventana nueva de PowerShell:
# el primero en el PATH guardado (maquina y luego usuario).
# Devuelve $null si el primero es el acceso directo de la Microsoft Store o si no hay ninguno.
function Python-En-Ventana-Nueva([string]$nombre = "python.exe") {
    $dirs = @()
    foreach ($f in @([Environment]::GetEnvironmentVariable("Path", "Machine"), [Environment]::GetEnvironmentVariable("Path", "User"))) {
        if ($f) { $dirs += $f.Split(";") }
    }
    foreach ($d in $dirs) {
        try {
            $d2 = [Environment]::ExpandEnvironmentVariables($d.Trim())
            if (-not $d2) { continue }
            $c = Join-Path $d2 $nombre
            if (Test-Path -LiteralPath $c) {
                if ($c -like "*\Microsoft\WindowsApps\*") { return $null }
                return $c
            }
        } catch { }
    }
    return $null
}

# Ajuste 29-sep (python3): prueba 'python3' tal como lo escribiria un agente en esta ventana, con
# python3 -c "import sys; print(sys.version)". Devuelve la version (por ejemplo 3.13.15) o $null.
# Si 'python3' es el acceso directo de la Microsoft Store (WindowsApps) no se ejecuta y cuenta como que no responde.
function Probar-Python3 {
    $c = Get-Command python3.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $c -or $c.Source -like "*\Microsoft\WindowsApps\*") { return $null }
    try {
        $v = & $c.Source -c "import sys; print(sys.version)" 2>$null
        if ($LASTEXITCODE -eq 0 -and "$v" -match '^(3\.\d+\.\d+)') { return $Matches[1] }
    } catch { }
    return $null
}

function Arquitectura {
    $a = $null
    try { $a = [string][System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture } catch { }
    if (-not $a) {
        $a = $env:PROCESSOR_ARCHITEW6432
        if (-not $a) { $a = $env:PROCESSOR_ARCHITECTURE }
    }
    if ($a -match "arm64") { return "arm64" }
    return "amd64"
}

# Descarga el instalador oficial de python.org, revisa su huella SHA-256 y lo corre solo para este usuario.
function Instalar-Python {
    $arq = Arquitectura
    $url = "https://www.python.org/ftp/python/$PyVersion/python-$PyVersion-$arq.exe"
    $tmp = Join-Path $env:TEMP "python-$PyVersion-$arq.exe"
    Write-Host "    Descargando Python $PyVersion ($arq, unos 28 MB) desde python.org..."
    $pp = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"
    try {
        Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -TimeoutSec 600
    } catch {
        $ProgressPreference = $pp
        Aviso "No se pudo descargar Python de python.org: $($_.Exception.Message)"
        return $false
    }
    $ProgressPreference = $pp
    $hash = (Get-FileHash -Path $tmp -Algorithm SHA256).Hash.ToLower()
    if ($hash -ne $PySha256[$arq]) {
        Aviso "La descarga de Python llego danada o alterada (la huella no coincide). No se instalo."
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        return $false
    }
    Write-Host "    Instalando Python solo para tu usuario, sin permisos de administrador (1 o 2 minutos, sin ventanas)..."
    $opciones = @("/quiet", "InstallAllUsers=0", "PrependPath=1", "Include_launcher=0", "Include_test=0", "Include_doc=0")
    $proc = Start-Process -FilePath $tmp -ArgumentList $opciones -Wait -PassThru
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
        Aviso "El instalador de Python termino con el codigo $($proc.ExitCode)."
        return $false
    }
    return $true
}

# Devuelve la version de las tres librerias si se pueden importar.
function Probar-Librerias([string]$exe) {
    try {
        $v = & $exe -c "import openpyxl, docx, pptx; from importlib.metadata import version as v; print('openpyxl ' + v('openpyxl') + ', python-docx ' + v('python-docx') + ', python-pptx ' + v('python-pptx'))" 2>$null
        if ($LASTEXITCODE -eq 0 -and $v) { return "$v".Trim() }
    } catch { }
    return $null
}

# Pregunta a OpenAI por el modelo del curso con esa llave. 200 = sirve, 401 = llave rechazada, 404 = modelo no visible, 0 = sin respuesta.
function Probar-Llave([string]$k) {
    try {
        $r = Invoke-WebRequest -Uri "https://api.openai.com/v1/models/$ModeloCurso" -Headers @{ Authorization = "Bearer $k" } -UseBasicParsing -TimeoutSec 20
        return [int]$r.StatusCode
    } catch {
        if ($_.Exception.Response) { try { return [int]$_.Exception.Response.StatusCode } catch { } }
        return 0
    }
}

function Texto-Seguro($s) {
    if (-not $s -or $s.Length -eq 0) { return "" }
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

# Estado de la llave segun Codex, con la llave enmascarada (Codex solo muestra el inicio y los ultimos caracteres).
# Revision 29-sep: 'codex login status' escribe en stderr (comprobado con 0.154.0 en el Studio). Windows
# PowerShell 5.1 suele pintar ese stderr capturado con '2>&1 | Out-String' como error (NativeCommandError,
# 'At line:...'), y ese texto se colaria en las lineas OK de los pasos 4 y 6 (no comprobado en 5.1; pwsh 7.6
# no lo hace). ForEach-Object { "$_" } deja solo el texto en las dos versiones.
function Estado-Llave {
    if (-not (Test-Path $codexExe)) { return "" }
    try { return (& $codexExe login status 2>&1 | ForEach-Object { "$_" } | Out-String).Trim() } catch { return "" }
}

Write-Host ""
Write-Host "Instalador del curso - Codex en Windows" -ForegroundColor Cyan
Write-Host "No cierres esta ventana hasta ver el mensaje final. Puede tardar varios minutos segun tu internet."

# ---------------------------------------------------------------- 1. Python
Paso "1/6 Python (el agente lo usa para leer y escribir Excel, Word y PowerPoint)"
try {
    $py = Buscar-Python
    if ($py) {
        Ok "Python $($py.Version) ya estaba: $($py.Exe)"
    } else {
        Write-Host "    No encontre un Python que funcione (el acceso directo de la Microsoft Store no cuenta)."
        $null = Instalar-Python
        Refrescar-Path
        $py = Buscar-Python
        if (-not $py) {
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                Aviso "Intento de nuevo con winget (descarga el mismo instalador de python.org)..."
                winget install --id $PyWinget -e --scope user --silent --accept-source-agreements --accept-package-agreements
                Refrescar-Path
                $py = Buscar-Python
            } else {
                Aviso "winget no esta disponible en esta maquina, asi que no hay segundo intento automatico."
            }
        }
        if ($py) { Ok "Python $($py.Version) instalado: $($py.Exe)" }
    }
    if ($py) {
        $python = $py.Exe
        $dirPy = Split-Path $python
        if (Poner-Primero-PathUsuario @($dirPy, "$dirPy\Scripts")) { Ok "Python quedo primero en el PATH del usuario" }
        Refrescar-Path
        # Ajuste 29-sep (python3): el Python de python.org trae python.exe pero no python3.exe. Si un agente escribe
        # 'python3' (Claude Code lo hizo en el ensayo de la S3; Codex escribio 'python'), Windows encuentra el acceso
        # directo de la Microsoft Store y falla. Si 'python3' no es un Python real, se copia python.exe como
        # python3.exe en la carpeta de este Python: solo si no existe ya y nunca en WindowsApps. La copia funciona
        # porque python.exe busca sus archivos en su propia carpeta.
        $v3 = Probar-Python3
        if ($v3) {
            Ok "python3 tambien responde (Python $v3)"
        } else {
            $py3 = Join-Path $dirPy "python3.exe"
            # Revision adversarial 29-sep: *\WindowsApps* cubre tambien C:\Program Files\WindowsApps (paquetes de la
            # tienda), no solo %LOCALAPPDATA%\Microsoft\WindowsApps. Ahi nunca se copia nada.
            if ($dirPy -like "*\WindowsApps*") {
                Aviso "Este Python vive en la carpeta de la Microsoft Store; no le agrego python3."
            } elseif (-not (Test-Path -LiteralPath $py3)) {
                try {
                    Copy-Item -LiteralPath $python -Destination $py3 -ErrorAction Stop
                    # Revision adversarial 29-sep: se prueba la copia misma. Si python.exe era un atajo que depende de
                    # su nombre (por ejemplo, un shim de scoop), la copia no corre: se borra para no dejar un python3
                    # roto antes que los demas en el PATH (simulado en pwsh 7.6 en el Studio).
                    if (Probar-Python $py3) {
                        Ok "Agregue python3.exe junto a python.exe (para los agentes que escriben python3)"
                    } else {
                        Remove-Item -LiteralPath $py3 -Force -ErrorAction SilentlyContinue
                        Aviso "La copia python3.exe no funciono en ${dirPy}; la borre."
                    }
                } catch {
                    Aviso "No pude agregar python3.exe en ${dirPy}: $($_.Exception.Message)"
                }
            }
            Refrescar-Path
            $v3 = Probar-Python3
            if ($v3) {
                Ok "python3 responde (Python $v3)"
            } else {
                Aviso "En esta ventana 'python3' no responde; 'python' si. Si un agente falla con python3, que use python."
            }
        }
    } else {
        Aviso "Python no quedo instalado. Instalalo a mano desde https://www.python.org/downloads/windows/"
        Aviso "(marca la casilla 'Add python.exe to PATH') y vuelve a correr esta misma linea."
        $pendientes += "Python"
    }
} catch {
    Aviso "Algo fallo revisando Python: $($_.Exception.Message)"
    $pendientes += "Python"
}

# ---------------------------------------------------------------- 2. Librerias para Office
Paso "2/6 Librerias de Python para Excel, Word y PowerPoint"
if (-not $python) {
    Aviso "Sin Python no se pueden instalar. Se instalan solas cuando vuelvas a correr la linea con Python listo."
    $pendientes += "librerias"
} else {
    try {
        & $python -m pip --version *> $null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    Este Python no traia pip; lo agrego..."
            & $python -m ensurepip --user *> $null
        }
        Write-Host "    Instalando $($Librerias -join ', ') (1 o 2 minutos)..."
        # ForEach-Object { "$_" }: en PowerShell 5.1 el stderr de pip saldria decorado como error (ver Estado-Llave).
        $salida = & $python -m pip install --user --upgrade --disable-pip-version-check --no-warn-script-location -q @Librerias 2>&1 | ForEach-Object { "$_" } | Out-String
        $v = Probar-Librerias $python
        if ($v) {
            Ok "Listas: $v"
            $pyNueva = Python-En-Ventana-Nueva
            if ($pyNueva -and ($pyNueva -ne $python) -and (Probar-Python $pyNueva) -and -not (Probar-Librerias $pyNueva)) {
                Write-Host "    Una ventana nueva usara otro Python ($pyNueva); le instalo tambien las librerias..."
                $null = & $pyNueva -m pip install --user --upgrade --disable-pip-version-check --no-warn-script-location -q @Librerias 2>&1 | Out-String
                if (Probar-Librerias $pyNueva) { Ok "Tambien listas en $pyNueva" } else { Aviso "No se pudieron instalar en $pyNueva"; $pendientes += "librerias" }
            }
        } else {
            if ($salida -match "SSL|Proxy|Max retries|getaddrinfo|NewConnectionError|timed out|ConnectTimeout") {
                Aviso "La red no dejo descargar las librerias (pypi.org). Prueba con otra red, por ejemplo el hotspot del celular, y vuelve a correr la linea."
            } else {
                Aviso "pip no pudo instalar las librerias. Ultimas lineas de pip:"
                foreach ($l in @(($salida.Trim() -split "`r?`n") | Select-Object -Last 6)) { Write-Host "        $l" }
            }
            $pendientes += "librerias"
        }
    } catch {
        Aviso "Algo fallo instalando las librerias: $($_.Exception.Message)"
        $pendientes += "librerias"
    }
}

# ---------------------------------------------------------------- 3. Codex
# Instalador oficial: https://chatgpt.com/codex/install.ps1 (redirige a releases.openai.com). Deja el programa en
# %USERPROFILE%\.codex\packages\standalone, el comando en %LOCALAPPDATA%\Programs\OpenAI\Codex\bin y agrega esa carpeta
# al PATH del usuario. No necesita Node ni npm. Se corre en un PowerShell hijo para que su 'exit' y su StrictMode no
# toquen esta ventana; CODEX_NON_INTERACTIVE=1 evita que al final pregunte si abrir Codex.
Paso "3/6 Codex (instalador oficial de OpenAI)"
try {
    if (-not [Environment]::Is64BitOperatingSystem) {
        Aviso "Codex necesita Windows de 64 bits y esta maquina es de 32. Avisale a Jorge."
        $pendientes += "Codex"
    } else {
        if (Test-Path $codexExe) { Ok "Codex ya estaba instalado; se revisa si hay version nueva" }
        Write-Host "    Descarga de unos 160 MB sin barra de avance: si la pantalla se queda quieta un par de minutos, es normal."
        $antesNI = $env:CODEX_NON_INTERACTIVE
        $env:CODEX_NON_INTERACTIVE = "1"
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command '[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072; irm https://chatgpt.com/codex/install.ps1 | iex'
        $codigo = $LASTEXITCODE
        $env:CODEX_NON_INTERACTIVE = $antesNI
        if ($codigo -ne 0) { Aviso "El instalador oficial termino con el codigo $codigo." }
    }
} catch {
    Aviso "El instalador oficial marco un error: $($_.Exception.Message)"
}
if (Test-Path $codexExe) {
    if (Agregar-PathUsuario $codexBin) { Ok "Carpeta de Codex agregada al PATH del usuario" } else { Ok "El PATH del usuario ya tenia a Codex" }
    if ($env:Path -notlike "*$codexBin*") { $env:Path = "$codexBin;$env:Path" }
    $v = & $codexExe --version 2>$null
    Ok "Codex instalado: $v"
} elseif ($pendientes -notcontains "Codex") {
    Aviso "No encontre codex.exe en $codexBin."
    Aviso "Si la red o el antivirus bloquearon la descarga, prueba con otra red y vuelve a correr la linea."
    $pendientes += "Codex"
}

# ---------------------------------------------------------------- 4. Llave de OpenAI
# Codex guarda la llave con 'codex login --with-api-key' (la lee de la entrada, no de la linea de comandos) en
# %USERPROFILE%\.codex\auth.json. Codex no toma la variable OPENAI_API_KEY por si sola, por eso no se usa.
Paso "4/6 Llave de OpenAI del curso"
if (-not (Test-Path $codexHome)) { New-Item -ItemType Directory -Path $codexHome -Force | Out-Null }
if (-not (Test-Path $codexExe)) {
    Aviso "Primero tiene que quedar Codex (paso 3). La llave se pide cuando vuelvas a correr la linea."
    $pendientes += "llave"
} else {
    $pedir = $true
    $estado = Estado-Llave
    if ($estado -match "API key") {
        Ok "Ya hay una llave guardada: $($estado -replace '^.*API key\s*-\s*', '')"
        $r = Read-Host "    Escribe S para reemplazarla, o Enter para dejarla"
        if ($r -ne "S" -and $r -ne "s") { $pedir = $false }
    } elseif ($estado -match "ChatGPT") {
        Aviso "Codex tiene abierta una sesion de ChatGPT. En el curso se usa la llave de OpenAI que recibiste de Jorge."
        $r = Read-Host "    Escribe S para cambiarla por tu llave, o Enter para dejarla"
        if ($r -ne "S" -and $r -ne "s") { $pedir = $false }
    }
    if ($pedir) {
        Write-Host "    Pega la llave de OpenAI que recibiste de Jorge (empieza con sk-proj- o sk-) y presiona Enter."
        Write-Host "    Por seguridad no se ve lo que pegas: solo veras asteriscos."
        $seguro = Read-Host "    Llave" -AsSecureString
        $llave = (Texto-Seguro $seguro) -replace '\s', ''
        $llave = $llave.Trim([char]34, [char]39)
        $seguro = $null
        if ($llave -eq "") {
            Aviso "No pegaste nada. Vuelve a correr la linea cuando tengas tu llave a la mano."
            $pendientes += "llave"
        } elseif ($llave -like "sk-ant-*") {
            Aviso "Esa es la llave de Claude Code (empieza con sk-ant-). Codex usa la llave de OpenAI (empieza con sk-proj- o sk-)."
            Aviso "No se guardo nada. Vuelve a correr la linea y pega la de OpenAI."
            $pendientes += "llave"
        } elseif ($llave -notlike "sk-*") {
            Aviso "Eso no parece una llave de OpenAI (deberia empezar con sk-). No se guardo nada; vuelve a correr la linea."
            $pendientes += "llave"
        } else {
            $fin = $llave.Substring([Math]::Max(0, $llave.Length - 4))
            Write-Host "    Recibi la llave que termina en ...$fin. La pruebo con OpenAI..."
            $codigo = Probar-Llave $llave
            if ($codigo -eq 401) {
                Aviso "OpenAI rechazo esa llave (codigo 401): esta incompleta, tiene un caracter de mas o ya se apago."
                Aviso "No se guardo nada. Copiala otra vez completa del mensaje de Jorge y vuelve a correr la linea."
                $pendientes += "llave"
            } else {
                if ($codigo -eq 200) { Ok "OpenAI reconoce la llave y el modelo del curso ($ModeloCurso) esta disponible" }
                elseif ($codigo -eq 404) { Aviso "La llave es valida pero el modelo $ModeloCurso no aparece para esa cuenta. Se guarda igual; avisale a Jorge." }
                elseif ($codigo -eq 0) { Aviso "No pude comprobar la llave con OpenAI (la red no respondio). Se guarda igual." }
                else { Aviso "OpenAI respondio con el codigo $codigo al probar la llave. Se guarda igual; si Codex falla, avisale a Jorge." }
                # La llave es ASCII; se fija la codificacion para que ningun perfil le agregue un BOM al pasarla.
                $antesOE = $OutputEncoding
                $OutputEncoding = New-Object System.Text.ASCIIEncoding
                $salida = $llave | & $codexExe login --with-api-key 2>&1 | ForEach-Object { "$_" } | Out-String
                $guardo = ($LASTEXITCODE -eq 0)
                $OutputEncoding = $antesOE
                if ($guardo) {
                    Ok "Llave guardada para Codex (termina en ...$fin)"
                } else {
                    Aviso "Codex no pudo guardar la llave: $($salida.Trim())"
                    $pendientes += "llave"
                }
            }
        }
        $llave = $null
    }
}

# ---------------------------------------------------------------- 5. Configuracion del curso
# %USERPROFILE%\.codex\config.toml: modelo y esfuerzo del curso, sin menu de actualizacion al abrir, y el sandbox de
# Windows que no pide administrador.
# Si el archivo ya existe no se pisa: solo se agregan las claves que falten. Un modelo ya elegido se respeta.
Paso "5/6 Configuracion del curso para Codex"
try {
    if (-not (Test-Path $codexHome)) { New-Item -ItemType Directory -Path $codexHome -Force | Out-Null }
    $cfg = Join-Path $codexHome "config.toml"
    $texto = ""
    if (Test-Path $cfg) { $texto = [IO.File]::ReadAllText($cfg) }
    $cabeza = ($texto -split '(?m)^[ \t]*\[', 2)[0]
    $arriba = @()
    $lineaModelo = ([regex]::Match($cabeza, '(?m)^[ \t]*model[ \t]*=.*$')).Value
    if ($lineaModelo -and $lineaModelo -like "*`"$ModeloCurso`"*") {
        Ok "config.toml ya tenia el modelo del curso"
    } elseif ($lineaModelo) {
        Aviso "Tu config.toml ya elige otro modelo y se respeta: $($lineaModelo.Trim())"
    } else {
        $arriba += "model = `"$ModeloCurso`""
    }
    if ($cabeza -notmatch '(?m)^[ \t]*model_reasoning_effort[ \t]*=') { $arriba += "model_reasoning_effort = `"$EsfuerzoCurso`"" }
    # Ajuste 29-sep: sin el menu "Update available" al abrir Codex. Codex sale casi a diario y ese menu frena la clase.
    # Clave oficial check_for_update_on_startup (learn.chatgpt.com/docs/config-file/config-reference). Probada en vivo en
    # el Studio con Codex 0.158.0 frente a 0.159.0 publicada: sin la clave sale el menu; con false, no. Para actualizar
    # Codex se vuelve a correr la linea del curso (el paso 3 baja la version nueva). Si ya hay un valor, se respeta.
    # Revision adversarial 29-sep: se busca en TODO el archivo y tambien con la clave entre comillas. Con la cabeza sola,
    # un arreglo de varias lineas con una linea que empieza con [ la cortaba antes de tiempo, y "check_for_update_on_startup"
    # entre comillas no se reconocia: en los dos casos la clave quedaba repetida y Codex ya no podia leer el archivo
    # (comprobado con tomllib). Si la clave aparece en cualquier parte no se agrega: que falte solo deja el menu.
    if ($texto -notmatch '(?m)^[ \t]*["'']?check_for_update_on_startup["'']?[ \t]*=') {
        $arriba += "# Sin el menu 'Update available' al abrir Codex. Para actualizar, vuelve a correr la linea del curso."
        $arriba += "check_for_update_on_startup = false"
    }
    $abajo = @()
    # Revision 29-sep: [.=] y no solo \. para reconocer tambien 'windows = { ... }'; si no, se agregaba una
    # segunda tabla [windows] y Codex ya no podia leer el archivo (comprobado con tomllib).
    if ($texto -notmatch '(?m)^[ \t]*\[windows\]' -and $cabeza -notmatch '(?m)^[ \t]*windows[ \t]*[.=]') {
        $abajo += @("[windows]", "sandbox = `"$SandboxWindows`"")
    }
    if ($arriba.Count -eq 0 -and $abajo.Count -eq 0) {
        Ok "config.toml ya estaba listo: $cfg"
    } else {
        $nuevo = ""
        if ($arriba.Count -gt 0) { $nuevo = "# Curso Ed Digital (instalar-codex.ps1)`r`n" + ($arriba -join "`r`n") + "`r`n`r`n" }
        $nuevo += $texto
        if ($abajo.Count -gt 0) {
            if ($nuevo -ne "" -and -not $nuevo.EndsWith("`n")) { $nuevo += "`r`n" }
            $nuevo += "`r`n" + ($abajo -join "`r`n") + "`r`n"
        }
        [IO.File]::WriteAllText($cfg, $nuevo, (New-Object System.Text.UTF8Encoding($false)))
        Ok "Configuracion guardada en $cfg"
        if (-not $lineaModelo) { Ok "Modelo del curso: $ModeloCurso (esfuerzo $EsfuerzoCurso)" }
        if ($arriba -contains "check_for_update_on_startup = false") { Ok "Sin menu de actualizacion al abrir Codex" }
    }
} catch {
    Aviso "No se pudo escribir la configuracion: $($_.Exception.Message)"
    $pendientes += "configuracion"
}

# ---------------------------------------------------------------- 6. Verificacion
Paso "6/6 Verificacion final"
if (-not (Test-Path $carpeta)) {
    New-Item -ItemType Directory -Path $carpeta -Force | Out-Null
    Ok "Carpeta de trabajo creada: $carpeta"
}
if (Test-Path $codexExe) {
    $v = & $codexExe --version 2>$null
    Ok "Codex: $v"
} else {
    Aviso "Codex: no esta instalado"
}
if ($python) {
    $vp = Probar-Python $python
    $vl = Probar-Librerias $python
    if ($vp) { Ok "Python $vp" } else { Aviso "Python no responde: $python" }
    if ($vl) { Ok "Librerias: $vl" } else { Aviso "Faltan las librerias de Office" }
    $pyNueva = Python-En-Ventana-Nueva
    if (-not $pyNueva) {
        Aviso "En una ventana nueva, 'python' podria abrir la Microsoft Store. Avisale a Jorge."
    } elseif (Probar-Librerias $pyNueva) {
        Ok "En una ventana nueva, python sera $pyNueva (con las librerias)"
    } else {
        Aviso "En una ventana nueva, python sera $pyNueva y ahi faltan las librerias"
    }
    # Ajuste 29-sep (python3): lo que encontrara 'python3' en una ventana nueva (el acceso directo de la tienda no cuenta).
    $py3Nueva = Python-En-Ventana-Nueva "python3.exe"
    # Revision adversarial 29-sep: python3 puede ser OTRO Python (por ejemplo, de MSYS2) sin las librerias; se dice aparte.
    if ($py3Nueva -and (Probar-Librerias $py3Nueva)) {
        Ok "En una ventana nueva, python3 tambien sera un Python real con las librerias ($py3Nueva)"
    } elseif ($py3Nueva -and (Probar-Python $py3Nueva)) {
        Aviso "En una ventana nueva, python3 sera $py3Nueva y ahi faltan las librerias. Si un agente falla con python3, que use python."
    } else {
        Aviso "En una ventana nueva, 'python3' no respondera; 'python' si. Si un agente falla con python3, que use python."
    }
} else {
    Aviso "Python: no esta"
}
$estado = Estado-Llave
if ($estado -match "API key") {
    Ok "Llave: $($estado -replace '^.*API key\s*-\s*', '')"
} else {
    Aviso "Codex todavia no tiene la llave del curso"
}

Write-Host ""
if ($pendientes.Count -eq 0) {
    Write-Host "LISTO. Ahora:" -ForegroundColor Green
} else {
    Aviso "Quedo pendiente: $(($pendientes | Select-Object -Unique) -join ', '). Lee los avisos amarillos de arriba y vuelve a correr la misma linea."
    Write-Host "Cuando todo salga en OK:" -ForegroundColor Yellow
}
Write-Host "  1. Cierra TODAS las ventanas de PowerShell y abre una nueva."
Write-Host "  2. Pega:   cd `$HOME\Documents\claude-proyectos"
Write-Host "  3. Pega:   codex"
Write-Host ""
