# Instalador de los cursos de JorgeEduAI

`instalar.ps1` deja lista una laptop Windows para trabajar con un agente de IA en la terminal. En orden:

1. Revisa Git for Windows y lo instala con winget si falta.
2. Corre el instalador oficial de Claude Code (Anthropic).
3. Agrega la carpeta de Claude Code al PATH del usuario.
4. Crea la carpeta de trabajo `Documents\claude-proyectos`.
5. Pide la llave del curso (opcional).
6. Instala Antigravity CLI de Google (comando `agy`) como respaldo (opcional).
7. Verifica que `claude --version` responda.

Se puede correr varias veces sin romper nada.

## Cómo se usa

Abre PowerShell (no CMD) y pega la línea principal:

```
irm https://bandeja-eddigital.jorgeeduai.app/instalar.ps1 | iex
```

Si esa liga no abre en tu red, usa la línea espejo, que baja este mismo archivo desde GitHub:

```
irm https://raw.githubusercontent.com/jorgeeduai/instalador/main/instalar.ps1 | iex
```

Las dos descargan exactamente el mismo archivo.

## Sobre la llave

La llave del curso se pide en pantalla durante el paso 5 y se guarda solo en tu usuario de Windows. Ninguna llave viaja dentro del script ni vive en este repositorio.
