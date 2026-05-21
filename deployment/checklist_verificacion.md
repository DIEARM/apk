# Lista de Verificación de Instalación — Zoho Assist TPV

**Versión:** 1.0.0 | **Objetivo:** Validar instalación correcta en cada TPV antes de entregar a producción.

---

## Checklist de 10 Puntos

| # | Punto de Verificación | Comando / Método | Esperado | ✅ |
|---|---|---|---|---|
| **1** | **APK instalado correctamente** | `adb shell pm list packages \| grep com.zoho.assist` | Debe retornar `package:com.zoho.assist` | ☐ |
| **2** | **Versión correcta** | `adb shell dumpsys package com.zoho.assist \| grep versionName` | Debe coincidir con la versión del manifiesto del repositorio (ej: `4.2.1`) | ☐ |
| **3** | **Servicio de accesibilidad habilitado** | `adb shell settings get secure enabled_accessibility_services` | Debe contener `com.zoho.assist` | ☐ |
| **4** | **Permiso SYSTEM_ALERT_WINDOW concedido** | `adb shell appops get com.zoho.assist SYSTEM_ALERT_WINDOW` | Debe retornar `allow` | ☐ |
| **5** | **Permiso de captura de pantalla** | `adb shell appops get com.zoho.assist PROJECT_MEDIA` | Debe retornar `allow` | ☐ |
| **6** | **Optimización de batería deshabilitada** | `adb shell dumpsys deviceidle whitelist +com.zoho.assist` | `com.zoho.assist` debe aparecer en la whitelist | ☐ |
| **7** | **Configuración JSON presente en dispositivo** | `adb shell ls -la /sdcard/zoho_tpv_config.json` | Debe existir y tener tamaño > 0 bytes | ☐ |
| **8** | **Conectividad de red activa** | `adb shell ping -c 2 -W 5 assist.zoho.com` | 0% packet loss (o al menos 1 paquete recibido en redes con restricciones) | ☐ |
| **9** | **Aplicación en ejecución (proceso vivo)** | `adb shell ps \| grep com.zoho.assist` | Debe aparecer al menos un proceso de Zoho Assist | ☐ |
| **10** | **Checksum MD5 del APK en dispositivo coincide con repositorio** | Comparar `md5sum` del APK local con el valor en `manifest.json` del repositorio | Coincidencia exacta | ☐ |

---

## Comandos de Verificación Rápida (Ejecutar en bloque)

### Linux/macOS

```bash
#!/bin/bash
# zoho_verify.sh — Verificación rápida de 10 puntos
DEVICE="${1:-$(adb devices | tail -n +2 | head -1 | awk '{print $1}')}"
echo "=== Verificando dispositivo: $DEVICE ==="
echo ""

echo "[1] APK instalado:"
adb -s "$DEVICE" shell pm list packages | grep -q "com.zoho.assist" && echo "  ✅ OK" || echo "  ❌ FALLO"

echo "[2] Versión:"
adb -s "$DEVICE" shell dumpsys package com.zoho.assist | grep "versionName" | head -1
echo ""

echo "[3] Accesibilidad:"
adb -s "$DEVICE" shell settings get secure enabled_accessibility_services | grep -q "com.zoho.assist" && echo "  ✅ OK" || echo "  ❌ FALLO"

echo "[4] Overlay:"
adb -s "$DEVICE" shell appops get com.zoho.assist SYSTEM_ALERT_WINDOW

echo "[5] Captura pantalla:"
adb -s "$DEVICE" shell appops get com.zoho.assist PROJECT_MEDIA

echo "[6] Batería whitelist:"
adb -s "$DEVICE" shell dumpsys deviceidle whitelist +com.zoho.assist | grep -q "com.zoho.assist" && echo "  ✅ OK" || echo "  ❌ FALLO"

echo "[7] Config JSON:"
adb -s "$DEVICE" shell ls -la /sdcard/zoho_tpv_config.json 2>/dev/null && echo "  ✅ OK" || echo "  ❌ FALLO"

echo "[8] Conectividad:"
adb -s "$DEVICE" shell "ping -c 2 -W 5 assist.zoho.com 2>&1" | tail -1

echo "[9] Proceso vivo:"
adb -s "$DEVICE" shell ps | grep -q "com.zoho.assist" && echo "  ✅ OK" || echo "  ❌ FALLO"

echo "[10] Verificar MD5 — comparar manualmente con manifest.json del repositorio"
echo ""

echo "=== Verificación completada ==="
```

### Windows (PowerShell)

```powershell
# zoho_verify.ps1
param($DeviceSerial)

if (-not $DeviceSerial) {
    $DeviceSerial = (adb devices | Select-Object -Skip 1 | Select-Object -First 1) -replace '\s+.*',''
}

Write-Host "=== Verificando dispositivo: $DeviceSerial ==="

Write-Host "`n[1] APK instalado:"
$pkg = adb -s $DeviceSerial shell pm list packages | Select-String "com.zoho.assist"
if ($pkg) { Write-Host "  ✅ OK" } else { Write-Host "  ❌ FALLO" }

Write-Host "`n[2] Versión:"
adb -s $DeviceSerial shell dumpsys package com.zoho.assist | Select-String "versionName"

Write-Host "`n[3] Accesibilidad:"
$acc = adb -s $DeviceSerial shell settings get secure enabled_accessibility_services
if ($acc -match "com.zoho.assist") { Write-Host "  ✅ OK" } else { Write-Host "  ❌ FALLO" }

Write-Host "`n[4] Overlay:"; adb -s $DeviceSerial shell appops get com.zoho.assist SYSTEM_ALERT_WINDOW
Write-Host "`n[5] Captura:"; adb -s $DeviceSerial shell appops get com.zoho.assist PROJECT_MEDIA

Write-Host "`n[6] Batería whitelist:"
$bat = adb -s $DeviceSerial shell dumpsys deviceidle whitelist +com.zoho.assist
if ($bat -match "com.zoho.assist") { Write-Host "  ✅ OK" } else { Write-Host "  ❌ FALLO" }

Write-Host "`n[7] Config JSON:"
$cfg = adb -s $DeviceSerial shell ls -la /sdcard/zoho_tpv_config.json 2>&1
if ($LASTEXITCODE -eq 0) { Write-Host "  ✅ OK" } else { Write-Host "  ❌ FALLO" }

Write-Host "`n[8] Conectividad:"; adb -s $DeviceSerial shell "ping -c 2 -W 5 assist.zoho.com 2>&1"

Write-Host "`n[9] Proceso vivo:"
$proc = adb -s $DeviceSerial shell ps | Select-String "com.zoho.assist"
if ($proc) { Write-Host "  ✅ OK" } else { Write-Host "  ❌ FALLO" }

Write-Host "`n[10] MD5: Comparar manualmente con manifest.json del repositorio"

Write-Host "`n=== Verificación completada ==="
```

---

## Criterios de Aceptación

| Resultado | Acción |
|---|---|
| 10/10 ✅ | Dispositivo listo para producción. Etiquetar y documentar. |
| 8-9/10 ✅ | Revisar fallos. Si son recuperables (ej: conectividad temporal), reintentar. |
| < 8/10 ✅ | Reinstalar desde cero con `install_zoho.sh`. |
| Punto #10 ❌ | **Crítico** — Posible APK corrupto o manipulado. No desplegar. |

---

## Registro de Verificación

| Dispositivo Serial | Fecha | Técnico | Puntaje | Observaciones |
|---|---|---|---|---|
| _______________ | ___/___/____ | _______________ | __/10 | _______________ |
| _______________ | ___/___/____ | _______________ | __/10 | _______________ |
| _______________ | ___/___/____ | _______________ | __/10 | _______________ |

---

## Checksums MD5 de Referencia

> **IMPORTANTE**: Estos valores deben actualizarse con cada nueva versión desplegada.

```
# Generar MD5 del APK oficial
# Linux/macOS:
md5sum zoho_assist.apk
# Windows:
certutil -hashfile zoho_assist.apk MD5

# Versión actual (2026-05-21):
# zoho_assist.apk  MD5: [PENDIENTE_DE_CALCULAR]
# manifest.json    MD5: [PENDIENTE_DE_CALCULAR]
```

---

## URL de Repositorio Privado para Actualizaciones

```
Base URL:  https://repo-empresarial.example.com/zoho
Canal:     stable
Manifiesto: https://repo-empresarial.example.com/zoho/stable/manifest.json
APK:       https://repo-empresarial.example.com/zoho/stable/zoho_assist.apk
```

> Reemplace `repo-empresarial.example.com` por el dominio real de su infraestructura.
