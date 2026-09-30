#!/usr/bin/env bash
# instalar-codex.sh - Deja lista una Mac para Codex (curso Ed Digital TEC, sesion 3)
#
# Uso (pegar en la app Terminal):
#   curl -fsSL https://bandeja-eddigital.jorgeeduai.app/instalar-codex.sh | bash
# Espejo, si la red bloquea la bandeja:
#   curl -fsSL https://raw.githubusercontent.com/jorgeeduai/instalador/main/instalar-codex.sh | bash
# Prueba local antes de publicar:
#   bash instalar-codex.sh
#
# Hace, en orden: Python -> librerias de Office -> Codex (instalador oficial de OpenAI) -> llave de OpenAI
# -> configuracion del curso -> verificacion.
# Se puede correr varias veces sin romper nada. Si un paso falla, solo avisa y los demas siguen.
# Compatible con el bash 3.2 que trae macOS. Todo va dentro de main() y se llama en la ultima linea: si la
# descarga se corta a la mitad no corre nada, y bash lee el script completo antes de preguntar la llave
# (con curl | bash la entrada es el propio script; las preguntas se leen de la terminal, /dev/tty).
#
# Solo para pruebas: INSTALADOR_SIN_PROBAR_LLAVE=1 salta la consulta a OpenAI que valida la llave.

MODELO_CURSO="gpt-6-sol"      # modelo de Codex por API (cambialo aqui)
ESFUERZO_CURSO="medium"       # esfuerzo de razonamiento sugerido por OpenAI para Sol
LIBRERIAS="openpyxl python-docx python-pptx"
URL_CODEX="https://chatgpt.com/codex/install.sh"

ORIGEN="${BASH_SOURCE[0]:-}"
CARPETA="$HOME/Documents/claude-proyectos"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
BIN_DIR="${CODEX_INSTALL_DIR:-$HOME/.local/bin}"
CODEX_BIN="$BIN_DIR/codex"
PENDIENTES=""
PYTHON=""
PY_VERSION=""

if [ -t 1 ]; then
    C_AZUL=$'\033[36m'; C_VERDE=$'\033[32m'; C_AMARILLO=$'\033[33m'; C_FIN=$'\033[0m'
else
    C_AZUL=""; C_VERDE=""; C_AMARILLO=""; C_FIN=""
fi

paso()  { printf '\n%s==> %s%s\n' "$C_AZUL" "$1" "$C_FIN"; }
ok()    { printf '%s    OK  %s%s\n' "$C_VERDE" "$1" "$C_FIN"; }
aviso() { printf '%s    !!  %s%s\n' "$C_AMARILLO" "$1" "$C_FIN"; }
pendiente() { case " $PENDIENTES " in *" $1 "*) ;; *) PENDIENTES="$PENDIENTES $1" ;; esac; }

# leer VARIABLE "pregunta" [secreto]
# Lee de la terminal. Si el script se corre desde un archivo con la entrada redirigida (pruebas), lee de ahi.
leer() {
    local __var="$1" __preg="$2" __secreto="${3:-}" __r=""
    printf '%s' "$__preg"
    if [ -t 0 ]; then
        if [ -n "$__secreto" ]; then IFS= read -rs __r; printf '\n'; else IFS= read -r __r; fi
    elif [ -n "$ORIGEN" ] && [ -f "$ORIGEN" ]; then
        IFS= read -r __r || true
        printf '\n'
    elif ( : </dev/tty ) 2>/dev/null; then
        if [ -n "$__secreto" ]; then IFS= read -rs __r </dev/tty; printf '\n'; else IFS= read -r __r </dev/tty; fi
    else
        printf '\n'
    fi
    printf -v "$__var" '%s' "$__r"
}

# Imprime la version si ese python es 3.9 o mas nuevo y funciona de verdad.
probar_python() {
    "$1" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3]) if sys.version_info >= (3, 9) else sys.exit(3)' 2>/dev/null
}

# El /usr/bin/python3 de macOS es un intermediario: sin las herramientas de linea de comandos de Apple no hay
# Python detras y correrlo abre la ventana de instalacion. Por eso primero se revisa xcode-select -p.
buscar_python() {
    local c v
    c="$(command -v python3 2>/dev/null)"
    if [ "$c" = "/usr/bin/python3" ] && ! xcode-select -p >/dev/null 2>&1; then c=""; fi
    if [ -n "$c" ]; then
        v="$(probar_python "$c")"
        if [ -n "$v" ]; then PYTHON="$c"; PY_VERSION="$v"; return 0; fi
    fi
    if [ "$c" != "/usr/bin/python3" ] && [ -x /usr/bin/python3 ] && xcode-select -p >/dev/null 2>&1; then
        v="$(probar_python /usr/bin/python3)"
        if [ -n "$v" ]; then PYTHON="/usr/bin/python3"; PY_VERSION="$v"; return 0; fi
    fi
    return 1
}

# probar_librerias PYTHON: imprime las versiones si las tres librerias se pueden importar.
probar_librerias() {
    "$1" -c 'import openpyxl, docx, pptx; from importlib.metadata import version as v; print("openpyxl " + v("openpyxl") + ", python-docx " + v("python-docx") + ", python-pptx " + v("python-pptx"))' 2>/dev/null
}

# instalar_librerias PYTHON: deja la salida de pip en SALIDA_PIP.
instalar_librerias() {
    if ! "$1" -m pip --version >/dev/null 2>&1; then
        echo "    Este Python no traia pip; lo agrego..."
        "$1" -m ensurepip --user >/dev/null 2>&1 || true
    fi
    # $LIBRERIAS va sin comillas a proposito: son tres nombres separados por espacios.
    SALIDA_PIP="$("$1" -m pip install --user --upgrade --disable-pip-version-check --no-warn-script-location -q $LIBRERIAS 2>&1)"
    case "$SALIDA_PIP" in
        *externally-managed-environment*)
            # Python de Homebrew (PEP 668): pip se niega a instalar fuera de un entorno virtual. Con --user los
            # paquetes van a ~/Library/Python/X.Y de la persona y no tocan los de Homebrew; por eso se permite
            # con --break-system-packages.
            echo "    Este Python es de Homebrew; repito la instalacion en la carpeta del usuario..."
            SALIDA_PIP="$("$1" -m pip install --user --break-system-packages --upgrade --disable-pip-version-check --no-warn-script-location -q $LIBRERIAS 2>&1)"
            ;;
    esac
}

# El python3 que vera una Terminal nueva: se le pregunta al shell de login de la persona (lee .zprofile o
# .bash_profile, no .zshrc). Sirve cuando el instalador corre con un PATH distinto al de una Terminal nueva.
python_terminal_nueva() {
    local sh_login p
    case "${SHELL:-}" in */zsh|*/bash) sh_login="$SHELL" ;; *) sh_login="/bin/zsh" ;; esac
    p="$("$sh_login" -l -c 'command -v python3' </dev/null 2>/dev/null | tail -n 1)"
    case "$p" in /*) ;; *) return 1 ;; esac
    if [ "$p" = "/usr/bin/python3" ] && ! xcode-select -p >/dev/null 2>&1; then return 1; fi
    if [ -z "$(probar_python "$p")" ]; then return 1; fi
    printf '%s\n' "$p"
}

# Pregunta a OpenAI por el modelo del curso con esa llave. 200 = sirve, 401 = rechazada, 404 = modelo no visible,
# 000 = sin respuesta. La llave va por la entrada de curl (-K -), no en la linea de comandos.
probar_llave() {
    printf 'header = "Authorization: Bearer %s"\n' "$1" |
        curl -s -o /dev/null -w '%{http_code}' --max-time 20 -K - "https://api.openai.com/v1/models/$MODELO_CURSO" 2>/dev/null
}

estado_llave() {
    if [ -x "$CODEX_BIN" ]; then "$CODEX_BIN" login status 2>&1; fi
}

main() {
    echo ""
    printf '%sInstalador del curso - Codex en Mac%s\n' "$C_AZUL" "$C_FIN"
    echo "No cierres esta ventana hasta ver el mensaje final. Puede tardar varios minutos segun tu internet."

    # ------------------------------------------------------------ 1. Python
    paso "1/6 Python (el agente lo usa para leer y escribir Excel, Word y PowerPoint)"
    if buscar_python; then
        ok "Python $PY_VERSION: $PYTHON"
    elif ! xcode-select -p >/dev/null 2>&1; then
        aviso "Esta Mac no tiene las herramientas de linea de comandos de Apple, que traen Python."
        xcode-select --install >/dev/null 2>&1 || true
        aviso "Se abrio una ventana para instalarlas: elige Instalar y espera a que termine (puede tardar varios minutos)."
        aviso "Despues vuelve a pegar la misma linea. Mientras, sigo con los demas pasos."
        pendiente "Python"
    else
        aviso "No encontre un python3 que funcione. Avisale a Jorge."
        pendiente "Python"
    fi

    # ------------------------------------------------------------ 2. Librerias para Office
    paso "2/6 Librerias de Python para Excel, Word y PowerPoint"
    if [ -z "$PYTHON" ]; then
        aviso "Sin Python no se pueden instalar. Se instalan solas cuando vuelvas a correr la linea con Python listo."
        pendiente "librerias"
    else
        echo "    Instalando $LIBRERIAS (1 o 2 minutos)..."
        instalar_librerias "$PYTHON"
        salida="$SALIDA_PIP"
        v="$(probar_librerias "$PYTHON")"
        if [ -n "$v" ]; then
            ok "Listas: $v"
            PY_NUEVA="$(python_terminal_nueva)"
            if [ -n "$PY_NUEVA" ] && [ "$PY_NUEVA" != "$PYTHON" ] && [ -z "$(probar_librerias "$PY_NUEVA")" ]; then
                echo "    Una Terminal nueva usara otro python3 ($PY_NUEVA); le instalo tambien las librerias..."
                instalar_librerias "$PY_NUEVA"
                v2="$(probar_librerias "$PY_NUEVA")"
                if [ -n "$v2" ]; then ok "Tambien listas en $PY_NUEVA"; else aviso "No se pudieron instalar en $PY_NUEVA"; pendiente "librerias"; fi
            fi
        else
            case "$salida" in
                *SSL*|*Proxy*|*proxy*|*"Max retries"*|*NewConnectionError*|*"timed out"*)
                    aviso "La red no dejo descargar las librerias (pypi.org). Prueba con otra red, por ejemplo el hotspot del celular, y vuelve a correr la linea."
                    ;;
                *)
                    aviso "pip no pudo instalar las librerias. Ultimas lineas de pip:"
                    printf '%s\n' "$salida" | tail -n 6 | sed 's/^/        /'
                    ;;
            esac
            pendiente "librerias"
        fi
    fi

    # ------------------------------------------------------------ 3. Codex
    # Instalador oficial: https://chatgpt.com/codex/install.sh (redirige a releases.openai.com). Deja el programa en
    # ~/.codex/packages/standalone y el comando en ~/.local/bin/codex; si esa carpeta no esta en el PATH, la agrega a
    # ~/.zprofile (zsh) o ~/.bash_profile (bash). No necesita Node ni Homebrew. CODEX_NON_INTERACTIVE=1 evita que al
    # final pregunte si abrir Codex.
    paso "3/6 Codex (instalador oficial de OpenAI)"
    if [ -x "$CODEX_BIN" ]; then ok "Codex ya estaba instalado; se revisa si hay version nueva"; fi
    echo "    Descarga de unos 140 MB sin barra de avance: si la pantalla se queda quieta un par de minutos, es normal."
    tmp="$(mktemp "${TMPDIR:-/tmp}/instalar-codex.XXXXXX")"
    if curl -fsSL --max-time 120 "$URL_CODEX" -o "$tmp"; then
        CODEX_NON_INTERACTIVE=1 sh "$tmp" || aviso "El instalador oficial termino con error."
    else
        aviso "No se pudo descargar el instalador de Codex. Si la red o el antivirus lo bloquean, prueba con otra red."
    fi
    rm -f "$tmp"
    case ":$PATH:" in *":$BIN_DIR:"*) ;; *) PATH="$BIN_DIR:$PATH"; export PATH ;; esac
    if [ -x "$CODEX_BIN" ]; then
        ok "Codex instalado: $("$CODEX_BIN" --version 2>/dev/null)"
    else
        aviso "No encontre el comando codex en $BIN_DIR."
        pendiente "Codex"
    fi

    # ------------------------------------------------------------ 4. Llave de OpenAI
    # Codex guarda la llave con 'codex login --with-api-key' (la lee de la entrada) en ~/.codex/auth.json, que
    # sobrevive a cerrar la Terminal. Codex no toma la variable OPENAI_API_KEY por si sola, por eso no se usa.
    paso "4/6 Llave de OpenAI del curso"
    mkdir -p "$CODEX_DIR"
    if [ ! -x "$CODEX_BIN" ]; then
        aviso "Primero tiene que quedar Codex (paso 3). La llave se pide cuando vuelvas a correr la linea."
        pendiente "llave"
    else
        pedir="si"
        estado="$(estado_llave)"
        case "$estado" in
            *"API key"*)
                ok "Ya hay una llave guardada: ${estado##*API key - }"
                leer r "    Escribe S para reemplazarla, o Enter para dejarla: "
                if [ "$r" != "S" ] && [ "$r" != "s" ]; then pedir="no"; fi
                ;;
            *ChatGPT*)
                aviso "Codex tiene abierta una sesion de ChatGPT. En el curso se usa la llave de OpenAI que recibiste de Jorge."
                leer r "    Escribe S para cambiarla por tu llave, o Enter para dejarla: "
                if [ "$r" != "S" ] && [ "$r" != "s" ]; then pedir="no"; fi
                ;;
        esac
        if [ "$pedir" = "si" ]; then
            echo "    Pega la llave de OpenAI que recibiste de Jorge (empieza con sk-proj- o sk-) y presiona Enter."
            echo "    Por seguridad no se ve lo que pegas."
            leer llave "    Llave: " secreto
            llave="$(printf '%s' "$llave" | tr -d "[:space:]\"'")"
            case "$llave" in
                "")
                    aviso "No pegaste nada. Vuelve a correr la linea cuando tengas tu llave a la mano."
                    pendiente "llave"
                    ;;
                sk-ant-*)
                    aviso "Esa es la llave de Claude Code (empieza con sk-ant-). Codex usa la llave de OpenAI (empieza con sk-proj- o sk-)."
                    aviso "No se guardo nada. Vuelve a correr la linea y pega la de OpenAI."
                    pendiente "llave"
                    ;;
                sk-*)
                    fin="${llave#"${llave%????}"}"
                    if [ "${INSTALADOR_SIN_PROBAR_LLAVE:-}" = "1" ]; then
                        codigo="omitida"
                        echo "    Recibi la llave que termina en ...$fin (prueba con OpenAI omitida)."
                    else
                        echo "    Recibi la llave que termina en ...$fin. La pruebo con OpenAI..."
                        codigo="$(probar_llave "$llave")"
                    fi
                    if [ "$codigo" = "401" ]; then
                        aviso "OpenAI rechazo esa llave (codigo 401): esta incompleta, tiene un caracter de mas o ya se apago."
                        aviso "No se guardo nada. Copiala otra vez completa del mensaje de Jorge y vuelve a correr la linea."
                        pendiente "llave"
                    else
                        case "$codigo" in
                            200) ok "OpenAI reconoce la llave y el modelo del curso ($MODELO_CURSO) esta disponible" ;;
                            404) aviso "La llave es valida pero el modelo $MODELO_CURSO no aparece para esa cuenta. Se guarda igual; avisale a Jorge." ;;
                            omitida) ;;
                            000|"") aviso "No pude comprobar la llave con OpenAI (la red no respondio). Se guarda igual." ;;
                            *) aviso "OpenAI respondio con el codigo $codigo al probar la llave. Se guarda igual; si Codex falla, avisale a Jorge." ;;
                        esac
                        if printf '%s' "$llave" | "$CODEX_BIN" login --with-api-key >/dev/null 2>&1; then
                            ok "Llave guardada para Codex (termina en ...$fin)"
                        else
                            aviso "Codex no pudo guardar la llave. Avisale a Jorge."
                            pendiente "llave"
                        fi
                    fi
                    ;;
                *)
                    aviso "Eso no parece una llave de OpenAI (deberia empezar con sk-). No se guardo nada; vuelve a correr la linea."
                    pendiente "llave"
                    ;;
            esac
            llave=""
        fi
    fi

    # ------------------------------------------------------------ 5. Configuracion del curso
    # ~/.codex/config.toml: modelo y esfuerzo del curso, y sin menu de actualizacion al abrir. Si el archivo ya existe
    # no se pisa: solo se agregan al principio las claves que falten. Un modelo ya elegido se respeta.
    paso "5/6 Configuracion del curso para Codex"
    mkdir -p "$CODEX_DIR"
    cfg="$CODEX_DIR/config.toml"
    cabeza=""
    if [ -f "$cfg" ]; then cabeza="$(awk '/^[ \t]*\[/ { exit } { print }' "$cfg")"; fi
    linea_modelo="$(printf '%s\n' "$cabeza" | grep -E '^[[:space:]]*model[[:space:]]*=' | head -n 1)"
    falta_esfuerzo="si"
    if printf '%s\n' "$cabeza" | grep -qE '^[[:space:]]*model_reasoning_effort[[:space:]]*='; then falta_esfuerzo="no"; fi
    # Ajuste 29-sep: sin el menu "Update available" al abrir Codex. Codex sale casi a diario y ese menu frena la clase.
    # Clave oficial check_for_update_on_startup (learn.chatgpt.com/docs/config-file/config-reference). Probada en vivo en
    # el Studio con Codex 0.158.0 frente a 0.159.0 publicada: sin la clave sale el menu; con false, no. Para actualizar
    # Codex se vuelve a correr la linea del curso (el paso 3 baja la version nueva). Si ya hay un valor, se respeta.
    # Revision adversarial 29-sep: se busca en TODO el archivo y tambien con la clave entre comillas. Con la cabeza sola,
    # un arreglo de varias lineas con una linea que empieza con [ la cortaba antes de tiempo, y la clave entre comillas no
    # se reconocia: en los dos casos quedaba repetida y Codex ya no podia leer el archivo (comprobado con tomllib). Si la
    # clave aparece en cualquier parte no se agrega: que falte solo deja el menu.
    falta_revision="si"
    if [ -f "$cfg" ] && grep -qE "^[[:space:]]*[\"']?check_for_update_on_startup[\"']?[[:space:]]*=" "$cfg"; then falta_revision="no"; fi
    if [ -n "$linea_modelo" ]; then
        case "$linea_modelo" in
            *"\"$MODELO_CURSO\""*) ok "config.toml ya tenia el modelo del curso" ;;
            *) aviso "Tu config.toml ya elige otro modelo y se respeta: $linea_modelo" ;;
        esac
    fi
    if [ -n "$linea_modelo" ] && [ "$falta_esfuerzo" = "no" ] && [ "$falta_revision" = "no" ]; then
        ok "config.toml ya estaba listo: $cfg"
    else
        tmpcfg="$(mktemp "${TMPDIR:-/tmp}/codex-config.XXXXXX")"
        {
            echo "# Curso Ed Digital (instalar-codex.sh)"
            if [ -z "$linea_modelo" ]; then echo "model = \"$MODELO_CURSO\""; fi
            if [ "$falta_esfuerzo" = "si" ]; then echo "model_reasoning_effort = \"$ESFUERZO_CURSO\""; fi
            if [ "$falta_revision" = "si" ]; then
                echo "# Sin el menu 'Update available' al abrir Codex. Para actualizar, vuelve a correr la linea del curso."
                echo "check_for_update_on_startup = false"
            fi
            echo ""
            if [ -f "$cfg" ]; then cat "$cfg"; fi
        } > "$tmpcfg"
        if mv "$tmpcfg" "$cfg"; then
            ok "Configuracion guardada en $cfg"
            if [ -z "$linea_modelo" ]; then ok "Modelo del curso: $MODELO_CURSO (esfuerzo $ESFUERZO_CURSO)"; fi
            if [ "$falta_revision" = "si" ]; then ok "Sin menu de actualizacion al abrir Codex"; fi
        else
            rm -f "$tmpcfg"
            aviso "No se pudo escribir $cfg"
            pendiente "configuracion"
        fi
    fi

    # ------------------------------------------------------------ 6. Verificacion
    paso "6/6 Verificacion final"
    if [ ! -d "$CARPETA" ]; then
        mkdir -p "$CARPETA" && ok "Carpeta de trabajo creada: $CARPETA"
    fi
    if [ -x "$CODEX_BIN" ]; then ok "Codex: $("$CODEX_BIN" --version 2>/dev/null)"; else aviso "Codex: no esta instalado"; fi
    if [ -n "$PYTHON" ]; then
        ok "Python $(probar_python "$PYTHON"): $PYTHON"
        v="$(probar_librerias "$PYTHON")"
        if [ -n "$v" ]; then ok "Librerias: $v"; else aviso "Faltan las librerias de Office"; fi
        PY_NUEVA="$(python_terminal_nueva)"
        if [ -n "$PY_NUEVA" ]; then
            if [ -n "$(probar_librerias "$PY_NUEVA")" ]; then
                ok "En una Terminal nueva, python3 sera $PY_NUEVA (con las librerias)"
            else
                aviso "En una Terminal nueva, python3 sera $PY_NUEVA y ahi faltan las librerias"
            fi
        fi
    else
        aviso "Python: no esta"
    fi
    estado="$(estado_llave)"
    case "$estado" in
        *"API key"*) ok "Llave: ${estado##*API key - }" ;;
        *) aviso "Codex todavia no tiene la llave del curso" ;;
    esac

    echo ""
    if [ -z "$PENDIENTES" ]; then
        printf '%sLISTO. Ahora:%s\n' "$C_VERDE" "$C_FIN"
    else
        aviso "Quedo pendiente:$PENDIENTES. Lee los avisos amarillos de arriba y vuelve a correr la misma linea."
        printf '%sCuando todo salga en OK:%s\n' "$C_AMARILLO" "$C_FIN"
    fi
    echo "  1. Cierra la Terminal por completo (Cmd + Q) y abrela de nuevo."
    echo "  2. Pega:   cd ~/Documents/claude-proyectos"
    echo "  3. Pega:   codex"
    echo ""
}

main "$@"
