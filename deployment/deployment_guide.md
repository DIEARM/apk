# Zoho Assist — Documentación Técnica de Deployment Masivo TPV

**Versión:** 1.0.0  
**Fecha:** 2026-05-21  
**Audiencia:** Equipo de Infraestructura / Soporte Técnico N2-N3  

---

## 1. Arquitectura de Deployment

```
┌──────────────────────────────────────────────────────────┐
│                 ESTACIÓN DE DEPLOYMENT                    │
│  (Windows/Linux/macOS con ADB + Scripts)                 │
│                                                          │
│  install_zoho.bat / install_zoho.sh                      │
│  auto_updater.sh                                         │
│  device_manager.sh                                       │
│  zoho_tpv_config.json                                    │
│  zoho_assist.apk (colocado manualmente o descargado)     │
└──────────────┬───────────────────────────────────────────┘
               │ USB (ADB)
               ▼
┌──────────────────────────────────────────────────────────┐
│              DISPOSITIVO TPV ANDROID                      │
│                                                          │
│  ┌──────────────────────────────────────────────────┐    │
│  │ Zoho Assist APK (com.zoho.assist)                │    │
│  │  ├── Accessibility Service (control remoto)      │    │
│  │  ├── Screen Capture Service (screen sharing)     │    │
│  │  ├── File Transfer Service                       │    │
│  │  └── Device Admin Receiver (gestión)             │    │
│  └──────────────────────────────────────────────────┘    │
│  /sdcard/zoho_tpv_config.json                            │
│  /sdcard/zoho_auto_updater.sh                            │
└──────────────────────────────────────────────────────────┘
```

### Componentes

| Componente | Archivo | Función |
|---|---|---|
| Instalador | `install_zoho.bat` / `.sh` | Instalación automatizada completa vía ADB |
| Auto-Updater | `auto_updater.sh` | Verifica y descarga actualizaciones desde repo privado |
| Configuración | `zoho_tpv_config.json` | Parámetros centralizados para todos los TPV |
| Gestor MDM | `device_manager.sh` | Inventario, health check, comandos remotos |

---

## 2. Prerrequisitos

### 2.1 En la estación de deployment

- **ADB (Android Debug Bridge)** — Platform Tools r34.0+
  - Descarga: https://developer.android.com/studio/releases/platform-tools
- **Windows**: PowerShell 5.1+ o curl
- **Linux/macOS**: bash 4.0+, curl o wget
- **Opcional**: `jq` para procesamiento avanzado de JSON

### 2.2 En cada dispositivo TPV Android

- Android 7.0 (API 24) o superior
- **Depuración USB** habilitada (Ajustes → Opciones de desarrollador)
- **Instalar desde fuentes desconocidas** habilitado
- Pantalla desbloqueada durante la instalación
- Sin cuentas de Google configuradas (para Device Admin)
- Espacio libre: mínimo 100 MB

### 2.3 Infraestructura de red

- Repositorio privado HTTPS accesible desde la estación de deployment:
  ```
  https://repo-empresarial.example.com/zoho/
  ├── stable/
  │   ├── manifest.json       # Metadatos de versión
  │   └── zoho_assist.apk     # Última versión estable
  ├── beta/
  │   └── ...
  └── archives/
      └── v1.0.0/
          └── zoho_assist.apk
  ```

### Formato de `manifest.json`

```json
{
  "version": "4.2.1",
  "version_code": 42100,
  "release_date": "2026-05-15",
  "apk_url": "https://repo-empresarial.example.com/zoho/stable/zoho_assist.apk",
  "md5": "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6",
  "min_sdk": 24,
  "changelog": "Corrección de bugs y mejoras de estabilidad."
}
```

---

## 3. Procedimiento de Deployment Masivo

### 3.1 Preparación única (una vez)

```bash
# Clonar o copiar el paquete de deployment
mkdir -p ~/zoho-tpv-deployment
cp install_zoho.sh auto_updater.sh device_manager.sh zoho_tpv_config.json ~/zoho-tpv-deployment/
cd ~/zoho-tpv-deployment

# Editar configuración con datos de la empresa
nano zoho_tpv_config.json
# Rellenar: organization.name, organization.id, zoho_assist.unattended_access_key,
#           update_repository.base_url, device_management.enrollment_token...
```

### 3.2 Por cada dispositivo TPV

```bash
# 1. Conectar dispositivo vía USB
# 2. Verificar que ADB lo detecta
adb devices

# 3. Ejecutar instalación
# Linux/macOS:
chmod +x install_zoho.sh
./install_zoho.sh
# Windows:
install_zoho.bat

# 4. Verificar instalación (ver checklist más abajo)

# 5. Desconectar y etiquetar dispositivo
```

### 3.3 Deployment paralelo (múltiples dispositivos)

```bash
# Conectar N dispositivos simultáneamente vía hub USB
# El script detectará múltiples dispositivos y preguntará cuál instalar.

# Para automatizar 100%:
for device in $(adb devices | tail -n +2 | awk '{print $1}'); do
    echo "Instalando en $device..."
    DEVICE_SERIAL=$device ./install_zoho.sh
done
```

---

## 4. Auto-Actualización

### 4.1 Flujo

```
┌──────────┐     ┌──────────────┐     ┌──────────────┐
│ CRON/Task │────▶│ auto_updater │────▶│  Repo HTTPS  │
│ Scheduler │     │   .sh        │     │  (manifest)  │
└──────────┘     └──────┬───────┘     └──────────────┘
                        │
                   ┌────▼────┐     ┌──────────┐
                   │ ¿Nueva  │────▶│ Descargar │
                   │ versión?│ No  │   APK     │
                   └────┬────┘     └─────┬─────┘
                        │ Sí             │
                        ▼                ▼
                   ┌──────────┐     ┌──────────┐
                   │ Backup   │     │ Instalar │
                   │ actual   │     │ + permisos│
                   └──────────┘     └──────────┘
```

### 4.2 Programación

**Linux/macOS (crontab):**
```bash
# Verificar actualizaciones cada 6 horas
0 */6 * * * /ruta/deployment/auto_updater.sh >> /var/log/zoho_updater.log 2>&1
```

**Windows (Task Scheduler):**
```powershell
# Crear tarea programada
schtasks /create /tn "ZohoAssistUpdater" /tr "C:\deployment\auto_updater.sh" /sc daily /st 02:00
```

### 4.3 Rollback

```bash
# Si una actualización falla, el script hace rollback automático.
# Para rollback manual:
./auto_updater.sh --rollback
```

---

## 5. Gestión Centralizada de Dispositivos

### 5.1 Inventario

```bash
# Listar todos los dispositivos conectados con estado
./device_manager.sh --inventory

# Output:
# ┌──────────────────────┬──────────────────┬──────────┬──────────────┬──────────────┐
# │ Serial               │ Modelo           │ Android   │ Zoho Version │ Conectividad │
# ├──────────────────────┼──────────────────┼──────────┼──────────────┼──────────────┤
# │ ABC123               │ TPV-SUNMI-V2     │ 9 (SDK28)│ 4.2.1        │ WiFi OK      │
# │ DEF456               │ PAX-A920         │ 10(SDK29)│ 4.2.0        │ WiFi OK      │
# └──────────────────────┴──────────────────┴──────────┴──────────────┴──────────────┘
```

### 5.2 Health Check

```bash
./device_manager.sh --health-check
# Verifica: batería, espacio, conectividad, servicio Zoho corriendo, permisos
```

### 5.3 Comandos remotos vía ADB TCP/IP

```bash
# Habilitar ADB sobre WiFi (una vez vía USB)
./device_manager.sh --enable-wifi-adb

# Luego todos los comandos funcionan sin USB:
./device_manager.sh --health-check --ip 192.168.1.100
```

---

## 6. Permisos Especiales

Ver documento **[permisos_adb_guide.md](./permisos_adb_guide.md)** para detalle completo de cada permiso y su justificación.

Resumen de permisos críticos concedidos por el instalador:

| Permiso | Motivo |
|---|---|
| `BIND_ACCESSIBILITY_SERVICE` | Control remoto táctil/clicks |
| `SYSTEM_ALERT_WINDOW` | Overlay para screen sharing |
| `PROJECT_MEDIA` | Captura de pantalla |
| `WRITE_SETTINGS` | Ajustes del sistema |
| `PACKAGE_USAGE_STATS` | Monitoreo de apps TPV |
| `BIND_DEVICE_ADMIN` | Evitar confirmaciones |

---

## 7. Optimización para Dispositivos de Bajos Recursos

### Parámetros en `zoho_tpv_config.json`

```json
{
  "performance": {
    "max_memory_usage_mb": 128,
    "max_cpu_percent": 30,
    "screen_sharing_max_fps": 10,
    "screen_compression_quality": 60,
    "min_bitrate_kbps": 50,
    "max_bitrate_kbps": 500
  }
}
```

### Configuraciones recomendadas por tipo de TPV

| Hardware | screen_sharing_max_fps | max_bitrate_kbps | max_memory_usage_mb |
|---|---|---|---|
| SUNMI V2 (1GB RAM) | 8 | 300 | 64 |
| PAX A920 (2GB RAM) | 12 | 800 | 128 |
| Wiseasy W2 (1GB RAM) | 8 | 250 | 64 |
| Gamer520 (1GB RAM) | 6 | 200 | 48 |

---

## 8. Solución de Problemas

### Error: "ADB no encontrado"
```bash
# Verificar PATH
which adb          # Linux/macOS
where adb          # Windows
# Añadir al PATH o instalar Platform Tools
```

### Error: "No se detecto ningun dispositivo"
1. Verificar cable USB (datos, no solo carga)
2. Verificar depuración USB habilitada
3. `adb kill-server && adb start-server`
4. Aceptar huella RSA en pantalla del dispositivo
5. Probar otro puerto USB

### Error: "INSTALL_FAILED_INSUFFICIENT_STORAGE"
```bash
# Liberar espacio
adb shell pm clear com.zoho.assist
adb shell pm uninstall -k --user 0 <paquetes_innecesarios>
```

### Error: "Device Admin no se pudo configurar"
```bash
# Eliminar cuentas existentes
adb shell pm list users
adb shell pm remove-user <user_id>  # Solo si es seguro

# O verificar si ya hay un Device Owner
adb shell dumpsys device_policy
```

### El servicio Zoho se detiene solo
```bash
# Verificar optimización de batería
adb shell dumpsys deviceidle whitelist +com.zoho.assist
adb shell cmd deviceidle tempwhitelist com.zoho.assist

# Forzar servicio foreground
adb shell am start-foreground-service com.zoho.assist/.service.RemoteService
```

---

## 9. Seguridad

- **APK firmado oficialmente** — No usar APKs de fuentes no verificadas
- **HTTPS obligatorio** para todas las comunicaciones con el repositorio
- **Certificate pinning** habilitado en configuración
- **Checksums MD5** verificados en cada descarga
- **Logs anonimizados** (`anonymize_pii: true`)
- **Grabación de sesiones** retenida 90 días por compliance

---

## 10. Apéndice: Checklist Rápido de Deployment

Ver **[checklist_verificacion.md](./checklist_verificacion.md)** para la lista de 10 puntos de verificación post-instalación.

---

## 11. Contacto y Soporte

- **Equipo de Infraestructura TPV**: soporte@empresa.com
- **Zoho Assist Admin Console**: https://assist.zoho.com
- **Documentación oficial Zoho**: https://help.zoho.com/portal/en/kb/assist
