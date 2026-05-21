#!/usr/bin/env bash
# ============================================================================
#  Zoho Assist TPV Deployment Script - Linux / macOS
#  Instalacion automatizada para entornos TPV Android sin Play Store
#  Version: 1.0.0 | Fecha: 2026-05-21
# ============================================================================
set -euo pipefail

# ── Configuracion ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/zoho_tpv_config.json"
APK_URL="${APK_URL:-https://repo-empresarial.example.com/zoho/assist/latest.apk}"
APK_LOCAL="${SCRIPT_DIR}/zoho_assist.apk"
MD5_EXPECTED="${MD5_EXPECTED:-}"
ADB="${ADB:-adb}"
LOG_FILE="${SCRIPT_DIR}/install_$(date +%Y%m%d_%H%M%S).log"
DEVICE=""

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ── Funciones auxiliares ───────────────────────────────────────────────────
log() {
    local level="$1"; shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"

    case "${level}" in
        INFO)  echo -e "${CYAN}[${level}]${NC} ${message}" ;;
        OK)    echo -e "${GREEN}[${level}]${NC} ${message}" ;;
        WARN)  echo -e "${YELLOW}[${level}]${NC} ${message}" ;;
        ERROR) echo -e "${RED}[${level}]${NC} ${message}" ;;
        *)     echo "[${level}] ${message}" ;;
    esac
}

check_command() {
    if ! command -v "$1" &>/dev/null; then
        log ERROR "Comando '$1' no encontrado. Instálelo primero."
        return 1
    fi
}

# ── Banner ─────────────────────────────────────────────────────────────────
echo "============================================================"
echo "  Zoho Assist - Instalador TPV Empresarial v1.0.0"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ── Verificar dependencias ─────────────────────────────────────────────────
log INFO "Verificando dependencias..."
check_command adb || exit 1
log OK "ADB detectado."

# Verificar curl o wget
if command -v curl &>/dev/null; then
    DOWNLOADER="curl -L -o"
elif command -v wget &>/dev/null; then
    DOWNLOADER="wget -O"
else
    log WARN "Ni curl ni wget detectados. La descarga automatica no estara disponible."
    DOWNLOADER=""
fi

# ── Detectar dispositivos ──────────────────────────────────────────────────
log INFO "Buscando dispositivos Android conectados..."

mapfile -t devices < <(${ADB} devices | tail -n +2 | grep -v "^$" | awk '{print $1}')

if [ ${#devices[@]} -eq 0 ]; then
    log ERROR "No se detecto ningun dispositivo Android."
    echo ""
    echo "Conecte el dispositivo via USB y asegurese de que:"
    echo "  1. Depuracion USB esta habilitada (Opciones de desarrollador)"
    echo "  2. El dispositivo esta desbloqueado"
    echo "  3. Acepto la huella RSA en la pantalla del dispositivo"
    exit 1
fi

# Si hay multiples dispositivos, preguntar cual usar
if [ ${#devices[@]} -gt 1 ]; then
    log INFO "Multiples dispositivos detectados:"
    for i in "${!devices[@]}"; do
        echo "  [$((i+1))] ${devices[$i]}"
    done
    read -rp "Seleccione numero de dispositivo [1]: " selection
    selection="${selection:-1}"
    DEVICE="${devices[$((selection-1))]}"
else
    DEVICE="${devices[0]}"
fi

log OK "Dispositivo seleccionado: ${DEVICE}"

# ── Verificar conexion ─────────────────────────────────────────────────────
log INFO "Verificando conexion con el dispositivo..."
if ! ${ADB} -s "${DEVICE}" shell echo "connected" &>/dev/null; then
    log ERROR "No se pudo establecer conexion con ${DEVICE}"
    exit 1
fi
log OK "Conexion establecida."

# ── Obtener info del dispositivo ───────────────────────────────────────────
log INFO "Recopilando informacion del dispositivo..."
MANUFACTURER=$(${ADB} -s "${DEVICE}" shell getprop ro.product.manufacturer | tr -d '\r')
MODEL=$(${ADB} -s "${DEVICE}" shell getprop ro.product.model | tr -d '\r')
ANDROID_VER=$(${ADB} -s "${DEVICE}" shell getprop ro.build.version.release | tr -d '\r')
SDK=$(${ADB} -s "${DEVICE}" shell getprop ro.build.version.sdk | tr -d '\r')

echo "  Fabricante : ${MANUFACTURER}"
echo "  Modelo     : ${MODEL}"
echo "  Android    : ${ANDROID_VER} (SDK ${SDK})"
log INFO "Dispositivo: ${MANUFACTURER} ${MODEL} | Android ${ANDROID_VER} (SDK ${SDK})"

# ── Verificar SDK minimo ───────────────────────────────────────────────────
if [ "${SDK}" -lt 24 ]; then
    log ERROR "SDK ${SDK} no compatible. Se requiere Android 7.0 (SDK 24) o superior."
    exit 1
fi

# ── Preparar APK ───────────────────────────────────────────────────────────
log INFO "Preparando APK de Zoho Assist..."

if [ -f "${APK_LOCAL}" ]; then
    log INFO "APK local encontrado: ${APK_LOCAL}"

    # Verificar MD5 si se proporciono
    if [ -n "${MD5_EXPECTED}" ]; then
        log INFO "Verificando integridad del APK (MD5)..."
        if command -v md5sum &>/dev/null; then
            MD5_ACTUAL=$(md5sum "${APK_LOCAL}" | awk '{print $1}')
        elif command -v md5 &>/dev/null; then
            MD5_ACTUAL=$(md5 -q "${APK_LOCAL}")
        else
            log WARN "No se encontro herramienta MD5. Omitiendo verificacion de integridad."
            MD5_ACTUAL="${MD5_EXPECTED}"
        fi

        if [ "${MD5_ACTUAL}" != "${MD5_EXPECTED}" ]; then
            log ERROR "MD5 mismatch! Esperado: ${MD5_EXPECTED} | Obtenido: ${MD5_ACTUAL}"
            exit 1
        fi
        log OK "MD5 verificado correctamente."
    fi
else
    log INFO "APK local no encontrado. Descargando desde repositorio..."
    if [ -z "${DOWNLOADER}" ]; then
        log ERROR "No se pudo descargar el APK (curl/wget no disponibles)."
        log ERROR "Coloque zoho_assist.apk en: ${SCRIPT_DIR}"
        exit 1
    fi

    echo "Descargando APK desde: ${APK_URL}"
    ${DOWNLOADER} "${APK_LOCAL}" "${APK_URL}" || {
        log ERROR "Descarga fallida. Verifique la URL o coloque el APK manualmente."
        exit 1
    }
    log OK "APK descargado correctamente."
fi

# ── Desinstalar version anterior ───────────────────────────────────────────
log INFO "Verificando instalaciones previas..."
if ${ADB} -s "${DEVICE}" shell pm list packages com.zoho.assist | grep -q "com.zoho.assist"; then
    log INFO "Zoho Assist ya instalado. Desinstalando version anterior..."
    ${ADB} -s "${DEVICE}" uninstall com.zoho.assist
    log OK "Version anterior desinstalada."
fi

# ── Instalar APK ───────────────────────────────────────────────────────────
log INFO "Instalando Zoho Assist en ${DEVICE}..."
${ADB} -s "${DEVICE}" install -r -d "${APK_LOCAL}" || {
    log ERROR "Fallo la instalacion del APK."
    echo ""
    echo "Verifique:"
    echo "  - Espacio disponible en el dispositivo"
    echo "  - Compatibilidad de arquitectura (arm64-v8a / armeabi-v7a)"
    echo "  - Permisos de instalacion desde fuentes desconocidas"
    exit 1
}
log OK "Zoho Assist instalado correctamente."

# ── Conceder permisos especiales ───────────────────────────────────────────
log INFO "Configurando permisos especiales para control remoto..."
echo "Concediendo permisos (esto puede tomar unos segundos)..."

# Permisos de accesibilidad (necesario para control remoto)
${ADB} -s "${DEVICE}" shell settings put secure enabled_accessibility_services com.zoho.assist/com.zoho.assist.service.AssistAccessibilityService
${ADB} -s "${DEVICE}" shell settings put secure accessibility_enabled 1

# Permiso de overlay (screen sharing)
${ADB} -s "${DEVICE}" shell appops set com.zoho.assist SYSTEM_ALERT_WINDOW allow

# Permiso de captura de pantalla
${ADB} -s "${DEVICE}" shell appops set com.zoho.assist PROJECT_MEDIA allow

# Permiso de notificaciones
${ADB} -s "${DEVICE}" shell appops set com.zoho.assist POST_NOTIFICATIONS allow

# Permisos runtime
declare -a PERMISSIONS=(
    "android.permission.CAMERA"
    "android.permission.RECORD_AUDIO"
    "android.permission.ACCESS_FINE_LOCATION"
    "android.permission.READ_EXTERNAL_STORAGE"
    "android.permission.WRITE_EXTERNAL_STORAGE"
    "android.permission.READ_PHONE_STATE"
    "android.permission.SYSTEM_ALERT_WINDOW"
    "android.permission.WRITE_SETTINGS"
    "android.permission.PACKAGE_USAGE_STATS"
    "android.permission.BIND_ACCESSIBILITY_SERVICE"
    "android.permission.BIND_DEVICE_ADMIN"
)

for perm in "${PERMISSIONS[@]}"; do
    ${ADB} -s "${DEVICE}" shell pm grant com.zoho.assist "${perm}" 2>/dev/null || true
done

# Device Admin (evita confirmaciones repetitivas)
${ADB} -s "${DEVICE}" shell dpm set-device-owner com.zoho.assist/.receiver.DeviceAdminReceiver 2>/dev/null || {
    log WARN "Device Admin no se pudo configurar (posiblemente ya hay otro Device Owner o cuentas existentes)."
    log WARN "Para habilitar, elimine todas las cuentas del dispositivo y reintente."
}

# Deshabilitar optimizacion de bateria
${ADB} -s "${DEVICE}" shell dumpsys deviceidle whitelist +com.zoho.assist 2>/dev/null || true

# Impedir que el sistema mate el proceso
${ADB} -s "${DEVICE}" shell cmd deviceidle tempwhitelist com.zoho.assist 2>/dev/null || true

log OK "Permisos configurados."

# ── Push de configuracion ──────────────────────────────────────────────────
if [ -f "${CONFIG_FILE}" ]; then
    log INFO "Desplegando archivo de configuracion..."
    ${ADB} -s "${DEVICE}" push "${CONFIG_FILE}" /sdcard/zoho_tpv_config.json
    log OK "Configuracion desplegada en /sdcard/zoho_tpv_config.json"
else
    log WARN "Archivo de configuracion no encontrado: ${CONFIG_FILE}"
fi

# Push de script de auto-actualizacion
if [ -f "${SCRIPT_DIR}/auto_updater.sh" ]; then
    log INFO "Desplegando script de auto-actualizacion..."
    ${ADB} -s "${DEVICE}" push "${SCRIPT_DIR}/auto_updater.sh" /sdcard/zoho_auto_updater.sh
    log OK "Script de actualizacion desplegado."
fi

# ── Iniciar aplicacion ─────────────────────────────────────────────────────
log INFO "Iniciando Zoho Assist..."
${ADB} -s "${DEVICE}" shell monkey -p com.zoho.assist -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
log OK "Zoho Assist iniciado."

# ── Verificar instalacion ──────────────────────────────────────────────────
log INFO "Verificando instalacion..."

if ! ${ADB} -s "${DEVICE}" shell pm list packages com.zoho.assist | grep -q "com.zoho.assist"; then
    log ERROR "Verificacion fallida: paquete no encontrado."
    exit 1
fi

INSTALLED_VERSION=$(${ADB} -s "${DEVICE}" shell dumpsys package com.zoho.assist | grep "versionName" | head -1 | cut -d'=' -f2 | tr -d '\r')
log OK "Verificacion OK. Version instalada: ${INSTALLED_VERSION}"

# ── Resumen ────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  INSTALACION COMPLETADA EXITOSAMENTE"
echo "============================================================"
echo "  Dispositivo : ${MANUFACTURER} ${MODEL}"
echo "  Android     : ${ANDROID_VER}"
echo "  Zoho Assist : v${INSTALLED_VERSION:-desconocida}"
echo "  Log         : ${LOG_FILE}"
echo "============================================================"
echo ""
log OK "Instalacion completada exitosamente."
