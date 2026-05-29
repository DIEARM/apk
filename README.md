# Zoho TPV Manager

**Gestor de despliegue empresarial para Zoho Assist en terminales TPV Android.**

Compilado con herramientas reales de Android SDK (aapt2, javac, d8, apksigner).

---

## Estructura

```
zoho-tpv-manager/
├── android/                       # Proyecto Android (Gradle + Java)
│   ├── app/src/main/java/         # 18 clases Java
│   ├── app/src/main/res/          # Layouts, strings, XML configs
│   ├── build.gradle.kts           # Config de compilación
│   ├── compilar_apk.bat           # Script de build automático
│   └── zoho_tpv_manager_signed.apk
├── deployment/                    # Scripts de instalación masiva
│   ├── install_zoho.bat           # Instalador Windows
│   ├── install_zoho.sh            # Instalador Linux/macOS
│   ├── auto_updater.sh            # Auto-actualización desde repo
│   ├── device_manager.sh          # Gestión centralizada dispositivos
│   ├── zoho_verify.sh             # Verificación 10 puntos (bash)
│   ├── zoho_verify.ps1            # Verificación 10 puntos (PowerShell)
│   ├── zoho_tpv_config.json       # Configuración centralizada
│   ├── deployment_guide.md        # Documentación técnica
│   ├── checklist_verificacion.md  # Checklist detallado
│   └── permisos_adb_guide.md      # Guía permisos ADB
├── update-server/                 # Servidor de actualizaciones
│   ├── server.py                  # Servidor HTTP (Python stdlib)
│   ├── Dockerfile                 # Imagen Docker
│   ├── docker-compose.yml         # Orquestación
│   ├── requirements.txt           # Dependencias (ninguna)
│   └── apks/                      # Directorio de APKs servidos
└── releases/                      # APKs compilados
    └── zoho_tpv_manager.apk
```

---

## Características

- **Instalación automática**: Busca `zoho_assist.apk` en Descargas y lo instala
- **Auto-actualización**: Verifica y descarga nuevas versiones desde repositorio privado
- **Control remoto**: AccessibilityService + DeviceAdmin para sesiones sin confirmaciones
- **Screen sharing**: MediaProjection para compartir pantalla
- **Gestión TPV**: Health checks, inventario, alertas de batería
- **Deployment masivo**: Scripts para instalar en N dispositivos vía ADB
- **Servidor de updates**: Servidor HTTP ligero para distribuir APKs y manifiestos

---

## Flujo completo

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  update-server/  │────▶│  deployment/      │────▶│  Dispositivo TPV │
│  (Python HTTP)   │     │  auto_updater.sh  │     │  Android          │
│                  │     │  install_zoho.sh  │     │                   │
│  GET /manifest   │     │  zoho_verify.sh   │     │  Zoho Assist APK  │
│  GET /apk        │     └──────────────────┘     └─────────────────┘
│  POST /upload    │
└─────────────────┘
```

1. **Subir APK** al servidor: `curl -F "apk=@zoho_assist.apk" http://server:8080/upload`
2. **Desplegar en TPV**: `./deployment/install_zoho.sh`
3. **Verificar**: `./deployment/zoho_verify.sh`
4. **Actualizar automáticamente**: el `auto_updater.sh` consulta `/manifest.json` cada 6h

---

## Servidor de actualizaciones

### Inicio rápido

```bash
cd update-server

# Opción A: Python directo
python server.py
# → http://localhost:8080

# Opción B: Docker
docker compose up -d
# → http://localhost:8080
```

### Endpoints

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/health` | Health check |
| GET | `/zoho/stable/manifest.json` | Metadatos de la última versión |
| GET | `/zoho/stable/zoho_assist.apk` | Descarga del APK |
| POST | `/upload` | Subir nueva versión (multipart) |

### Subir una nueva versión

```bash
# Linux/macOS
curl -F "apk=@zoho_assist.apk" http://localhost:8080/upload

# Windows PowerShell
Invoke-RestMethod -Uri http://localhost:8080/upload -Method Post -Form @{apk=Get-Item zoho_assist.apk}
```

El servidor guarda el APK en `apks/`, calcula el MD5, y regenera `manifest.json`.

---

## Compilación del APK

```batch
cd android
compilar_apk.bat
```

Requiere: JDK 17 + Android SDK (build-tools 34.0.0, platform 34)

---

## Instalación rápida en TPV

1. Instala `zoho_tpv_manager.apk` en el TPV
2. Coloca `zoho_assist.apk` en la carpeta Descargas
3. Abre la app y pulsa "Instalar Zoho Assist"

---

## Deployment masivo

```bash
cd deployment

# Linux/macOS
chmod +x install_zoho.sh auto_updater.sh zoho_verify.sh device_manager.sh
./install_zoho.sh

# Windows
install_zoho.bat
```

### Verificación post-instalación

```bash
# Linux/macOS
./zoho_verify.sh

# Windows PowerShell
.\zoho_verify.ps1
```

Salida esperada: `10/10 aprobados` → ✅ listo para producción.

---

## Personalización

Edita `deployment/zoho_tpv_config.json` con los datos de tu empresa:

- `organization.name`, `organization.id`
- `zoho_assist.unattended_access_key`
- `update_repository.base_url` → URL de tu servidor de updates
- `device_management.enrollment_token`
- `security.trusted_certificates_sha256`

---

## Licencia

Uso interno empresarial. Zoho Assist es marca registrada de Zoho Corporation.
