# instalar.ps1 - Deja lista una laptop Windows para Claude Code (curso Ed Digital TEC)
#
# Uso (pegar en PowerShell, NO en CMD):
#   irm https://bandeja-eddigital.jorgeeduai.app/instalar.ps1 | iex
#
# Hace, en orden: Git for Windows -> instalador oficial de Claude Code -> PATH -> carpeta de trabajo -> llave del curso (opcional) -> Antigravity CLI (respaldo, opcional) -> verificacion.
# Se puede correr varias veces sin romper nada. Sin acentos a proposito: PowerShell 5.1 los maltrata al leer por irm.

$ErrorActionPreference = "Continue"

function Paso($t)  { Write-Host ""; Write-Host "==> $t" -ForegroundColor Cyan }
function Ok($t)    { Write-Host "    OK  $t" -ForegroundColor Green }
function Aviso($t) { Write-Host "    !!  $t" -ForegroundColor Yellow }

Write-Host ""
Write-Host "Instalador del curso - Claude Code en Windows" -ForegroundColor Cyan
Write-Host "No cierres esta ventana hasta ver el mensaje final."

$claudeBin = "$env:USERPROFILE\.local\bin"
$carpeta   = "$HOME\Documents\claude-proyectos"

# ---------------------------------------------------------------- 1. Git
Paso "1/7 Revisando Git for Windows"
if (Get-Command git -ErrorAction SilentlyContinue) {
    Ok "Git ya esta instalado"
} else {
    Aviso "Git no esta. Instalando con winget (puede pedir permiso de administrador: di que si)..."
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Aviso "winget no esta disponible en esta maquina."
        Aviso "Instala Git a mano desde https://git-scm.com/download/win y vuelve a correr esta misma linea."
        return
    }
    winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements
    $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Ok "Git instalado"
    } else {
        Aviso "Git se instalo pero esta ventana todavia no lo ve."
        Aviso "Cierra PowerShell, abre uno nuevo y vuelve a correr la misma linea. Continuara donde se quedo."
        return
    }
}

# ---------------------------------------------------------------- 2. Claude Code
Paso "2/7 Instalando Claude Code (instalador oficial de Anthropic)"
if (Test-Path "$claudeBin\claude.exe") { Ok "Ya estaba instalado; se actualiza" }
try {
    irm https://claude.ai/install.ps1 | iex
} catch {
    Aviso "El instalador oficial marco un error: $($_.Exception.Message)"
}

# ---------------------------------------------------------------- 3. PATH
Paso "3/7 Revisando que Windows encuentre el comando 'claude'"
$userPath = [Environment]::GetEnvironmentVariable("Path","User")
if ($userPath -notlike "*$claudeBin*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$claudeBin", "User")
    Ok "Carpeta agregada al PATH del usuario"
} else {
    Ok "El PATH ya estaba bien"
}
$env:Path = "$env:Path;$claudeBin"

# ---------------------------------------------------------------- 4. Carpeta
Paso "4/7 Creando tu carpeta de trabajo"
if (-not (Test-Path $carpeta)) {
    New-Item -ItemType Directory -Path $carpeta | Out-Null
    Ok "Creada: $carpeta"
} else {
    Ok "Ya existia: $carpeta"
}

# ---------------------------------------------------------------- 5. Llave del curso (opcional)
Paso "5/7 Llave del curso"
$actual = [Environment]::GetEnvironmentVariable("ANTHROPIC_API_KEY","User")
if ($actual) {
    Ok "Ya hay una llave guardada (termina en ...$($actual.Substring([Math]::Max(0,$actual.Length-4))))"
    $cambiar = Read-Host "    Escribe S para reemplazarla, o Enter para dejarla"
    if ($cambiar -ne "S" -and $cambiar -ne "s") { $actual = "conservar" }
}
if ($actual -ne "conservar") {
    Write-Host "    Si Jorge te mando una llave (empieza con sk-ant-), pegala aqui."
    Write-Host "    Si no tienes llave, solo presiona Enter: Claude Code te pedira iniciar sesion con tu cuenta."
    $llave = Read-Host "    Llave"
    $llave = $llave.Trim()
    if ($llave -eq "") {
        Ok "Sin llave; se usara inicio de sesion"
    } elseif ($llave -notlike "sk-ant-*") {
        Aviso "Eso no parece una llave (deberia empezar con sk-ant-). No se guardo nada; vuelve a correr la linea para intentarlo de nuevo."
    } else {
        [Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", $llave, "User")
        [Environment]::SetEnvironmentVariable("ANTHROPIC_MODEL", "claude-sonnet-5-5", "User")
        Ok "Llave guardada para tu usuario. Modelo del curso: claude-sonnet-5-5"
        Write-Host "    La primera vez que abras claude te preguntara si usas esta llave: di que si."
    }
}

# ---------------------------------------------------------------- 6. Antigravity CLI (respaldo, opcional)
# Antigravity CLI de Google: segundo agente que trabaja en la terminal, como Claude Code. Se abre con 'agy'.
# Es respaldo: si algo falla aqui solo se avisa y el script sigue. Nunca detiene lo demas.
# Instalador oficial: https://antigravity.google/cli/install.ps1 (deja agy.exe en %LOCALAPPDATA%\agy\bin).
# Se corre en un scriptblock hijo para que su StrictMode y su ErrorActionPreference no se queden en este script.
Paso "6/7 Antigravity CLI (respaldo)"
$agyBin   = "$env:LOCALAPPDATA\agy\bin"
$agExe    = "$agyBin\agy.exe"
$agListo  = $false
try {
    if (Test-Path $agExe) {
        Ok "Antigravity CLI ya estaba instalado"
        $agListo = $true
    } else {
        Write-Host "    Instalando Antigravity CLI de Google como respaldo (agente en la terminal)."
        $s = Invoke-RestMethod -Uri "https://antigravity.google/cli/install.ps1" -UseBasicParsing -TimeoutSec 60
        if ($s -is [byte[]]) { $s = [Text.Encoding]::UTF8.GetString($s) }
        & ([scriptblock]::Create([string]$s))
        if (Test-Path $agExe) {
            Ok "Antigravity CLI instalado"
            $agListo = $true
        } else {
            Aviso "Antigravity CLI no quedo instalado. No pasa nada: es solo el respaldo."
            Aviso "Si lo quieres despues, las instrucciones estan en https://antigravity.google/docs/cli/install/"
        }
    }
    if ($agListo) {
        $userPath = [Environment]::GetEnvironmentVariable("Path","User")
        if ($userPath -notlike "*$agyBin*") {
            [Environment]::SetEnvironmentVariable("Path", "$userPath;$agyBin", "User")
            Ok "Carpeta de agy agregada al PATH del usuario"
        }
        if ($env:Path -notlike "*$agyBin*") { $env:Path = "$env:Path;$agyBin" }
    }
} catch {
    Aviso "Antigravity CLI no se pudo instalar: $($_.Exception.Message)"
    Aviso "No pasa nada: es solo el respaldo. Claude Code sigue su camino."
}

# ---------------------------------------------------------------- 7. Verificacion
Paso "7/7 Verificacion final"
if (Test-Path "$claudeBin\claude.exe") {
    $v = & "$claudeBin\claude.exe" --version 2>$null
    Ok "Claude Code instalado: $v"
    Write-Host ""
    Write-Host "LISTO. Ahora:" -ForegroundColor Green
    Write-Host "  1. Cierra TODAS las ventanas de PowerShell y abre una nueva."
    Write-Host "  2. Pega:   cd `$HOME\Documents\claude-proyectos"
    Write-Host "  3. Pega:   claude"
    Write-Host "     Con llave: te pregunta si la usas, di que si. Sin llave: abre el navegador para iniciar sesion."
    if ($agListo) {
        Write-Host ""
        Write-Host "Antigravity CLI quedo instalado. Se abre escribiendo agy dentro de tu carpeta; la primera vez pide tu cuenta de Google en el navegador."
    }
} else {
    Aviso "No encontre claude.exe en $claudeBin."
    Aviso "Avisale a Jorge. La guia tiene el plan B paso a paso (seccion 'Si algo falla')."
}
Write-Host ""
