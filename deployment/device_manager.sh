#!/usr/bin/env bash
# ============================================================================
#  Zoho Assist - Gestor Centralizado de Dispositivos TPV
#  Funciones: inventario, health check, comandos remotos, reportes
#  Version: 1.0.0 | Fecha: 2026-05-21
#
#  Uso:
#    ./device_manager.sh --inventory           Listar todos los dispositivos
#    ./device_manager.sh --health-check        Verificar salud de dispositivo(s)
#    ./device_manager.sh --enable-wifi-adb     Habilitar ADB sobre TCP/IP
#    ./device_manager.sh --reboot              Reiniciar dispositivo(s)
#    ./device_manager.sh --export-csv          Exportar inventario a CSV
#    ./device_manager.sh --device <serial>     Operar en dispositivo especifico
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADB="${ADB:-adb}"
CONFIG_FILE="${SCRIPT_DIR}/zoho_tpv_config.json"
OUTPUT_DIR="${SCRIPT_DIR}/reports"
mkdir -p "${OUTPUT_DIR}"

# ── Colores ────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ── Funciones de utilidad ──────────────────────────────────────────────────
banner() {
    echo -e "${BOLD}============================================================${NC}"
    echo -e "${BOLD}  Zoho Assist - Gestor de Dispositivos TPV v1.0.0${NC}"
    echo -e "${BOLD}  $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${BOLD}============================================================${NC}"
    echo ""
}

get_device_info() {
    local device="$1"
    local info=""

    info+="$(adb -s "$device" shell getprop ro.product.manufacturer 2>/dev/null | tr -d '\r')|"
    info+="$(adb -s "$device" shell getprop ro.product.model 2>/dev/null | tr -d '\r')|"
    info+="$(adb -s "$device" shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')|"
    info+="$(adb -s "$device" shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')|"
    info+="$(adb -s "$device" shell getprop ro.serialno 2>/dev/null | tr -d '\r')|"

    # Version de Zoho
    local zoho_ver
    zoho_ver=$(adb -s "$device" shell dumpsys package com.zoho.assist 2>/dev/null | grep "versionName" | head -1 | cut -d'=' -f2 | tr -d '\r')
    info+="${zoho_ver:-N/A}|"

    # Estado de conexion
    local wifi
    wifi=$(adb -s "$device" shell dumpsys connectivity 2>/dev/null | grep "WIFI" | head -1 | grep -o "CONNECTED\|DISCONNECTED" || echo "UNKNOWN")
    info+="${wifi}|"

    # Bateria
    local battery
    battery=$(adb -s "$device" shell dumpsys battery 2>/dev/null | grep "level" | head -1 | grep -oP '\d+')
    info+="${battery:-?}%|"

    # Espacio libre
    local storage
    storage=$(adb -s "$device" shell df /data 2>/dev/null | tail -1 | awk '{print $4}' | tr -d '\r')
    if [ -n "${storage}" ] && [ "${storage}" -gt 0 ] 2>/dev/null; then
        info+="$(( storage / 1024 ))MB"
    else
        info+="N/A"
    fi

    echo "${info}"
}

is_zoho_running() {
    local device="$1"
    adb -s "$device" shell ps 2>/dev/null | grep -q "com.zoho.assist" && echo "YES" || echo "NO"
}

check_accessibility() {
    local device="$1"
    local a11y
    a11y=$(adb -s "$device" shell settings get secure enabled_accessibility_services 2>/dev/null | tr -d '\r')
    if echo "${a11y}" | grep -q "com.zoho.assist"; then
        echo "YES"
    else
        echo "NO"
    fi
}

check_device_owner() {
    local device="$1"
    adb -s "$device" shell dumpsys device_policy 2>/dev/null | grep -q "com.zoho.assist" && echo "YES" || echo "NO"
}

# ── Comandos ───────────────────────────────────────────────────────────────

cmd_inventory() {
    banner
    echo -e "${BOLD}INVENTARIO DE DISPOSITIVOS TPV${NC}"
    echo ""

    mapfile -t devices < <(${ADB} devices | tail -n +2 | grep -v "^$" | awk '{print $1}')

    if [ ${#devices[@]} -eq 0 ]; then
        echo -e "${RED}No se detectaron dispositivos conectados.${NC}"
        exit 1
    fi

    printf "${BOLD}%-20s %-18s %-10s %-14s %-10s %-8s %-8s %-10s${NC}\n" \
        "SERIAL" "MODELO" "ANDROID" "ZOHO" "WIFI" "BATERIA" "VIVO" "ESPACIO"
    echo "──────────────────────────────────────────────────────────────────────────────────────────────────"

    for device in "${devices[@]}"; do
        local info
        info=$(get_device_info "$device")
        IFS='|' read -r manufacturer model android_ver sdk serial zoho_ver wifi batt storage <<< "${info}"

        local running
        running=$(is_zoho_running "$device")

        local running_icon="❌"
        [ "${running}" = "YES" ] && running_icon="✅"

        local wifi_icon="❌"
        [ "${wifi}" = "CONNECTED" ] && wifi_icon="✅"

        printf "%-20s %-18s %-10s %-14s %-8s %-8s %-8s %-10s\n" \
            "${device:0:19}" \
            "${model:0:17}" \
            "${android_ver} (SDK${sdk})" \
            "${zoho_ver:0:13}" \
            "${wifi_icon}" \
            "${batt}" \
            "${running_icon}" \
            "${storage}"
    done

    echo ""
    echo -e "${GREEN}Total dispositivos: ${#devices[@]}${NC}"
}

cmd_health_check() {
    local target_device="${1:-}"

    banner
    echo -e "${BOLD}HEALTH CHECK DE DISPOSITIVO(S)${NC}"
    echo ""

    mapfile -t devices < <(${ADB} devices | tail -n +2 | grep -v "^$" | awk '{print $1}')

    if [ -n "${target_device}" ]; then
        devices=("${target_device}")
    fi

    if [ ${#devices[@]} -eq 0 ]; then
        echo -e "${RED}No se detectaron dispositivos.${NC}"
        exit 1
    fi

    local total_checks=0
    local total_passed=0

    for device in "${devices[@]}"; do
        echo -e "${CYAN}────────────────────────────────────────────${NC}"
        echo -e "${BOLD}Dispositivo: ${device}${NC}"
        echo -e "${CYAN}────────────────────────────────────────────${NC}"

        local checks=0
        local passed=0

        # Check 1: Conexion ADB
        ((checks++))
        if ${ADB} -s "$device" shell echo "ok" &>/dev/null; then
            echo -e "  ${GREEN}✅${NC} Conexión ADB"
            ((passed++))
        else
            echo -e "  ${RED}❌${NC} Conexión ADB"
        fi

        # Check 2: Zoho instalado
        ((checks++))
        if ${ADB} -s "$device" shell pm list packages 2>/dev/null | grep -q "com.zoho.assist"; then
            echo -e "  ${GREEN}✅${NC} Zoho Assist instalado"
            ((passed++))
        else
            echo -e "  ${RED}❌${NC} Zoho Assist NO instalado"
        fi

        # Check 3: Servicio corriendo
        ((checks++))
        if [ "$(is_zoho_running "$device")" = "YES" ]; then
            echo -e "  ${GREEN}✅${NC} Proceso Zoho activo"
            ((passed++))
        else
            echo -e "  ${RED}❌${NC} Proceso Zoho NO activo"
        fi

        # Check 4: Accesibilidad
        ((checks++))
        if [ "$(check_accessibility "$device")" = "YES" ]; then
            echo -e "  ${GREEN}✅${NC} Servicio de accesibilidad"
            ((passed++))
        else
            echo -e "  ${RED}❌${NC} Servicio de accesibilidad NO habilitado"
        fi

        # Check 5: Bateria > 15%
        ((checks++))
        local battery
        battery=$(adb -s "$device" shell dumpsys battery 2>/dev/null | grep "level" | grep -oP '\d+' || echo "0")
        if [ "${battery}" -gt 15 ]; then
            echo -e "  ${GREEN}✅${NC} Batería: ${battery}%"
            ((passed++))
        else
            echo -e "  ${RED}❌${NC} Batería crítica: ${battery}%"
        fi

        # Check 6: Espacio libre > 50MB
        ((checks++))
        local storage_kb
        storage_kb=$(adb -s "$device" shell df /data 2>/dev/null | tail -1 | awk '{print $4}' | tr -d '\r')
        if [ -n "${storage_kb}" ] && [ "${storage_kb}" -gt 51200 ] 2>/dev/null; then
            local storage_mb=$((storage_kb / 1024))
            echo -e "  ${GREEN}✅${NC} Espacio libre: ${storage_mb}MB"
            ((passed++))
        else
            echo -e "  ${RED}❌${NC} Espacio insuficiente"
        fi

        # Check 7: WiFi conectado
        ((checks++))
        local wifi
        wifi=$(adb -s "$device" shell dumpsys connectivity 2>/dev/null | grep "WIFI" | head -1 | grep -o "CONNECTED" || echo "")
        if [ "${wifi}" = "CONNECTED" ]; then
            echo -e "  ${GREEN}✅${NC} WiFi conectado"
            ((passed++))
        else
            echo -e "  ${RED}❌${NC} WiFi no conectado"
        fi

        # Check 8: Device Owner
        ((checks++))
        if [ "$(check_device_owner "$device")" = "YES" ]; then
            echo -e "  ${GREEN}✅${NC} Device Owner configurado"
            ((passed++))
        else
            echo -e "  ${YELLOW}⚠️${NC}  Device Owner no configurado (pueden aparecer diálogos)"
            ((passed++))  # No es bloqueante
        fi

        echo ""
        echo -e "  Resultado: ${passed}/${checks} checks OK"

        if [ ${passed} -eq ${checks} ]; then
            echo -e "  Estado:    ${GREEN}SALUDABLE${NC}"
        elif [ ${passed} -ge $((checks - 1)) ]; then
            echo -e "  Estado:    ${YELLOW}ATENCIÓN${NC}"
        else
            echo -e "  Estado:    ${RED}CRÍTICO${NC}"
        fi
        echo ""

        total_checks=$((total_checks + checks))
        total_passed=$((total_passed + passed))
    done

    echo -e "${BOLD}────────────────────────────────────────────${NC}"
    echo -e "${BOLD}Resumen global: ${total_passed}/${total_checks} checks OK${NC}"
}

cmd_enable_wifi_adb() {
    local device="$1"

    if [ -z "${device}" ]; then
        device=$(adb devices | tail -n +2 | head -1 | awk '{print $1}')
    fi

    echo "Habilitando ADB sobre WiFi en ${device}..."
    echo "NOTA: El dispositivo debe estar conectado via USB primero."

    local port=5555

    # Reiniciar ADB en modo TCP/IP
    adb -s "$device" tcpip "${port}"
    sleep 2

    # Obtener IP del dispositivo
    local ip
    ip=$(adb -s "$device" shell ip route 2>/dev/null | grep -oP 'src \K[\d.]+' | head -1)
    if [ -z "${ip}" ]; then
        ip=$(adb -s "$device" shell ifconfig wlan0 2>/dev/null | grep "inet addr" | cut -d':' -f2 | awk '{print $1}')
    fi

    if [ -z "${ip}" ]; then
        echo -e "${RED}No se pudo obtener la IP del dispositivo.${NC}"
        exit 1
    fi

    echo "Conectando a ${device} via WiFi (${ip}:${port})..."
    adb connect "${ip}:${port}"

    echo ""
    echo -e "${GREEN}ADB WiFi habilitado.${NC}"
    echo "Para usar: adb -s ${ip}:${port} <comando>"
    echo "Comando de conexión directa: adb connect ${ip}:${port}"
}

cmd_reboot() {
    local device="${1:-}"

    if [ -z "${device}" ]; then
        mapfile -t devices < <(${ADB} devices | tail -n +2 | grep -v "^$" | awk '{print $1}')
        if [ ${#devices[@]} -eq 0 ]; then
            echo -e "${RED}No hay dispositivos conectados.${NC}"
            exit 1
        fi
        device="${devices[0]}"
    fi

    echo -e "${YELLOW}Reiniciando dispositivo ${device}...${NC}"
    adb -s "$device" reboot
    echo -e "${GREEN}Comando de reinicio enviado.${NC}"
}

cmd_export_csv() {
    banner
    echo "Exportando inventario a CSV..."

    local csv_file="${OUTPUT_DIR}/inventory_$(date +%Y%m%d_%H%M%S).csv"
    echo "serial,manufacturer,model,android_version,sdk,zoho_version,wifi,battery,storage,zoho_running,accessibility,device_owner,timestamp" > "${csv_file}"

    mapfile -t devices < <(${ADB} devices | tail -n +2 | grep -v "^$" | awk '{print $1}')

    for device in "${devices[@]}"; do
        local info
        info=$(get_device_info "$device")
        IFS='|' read -r manufacturer model android_ver sdk serial zoho_ver wifi batt storage <<< "${info}"

        local running
        running=$(is_zoho_running "$device")

        local a11y
        a11y=$(check_accessibility "$device")

        local dpm
        dpm=$(check_device_owner "$device")

        echo "${serial},${manufacturer},${model},${android_ver},${sdk},${zoho_ver},${wifi},${batt},${storage},${running},${a11y},${dpm},$(date -Iseconds)" >> "${csv_file}"
    done

    echo -e "${GREEN}CSV exportado: ${csv_file}${NC}"
    echo "Total dispositivos: ${#devices[@]}"
}

# ── Main ───────────────────────────────────────────────────────────────────
main() {
    local TARGET_DEVICE=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --inventory)
                cmd_inventory
                exit 0
                ;;
            --health-check)
                shift
                TARGET_DEVICE="${1:-}"
                cmd_health_check "${TARGET_DEVICE}"
                exit 0
                ;;
            --enable-wifi-adb)
                shift
                TARGET_DEVICE="${1:-}"
                cmd_enable_wifi_adb "${TARGET_DEVICE}"
                exit 0
                ;;
            --reboot)
                shift
                TARGET_DEVICE="${1:-}"
                cmd_reboot "${TARGET_DEVICE}"
                exit 0
                ;;
            --export-csv)
                cmd_export_csv
                exit 0
                ;;
            --device)
                TARGET_DEVICE="$2"
                shift 2
                ;;
            --help|-h)
                echo "Uso: $0 [comando] [opciones]"
                echo ""
                echo "Comandos:"
                echo "  --inventory               Listar todos los dispositivos conectados"
                echo "  --health-check [serial]   Verificar salud de dispositivo(s)"
                echo "  --enable-wifi-adb [serial] Habilitar ADB sobre TCP/IP"
                echo "  --reboot [serial]         Reiniciar dispositivo"
                echo "  --export-csv              Exportar inventario a CSV"
                echo ""
                echo "Opciones:"
                echo "  --device <serial>         Especificar dispositivo para comandos que lo soporten"
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done

    # Si no se especifica comando, mostrar ayuda
    echo "Especifique un comando. Use --help para ver opciones."
}

main "$@"
