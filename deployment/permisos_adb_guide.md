# Guía de Permisos ADB para Control Remoto sin Confirmaciones

**Versión:** 1.0.0  
**Propósito:** Configurar permisos especiales de Android que eliminan diálogos de confirmación durante sesiones de control remoto.

---

## Índice

1. [Fundamento: por qué aparecen confirmaciones](#1-fundamento)
2. [Permisos Runtime](#2-permisos-runtime)
3. [Permisos Especiales (appops)](#3-permisos-especiales-appops)
4. [Servicio de Accesibilidad](#4-servicio-de-accesibilidad)
5. [Device Admin / Device Owner](#5-device-admin--device-owner)
6. [Optimización de Batería](#6-optimización-de-batería)
7. [Script de Configuración Completo](#7-script-de-configuración-completo)
8. [Verificación](#8-verificación)

---

## 1. Fundamento: por qué aparecen confirmaciones

Android muestra diálogos de confirmación por razones de seguridad y privacidad. Para un TPV que debe operar de forma desatendida, cada diálogo bloquea la sesión remota. La solución es **conceder permisos permanente + Device Owner**.

**Jerarquía de permisos (más alto = más poder, menos confirmaciones):**

```
Device Owner (dpm set-device-owner)
  └── Device Admin
       └── Permisos Signature/Privileged
            └── Permisos Runtime (grant)
                 └── AppOps (appops set)
```

---

## 2. Permisos Runtime

Concedidos con `adb shell pm grant`. No caducan a menos que se revoquen manualmente.

```bash
DEVICE=""

# Permisos esenciales para control remoto
adb -s $DEVICE shell pm grant com.zoho.assist android.permission.CAMERA
adb -s $DEVICE shell pm grant com.zoho.assist android.permission.RECORD_AUDIO
adb -s $DEVICE shell pm grant com.zoho.assist android.permission.ACCESS_FINE_LOCATION
adb -s $DEVICE shell pm grant com.zoho.assist android.permission.READ_EXTERNAL_STORAGE
adb -s $DEVICE shell pm grant com.zoho.assist android.permission.WRITE_EXTERNAL_STORAGE
adb -s $DEVICE shell pm grant com.zoho.assist android.permission.READ_PHONE_STATE

# Permisos signature-level (requieren que el APK esté firmado con la misma key del sistema
# o que se instale como sistema; si no, son no-op pero no dañan)
adb -s $DEVICE shell pm grant com.zoho.assist android.permission.SYSTEM_ALERT_WINDOW
adb -s $DEVICE shell pm grant com.zoho.assist android.permission.WRITE_SETTINGS
adb -s $DEVICE shell pm grant com.zoho.assist android.permission.PACKAGE_USAGE_STATS
adb -s $DEVICE shell pm grant com.zoho.assist android.permission.BIND_ACCESSIBILITY_SERVICE
adb -s $DEVICE shell pm grant com.zoho.assist android.permission.BIND_DEVICE_ADMIN
```

---

## 3. Permisos Especiales (AppOps)

Algunos permisos se gestionan a través de `appops`, no de `pm grant`. Son más granulares.

```bash
# SYSTEM_ALERT_WINDOW — Necesario para el overlay de screen sharing
adb -s $DEVICE shell appops set com.zoho.assist SYSTEM_ALERT_WINDOW allow

# PROJECT_MEDIA — Captura de pantalla sin diálogo de confirmación
adb -s $DEVICE shell appops set com.zoho.assist PROJECT_MEDIA allow

# POST_NOTIFICATIONS — Notificaciones persistentes (Android 13+)
adb -s $DEVICE shell appops set com.zoho.assist POST_NOTIFICATIONS allow

# RUN_IN_BACKGROUND — Evitar que el sistema mate el proceso
adb -s $DEVICE shell cmd appops set com.zoho.assist RUN_IN_BACKGROUND allow
```

### Verificar estado de AppOps

```bash
adb -s $DEVICE shell appops get com.zoho.assist
# Muestra todos los appops y su estado actual
```

---

## 4. Servicio de Accesibilidad

El Accessibility Service es el mecanismo que permite a Zoho Assist **inyectar eventos táctiles y leer la pantalla** para control remoto.

### Habilitar vía ADB (sin intervención del usuario)

```bash
# Habilitar el servicio de accesibilidad específico de Zoho
adb -s $DEVICE shell settings put secure enabled_accessibility_services \
    com.zoho.assist/com.zoho.assist.service.AssistAccessibilityService

# Activar accesibilidad globalmente
adb -s $DEVICE shell settings put secure accessibility_enabled 1
```

### Verificar

```bash
adb -s $DEVICE shell settings get secure enabled_accessibility_services
# Debe contener: com.zoho.assist/com.zoho.assist.service.AssistAccessibilityService

adb -s $DEVICE shell settings get secure accessibility_enabled
# Debe retornar: 1
```

---

## 5. Device Admin / Device Owner

### Device Admin

Permite ciertas políticas sin confirmación (bloqueo de pantalla, wipe, políticas de contraseña).

```bash
# Habilitar Device Admin (puede requerir confirmación en pantalla la primera vez)
adb -s $DEVICE shell dpm set-active-admin com.zoho.assist/.receiver.DeviceAdminReceiver
```

### Device Owner (Nivel máximo sin root)

**Device Owner** es el máximo privilegio sin root. Permite:
- Deshabilitar la barra de estado
- Gestionar actualizaciones del sistema
- **Eliminar confirmaciones de permisos peligrosos**
- Instalar/desinstalar apps silenciosamente

**Requisito:** El dispositivo NO debe tener cuentas configuradas (Google, etc.).

```bash
# Configurar Device Owner
adb -s $DEVICE shell dpm set-device-owner com.zoho.assist/.receiver.DeviceAdminReceiver

# Si falla, verificar si ya existe un Device Owner:
adb -s $DEVICE shell dumpsys device_policy | grep "Device Owner"
```

**Error común:**
```
java.lang.IllegalStateException: Trying to set device owner but device has already been provisioned
```
**Solución:** Hacer factory reset del dispositivo, o eliminar cuentas existentes:
```bash
adb -s $DEVICE shell pm remove-user 999  # Eliminar usuario de trabajo (si existe)
```

### Quitar Device Owner (si es necesario)

```bash
adb -s $DEVICE shell dpm remove-active-admin com.zoho.assist/.receiver.DeviceAdminReceiver
```

---

## 6. Optimización de Batería (Doze Mode)

Android suspende procesos en background. Para control remoto **permanente**, hay que deshabilitar esto para Zoho.

```bash
# Añadir a whitelist de Doze
adb -s $DEVICE shell dumpsys deviceidle whitelist +com.zoho.assist

# Para Android 9+: tempwhitelist (dura un tiempo limitado)
adb -s $DEVICE shell cmd deviceidle tempwhitelist com.zoho.assist

# Verificar
adb -s $DEVICE shell dumpsys deviceidle whitelist | grep com.zoho.assist
```

### Alternativa: Deshabilitar Doze globalmente (solo en TPV dedicados)

```bash
adb -s $DEVICE shell dumpsys deviceidle disable
```

---

## 7. Script de Configuración Completo

```bash
#!/bin/bash
# setup_permissions.sh — Configura todos los permisos para Zoho Assist sin confirmaciones
set -euo pipefail

DEVICE="${1:-$(adb devices | tail -n +2 | head -1 | awk '{print $1}')}"
PKG="com.zoho.assist"
A11Y_SERVICE="${PKG}/com.zoho.assist.service.AssistAccessibilityService"
ADMIN_RECEIVER="${PKG}/.receiver.DeviceAdminReceiver"

echo "Configurando permisos para ${PKG} en dispositivo ${DEVICE}..."
echo "============================================================"

# ── 1. Permisos Runtime ─────────────────────────────────────────────────
echo "[1/6] Permisos runtime..."
declare -a PERMS=(
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

for perm in "${PERMS[@]}"; do
    adb -s "$DEVICE" shell pm grant "$PKG" "$perm" 2>/dev/null && \
        echo "  ✅ $perm" || echo "  ⚠️  $perm (ignorado)"
done

# ── 2. AppOps ───────────────────────────────────────────────────────────
echo "[2/6] AppOps..."
adb -s "$DEVICE" shell appops set "$PKG" SYSTEM_ALERT_WINDOW allow
adb -s "$DEVICE" shell appops set "$PKG" PROJECT_MEDIA allow
adb -s "$DEVICE" shell appops set "$PKG" POST_NOTIFICATIONS allow
adb -s "$DEVICE" shell cmd appops set "$PKG" RUN_IN_BACKGROUND allow
echo "  ✅ AppOps configurados"

# ── 3. Servicio de Accesibilidad ────────────────────────────────────────
echo "[3/6] Servicio de accesibilidad..."
adb -s "$DEVICE" shell settings put secure enabled_accessibility_services "$A11Y_SERVICE"
adb -s "$DEVICE" shell settings put secure accessibility_enabled 1
echo "  ✅ Accesibilidad habilitada"

# ── 4. Device Admin ─────────────────────────────────────────────────────
echo "[4/6] Device Admin..."
adb -s "$DEVICE" shell dpm set-active-admin "$ADMIN_RECEIVER" 2>/dev/null && \
    echo "  ✅ Device Admin activado" || echo "  ⚠️  Device Admin ya activo o falló"

# ── 5. Device Owner ─────────────────────────────────────────────────────
echo "[5/6] Device Owner..."
adb -s "$DEVICE" shell dpm set-device-owner "$ADMIN_RECEIVER" 2>/dev/null && \
    echo "  ✅ Device Owner configurado" || echo "  ⚠️  Device Owner no disponible (requiere factory reset sin cuentas)"

# ── 6. Batería y Background ─────────────────────────────────────────────
echo "[6/6] Optimización de batería..."
adb -s "$DEVICE" shell dumpsys deviceidle whitelist +"$PKG" 2>/dev/null
adb -s "$DEVICE" shell cmd deviceidle tempwhitelist "$PKG" 2>/dev/null || true
echo "  ✅ Whitelist de batería configurada"

echo "============================================================"
echo "Configuración de permisos completada."
echo ""
echo "Verificar con:"
echo "  adb -s $DEVICE shell appops get $PKG"
echo "  adb -s $DEVICE shell dumpsys device_policy | grep 'Device Owner'"
```

---

## 8. Verificación

### Comprobación rápida manual

```bash
# 1. ¿Está instalado?
adb shell pm list packages | grep com.zoho.assist

# 2. ¿Accesibilidad activa?
adb shell settings get secure enabled_accessibility_services

# 3. ¿Todos los appops en 'allow'?
adb shell appops get com.zoho.assist | grep -E "SYSTEM_ALERT_WINDOW|PROJECT_MEDIA"

# 4. ¿Whitelist de batería?
adb shell dumpsys deviceidle whitelist | grep com.zoho.assist

# 5. ¿Device Owner?
adb shell dumpsys device_policy | grep -A 5 "Device Owner"
```

### Posibles estados de permisos y su significado

| Estado | Significado |
|---|---|
| `allow` | Permiso concedido, sin confirmaciones |
| `deny` | Permiso denegado — se mostrará diálogo |
| `default` | No configurado — Android pedirá confirmación |
| `ignore` | La app no tiene este permiso en su manifiesto |

---

## Notas Importantes

1. **Factory reset para Device Owner**: Si el dispositivo ya tiene cuentas configuradas, Device Owner no se puede activar sin factory reset.

2. **Actualizaciones de la app**: Tras cada actualización, algunos permisos AppOps pueden resetearse. El script `auto_updater.sh` los restaura automáticamente.

3. **Android 14+**: `PROJECT_MEDIA` fue reemplazado por permisos más granulares. Considerar `MANAGE_MEDIA_PROJECTION` si el APK lo soporta.

4. **Seguridad**: Conceder Device Owner otorga control total del dispositivo. Solo usar en TPVs dedicados sin datos sensibles de usuario final.
