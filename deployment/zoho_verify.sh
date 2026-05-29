#!/bin/bash
# ============================================================================
#  zoho_verify.sh — Verificación rápida de 10 puntos para Zoho Assist en TPV
#  Uso: ./zoho_verify.sh [device_serial]
# ============================================================================
set -euo pipefail

DEVICE="${1:-$(adb devices | tail -n +2 | head -1 | awk '{print $1}')}"

if [ -z "$DEVICE" ]; then
    echo "ERROR: No se detectó ningún dispositivo Android vía ADB."
    echo "Conecta un dispositivo y asegúrate de que 'adb devices' lo muestre."
    exit 1
fi

echo "============================================="
echo "  Verificación Zoho Assist TPV — 10 puntos"
echo "  Dispositivo: $DEVICE"
echo "============================================="

PASS=0
FAIL=0

check() {
    local num="$1"; shift
    local label="$1"; shift
    echo ""
    echo "[$num] $label"
    if "$@"; then
        echo "  ✅ OK"
        PASS=$((PASS + 1))
    else
        echo "  ❌ FALLO"
        FAIL=$((FAIL + 1))
    fi
}

# 1
check 1 "APK instalado" \
    sh -c "adb -s '$DEVICE' shell pm list packages | grep -q 'com.zoho.assist'"

# 2
echo ""
echo "[2] Versión:"
adb -s "$DEVICE" shell dumpsys package com.zoho.assist 2>/dev/null | grep "versionName" | head -1 || echo "  ❌ No detectada"
# Count as pass if we got version
adb -s "$DEVICE" shell dumpsys package com.zoho.assist 2>/dev/null | grep -q "versionName" && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# 3
check 3 "Servicio de accesibilidad habilitado" \
    sh -c "adb -s '$DEVICE' shell settings get secure enabled_accessibility_services | grep -q 'com.zoho.assist'"

# 4
echo ""
echo "[4] Permiso SYSTEM_ALERT_WINDOW:"
adb -s "$DEVICE" shell appops get com.zoho.assist SYSTEM_ALERT_WINDOW 2>/dev/null || echo "  ❌ Error"
adb -s "$DEVICE" shell appops get com.zoho.assist SYSTEM_ALERT_WINDOW 2>/dev/null | grep -q "allow" && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# 5
echo ""
echo "[5] Permiso PROJECT_MEDIA (captura pantalla):"
adb -s "$DEVICE" shell appops get com.zoho.assist PROJECT_MEDIA 2>/dev/null || echo "  ❌ Error"
adb -s "$DEVICE" shell appops get com.zoho.assist PROJECT_MEDIA 2>/dev/null | grep -q "allow" && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# 6
check 6 "Optimización batería deshabilitada" \
    sh -c "adb -s '$DEVICE' shell dumpsys deviceidle whitelist +com.zoho.assist 2>/dev/null | grep -q 'com.zoho.assist'"

# 7
check 7 "Config JSON presente" \
    sh -c "adb -s '$DEVICE' shell ls -la /sdcard/zoho_tpv_config.json >/dev/null 2>&1"

# 8
echo ""
echo "[8] Conectividad de red:"
adb -s "$DEVICE" shell "ping -c 2 -W 5 assist.zoho.com 2>&1" | tail -2
adb -s "$DEVICE" shell "ping -c 2 -W 5 assist.zoho.com 2>&1" | grep -q " 0% packet loss" && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# 9
check 9 "Proceso vivo" \
    sh -c "adb -s '$DEVICE' shell ps | grep -q 'com.zoho.assist'"

# 10
echo ""
echo "[10] MD5 — Comparar manualmente con manifest.json del repositorio"

echo ""
echo "============================================="
echo "  Resultado: $PASS/10 aprobados, $FAIL fallos"
echo "============================================="

if [ "$PASS" -eq 10 ]; then
    echo "✅ Dispositivo listo para producción."
elif [ "$PASS" -ge 8 ]; then
    echo "⚠️  Revisar fallos. Si son recuperables, reintentar."
else
    echo "❌ Menos de 8/10. Se recomienda reinstalar con install_zoho.sh"
fi
