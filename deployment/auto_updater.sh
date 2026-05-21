#!/usr/bin/env bash
# ============================================================================
#  Zoho Assist - Auto-Updater para TPV Android
#  Verifica version, descarga actualizaciones desde repo privado,
#  aplica rollback si falla, y mantiene registros de auditoria.
#  Version: 1.0.0 | Fecha: 2026-05-21
#
#  Ejecucion:
#    ./auto_updater.sh                          # Verificar + actualizar si hay nueva
#    ./auto_updater.sh --check-only             # Solo verificar, no instalar
#    ./auto_updater.sh --force                  # Forzar reinstalacion
#    ./auto_updater.sh --rollback               # Volver a version anterior
# ============================================================================
set -euo pipefail

# ── Configuracion ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/zoho_tpv_config.json"
ADB="${ADB:-adb}"
LOG_FILE="${SCRIPT_DIR}/updater_$(date +%Y%m%d).log"

# Valores por defecto (sobrescritos por JSON si existe)
REPO_BASE_URL="https://repo-empresarial.example.com/zoho"
REPO_CHANNEL="stable"
CHECK_INTERVAL_HOURS=6
ALLOW_DOWNGRADE=false
VERIFY_CHECKSUM=true
ROLLBACK_ENABLED=true
ROLLBACK_KEEP_VERSIONS=2
FORCE_UPDATE=false
CHECK_ONLY=false
DO_ROLLBACK=false

# ── Funciones ──────────────────────────────────────────────────────────────
log() {
    local level="$1"; shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

load_config() {
    if [ -f "${CONFIG_FILE}" ]; then
        log INFO "Cargando configuracion desde ${CONFIG_FILE}"

        if command -v jq &>/dev/null; then
            REPO_BASE_URL=$(jq -r '.update_repository.base_url // empty' "${CONFIG_FILE}" 2>/dev/null || echo "${REPO_BASE_URL}")
            REPO_CHANNEL=$(jq -r '.update_repository.channel // empty' "${CONFIG_FILE}" 2>/dev/null || echo "${REPO_CHANNEL}")
            CHECK_INTERVAL_HOURS=$(jq -r '.update_repository.check_interval_hours // empty' "${CONFIG_FILE}" 2>/dev/null || echo "${CHECK_INTERVAL_HOURS}")
            ALLOW_DOWNGRADE=$(jq -r '.update_repository.allow_downgrade // false' "${CONFIG_FILE}" 2>/dev/null)
            VERIFY_CHECKSUM=$(jq -r '.update_repository.verify_checksum // true' "${CONFIG_FILE}" 2>/dev/null)
            ROLLBACK_ENABLED=$(jq -r '.update_repository.rollback_enabled // true' "${CONFIG_FILE}" 2>/dev/null)
            ROLLBACK_KEEP_VERSIONS=$(jq -r '.update_repository.rollback_keep_versions // 2' "${CONFIG_FILE}" 2>/dev/null)
        else
            log WARN "jq no instalado. Usando valores por defecto."
        fi
    else
        log WARN "Archivo de configuracion no encontrado: ${CONFIG_FILE}"
    fi
}

detect_device() {
    mapfile -t devices < <(${ADB} devices | tail -n +2 | grep -v "^$" | awk '{print $1}')

    if [ ${#devices[@]} -eq 0 ]; then
        log ERROR "No se detecto ningun dispositivo Android."
        exit 1
    fi

    # Si hay multiples, usar el primero
    DEVICE="${devices[0]}"
    log INFO "Dispositivo detectado: ${DEVICE}"
}

get_installed_version() {
    local device="$1"
    local pkg="com.zoho.assist"

    if ${ADB} -s "${device}" shell pm list packages "${pkg}" 2>/dev/null | grep -q "${pkg}"; then
        local ver
        ver=$(${ADB} -s "${device}" shell dumpsys package "${pkg}" 2>/dev/null | grep "versionName" | head -1 | cut -d'=' -f2 | tr -d '\r')
        echo "${ver}"
    else
        echo "NOT_INSTALLED"
    fi
}

get_installed_version_code() {
    local device="$1"
    local pkg="com.zoho.assist"

    if ${ADB} -s "${device}" shell pm list packages "${pkg}" 2>/dev/null | grep -q "${pkg}"; then
        local code
        code=$(${ADB} -s "${device}" shell dumpsys package "${pkg}" 2>/dev/null | grep "versionCode" | head -1 | grep -oP '\d+' | head -1 | tr -d '\r')
        echo "${code}"
    else
        echo "0"
    fi
}

get_latest_version_info() {
    local manifest_url="${REPO_BASE_URL}/${REPO_CHANNEL}/manifest.json"
    log INFO "Consultando repositorio: ${manifest_url}"

    local manifest
    if command -v curl &>/dev/null; then
        manifest=$(curl -s --connect-timeout 10 --max-time 30 "${manifest_url}" 2>/dev/null || echo "")
    elif command -v wget &>/dev/null; then
        manifest=$(wget -q -O - --timeout=30 "${manifest_url}" 2>/dev/null || echo "")
    else
        log ERROR "Ni curl ni wget disponibles para consultar repositorio."
        exit 1
    fi

    if [ -z "${manifest}" ]; then
        log ERROR "No se pudo obtener manifiesto del repositorio. Verifique conectividad y URL."
        exit 1
    fi

    LATEST_VERSION=$(echo "${manifest}" | jq -r '.version // empty' 2>/dev/null || echo "")
    LATEST_VERSION_CODE=$(echo "${manifest}" | jq -r '.version_code // empty' 2>/dev/null || echo "0")
    APK_URL=$(echo "${manifest}" | jq -r '.apk_url // empty' 2>/dev/null || echo "")
    APK_MD5=$(echo "${manifest}" | jq -r '.md5 // empty' 2>/dev/null || echo "")

    if [ -z "${LATEST_VERSION}" ] || [ -z "${APK_URL}" ]; then
        log ERROR "Manifiesto invalido o incompleto. Campos requeridos: version, apk_url"
        exit 1
    fi

    log INFO "Ultima version en repositorio: ${LATEST_VERSION} (code: ${LATEST_VERSION_CODE})"
}

download_apk() {
    local url="$1"
    local output="$2"
    local expected_md5="$3"

    log INFO "Descargando APK desde: ${url}"

    if command -v curl &>/dev/null; then
        curl -L --connect-timeout 10 --max-time 120 -o "${output}" "${url}" || {
            log ERROR "Descarga fallida con curl."
            return 1
        }
    elif command -v wget &>/dev/null; then
        wget --timeout=120 -O "${output}" "${url}" || {
            log ERROR "Descarga fallida con wget."
            return 1
        }
    fi

    if [ ! -f "${output}" ]; then
        log ERROR "El archivo descargado no existe: ${output}"
        return 1
    fi

    local size
    size=$(stat -f%z "${output}" 2>/dev/null || stat -c%s "${output}" 2>/dev/null || echo "0")
    if [ "${size}" -lt 100000 ]; then
        log ERROR "APK descargado es demasiado pequeno (${size} bytes). Posible descarga corrupta."
        rm -f "${output}"
        return 1
    fi

    log INFO "APK descargado: ${size} bytes"

    # Verificar MD5 si se solicito
    if [ "${VERIFY_CHECKSUM}" = "true" ] && [ -n "${expected_md5}" ]; then
        log INFO "Verificando checksum MD5..."
        local actual_md5
        if command -v md5sum &>/dev/null; then
            actual_md5=$(md5sum "${output}" | awk '{print $1}')
        elif command -v md5 &>/dev/null; then
            actual_md5=$(md5 -q "${output}")
        else
            log WARN "Herramienta MD5 no disponible. Omitiendo verificacion."
            return 0
        fi

        if [ "${actual_md5}" != "${expected_md5}" ]; then
            log ERROR "Checksum mismatch! Esperado: ${expected_md5} Obtenido: ${actual_md5}"
            rm -f "${output}"
            return 1
        fi
        log OK "Checksum MD5 verificado correctamente."
    fi

    return 0
}

backup_current() {
    local device="$1"
    local version="$2"
    local backup_dir="${SCRIPT_DIR}/backups"
    mkdir -p "${backup_dir}"

    local backup_name="zoho_assist_v${version}_$(date +%Y%m%d_%H%M%S).apk"
    local backup_path="${backup_dir}/${backup_name}"

    log INFO "Creando backup de la version actual: ${backup_name}"

    # Extraer APK del dispositivo
    local apk_path
    apk_path=$(${ADB} -s "${device}" shell pm path com.zoho.assist 2>/dev/null | head -1 | cut -d':' -f2 | tr -d '\r')

    if [ -n "${apk_path}" ]; then
        ${ADB} -s "${device}" pull "${apk_path}" "${backup_path}" >/dev/null 2>&1 || {
            log WARN "No se pudo extraer backup del APK actual."
            return 1
        }
        log OK "Backup creado: ${backup_path}"

        # Rotar backups antiguos
        local backup_count
        backup_count=$(ls -1 "${backup_dir}"/zoho_assist_v*.apk 2>/dev/null | wc -l)
        if [ "${backup_count}" -gt "${ROLLBACK_KEEP_VERSIONS}" ]; then
            ls -1t "${backup_dir}"/zoho_assist_v*.apk | tail -n +$((ROLLBACK_KEEP_VERSIONS + 1)) | xargs rm -f
            log INFO "Rotacion de backups: se eliminaron versiones antiguas."
        fi
    else
        log WARN "No se pudo determinar la ruta del APK instalado."
        return 1
    fi

    echo "${backup_path}"
}

install_apk() {
    local device="$1"
    local apk_path="$2"

    log INFO "Instalando APK en ${device}..."

    # Desinstalar version actual (mantener datos)
    ${ADB} -s "${device}" uninstall -k com.zoho.assist 2>/dev/null || true

    # Instalar nueva version
    if ${ADB} -s "${device}" install -r -d "${apk_path}" 2>&1 | tee -a "${LOG_FILE}"; then
        log OK "APK instalado exitosamente."
        return 0
    else
        log ERROR "Fallo la instalacion del APK."
        return 1
    fi
}

perform_rollback() {
    local device="$1"
    local backup_dir="${SCRIPT_DIR}/backups"

    log INFO "Iniciando rollback..."

    local latest_backup
    latest_backup=$(ls -1t "${backup_dir}"/zoho_assist_v*.apk 2>/dev/null | head -1)

    if [ -z "${latest_backup}" ]; then
        log ERROR "No se encontraron backups para realizar rollback."
        return 1
    fi

    log INFO "Restaurando desde: ${latest_backup}"

    if install_apk "${device}" "${latest_backup}"; then
        log OK "Rollback completado exitosamente."
        return 0
    else
        log ERROR "Rollback fallido."
        return 1
    fi
}

restore_permissions() {
    local device="$1"

    log INFO "Restaurando permisos post-actualizacion..."

    # Permisos de accesibilidad
    ${ADB} -s "${device}" shell settings put secure enabled_accessibility_services com.zoho.assist/com.zoho.assist.service.AssistAccessibilityService 2>/dev/null || true
    ${ADB} -s "${device}" shell settings put secure accessibility_enabled 1 2>/dev/null || true

    # Permisos de overlay
    ${ADB} -s "${device}" shell appops set com.zoho.assist SYSTEM_ALERT_WINDOW allow 2>/dev/null || true

    # Whitelist de bateria
    ${ADB} -s "${device}" shell dumpsys deviceidle whitelist +com.zoho.assist 2>/dev/null || true

    log OK "Permisos restaurados."
}

main() {
    echo "============================================================"
    echo "  Zoho Assist - Auto-Updater TPV v1.0.0"
    echo "  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================================"
    echo ""

    # Parsear argumentos
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check-only) CHECK_ONLY=true; shift ;;
            --force) FORCE_UPDATE=true; shift ;;
            --rollback) DO_ROLLBACK=true; shift ;;
            --help|-h)
                echo "Uso: $0 [opciones]"
                echo "  --check-only   Solo verificar sin instalar"
                echo "  --force        Forzar reinstalacion aunque sea misma version"
                echo "  --rollback     Revertir a version anterior"
                exit 0
                ;;
            *) shift ;;
        esac
    done

    # Cargar configuracion
    load_config

    # Detectar dispositivo
    detect_device

    # ── Modo rollback ──────────────────────────────────────────────────────
    if [ "${DO_ROLLBACK}" = "true" ]; then
        if [ "${ROLLBACK_ENABLED}" != "true" ]; then
            log ERROR "Rollback deshabilitado en la configuracion."
            exit 1
        fi
        perform_rollback "${DEVICE}"
        restore_permissions "${DEVICE}"
        exit $?
    fi

    # Obtener version instalada
    INSTALLED_VER=$(get_installed_version "${DEVICE}")
    INSTALLED_CODE=$(get_installed_version_code "${DEVICE}")

    log INFO "Version instalada: ${INSTALLED_VER} (code: ${INSTALLED_CODE})"

    # Obtener info de la ultima version disponible
    get_latest_version_info

    # ── Modo check-only ───────────────────────────────────────────────────
    if [ "${CHECK_ONLY}" = "true" ]; then
        echo ""
        echo "============================================================"
        echo "  RESUMEN DE ACTUALIZACION"
        echo "============================================================"
        echo "  Instalada : ${INSTALLED_VER} (code: ${INSTALLED_CODE})"
        echo "  Disponible: ${LATEST_VERSION} (code: ${LATEST_VERSION_CODE})"
        if [ "${INSTALLED_CODE}" -lt "${LATEST_VERSION_CODE}" ]; then
            echo "  Estado    : ACTUALIZACION DISPONIBLE"
        else
            echo "  Estado    : Al dia"
        fi
        echo "============================================================"
        exit 0
    fi

    # Comparar versiones
    if [ "${INSTALLED_CODE}" -ge "${LATEST_VERSION_CODE}" ] && [ "${FORCE_UPDATE}" != "true" ]; then
        log OK "El dispositivo ya esta en la ultima version (${INSTALLED_VER})."
        exit 0
    fi

    if [ "${INSTALLED_CODE}" -gt "${LATEST_VERSION_CODE}" ] && [ "${ALLOW_DOWNGRADE}" != "true" ]; then
        log WARN "La version instalada es superior a la disponible. Downgrade no permitido."
        exit 0
    fi

    # Descargar APK
    local download_path="${SCRIPT_DIR}/zoho_assist_update_${LATEST_VERSION}.apk"
    download_apk "${APK_URL}" "${download_path}" "${APK_MD5}" || {
        log ERROR "No se pudo descargar la actualizacion."
        exit 1
    }

    # Backup de version actual
    if [ "${ROLLBACK_ENABLED}" = "true" ] && [ "${INSTALLED_VER}" != "NOT_INSTALLED" ]; then
        backup_current "${DEVICE}" "${INSTALLED_VER}" >/dev/null 2>&1 || true
    fi

    # Instalar actualizacion
    if install_apk "${DEVICE}" "${download_path}"; then
        # Restaurar permisos post-actualizacion
        restore_permissions "${DEVICE}"

        # Verificar que la nueva version se instalo correctamente
        sleep 3
        NEW_VER=$(get_installed_version "${DEVICE}")
        if [ "${NEW_VER}" = "${LATEST_VERSION}" ] || [ "${FORCE_UPDATE}" = "true" ]; then
            log OK "Actualizacion completada: ${INSTALLED_VER} -> ${NEW_VER}"
            echo ""
            echo "============================================================"
            echo "  ACTUALIZACION COMPLETADA EXITOSAMENTE"
            echo "============================================================"
            echo "  Anterior : ${INSTALLED_VER}"
            echo "  Nueva    : ${NEW_VER}"
            echo "============================================================"
        else
            log ERROR "La version instalada (${NEW_VER}) no coincide con la esperada (${LATEST_VERSION})."
            if [ "${ROLLBACK_ENABLED}" = "true" ]; then
                log INFO "Iniciando rollback automatico..."
                perform_rollback "${DEVICE}"
            fi
            exit 1
        fi
    else
        log ERROR "Fallo la instalacion de la actualizacion."
        if [ "${ROLLBACK_ENABLED}" = "true" ]; then
            log INFO "Iniciando rollback automatico..."
            perform_rollback "${DEVICE}"
        fi
        exit 1
    fi

    # Limpiar APK descargado
    rm -f "${download_path}"
}

main "$@"
