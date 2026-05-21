# Zoho TPV Manager

**Gestor de despliegue empresarial para Zoho Assist en terminales TPV Android.**

Compilado con herramientas reales de Android SDK (aapt2, javac, d8, apksigner).

## Estructura

```
zoho-tpv-manager/
├── android/                  # Proyecto Android (Gradle + Java)
│   ├── app/src/main/java/    # 18 clases Java
│   ├── app/src/main/res/     # Layouts, strings, XML configs
│   ├── build.gradle.kts      # Config de compilación
│   └── compilar_apk.bat      # Script de build automático
├── deployment/               # Scripts de instalación masiva
│   ├── install_zoho.bat      # Windows
│   ├── install_zoho.sh       # Linux/macOS
│   ├── auto_updater.sh       # Auto-actualización
│   ├── device_manager.sh     # Gestión centralizada
│   ├── zoho_tpv_config.json  # Configuración JSON
│   ├── deployment_guide.md   # Documentación técnica
│   ├── checklist_verificacion.md  # 10 puntos verificación
│   └── permisos_adb_guide.md     # Permisos ADB
└── releases/                 # APKs compilados
    └── zoho_tpv_manager.apk
```

## Características

- **Instalación automática**: Busca `zoho_assist.apk` en Descargas y lo instala
- **Auto-actualización**: Verifica y descarga nuevas versiones desde repositorio privado
- **Control remoto**: AccessibilityService + DeviceAdmin para sesiones sin confirmaciones
- **Screen sharing**: MediaProjection para compartir pantalla
- **Gestión TPV**: Health checks, inventario, alertas de batería
- **Deployment masivo**: Scripts para instalar en N dispositivos vía ADB

## Compilación

```batch
cd android
compilar_apk.bat
```

Requiere: JDK 17 + Android SDK (build-tools 34.0.0, platform 34)

## Instalación rápida

1. Instala `zoho_tpv_manager.apk` en el TPV
2. Coloca `zoho_assist.apk` en la carpeta Descargas
3. Abre la app y pulsa "Instalar Zoho Assist"

## Deployment masivo

```bash
cd deployment
./install_zoho.sh          # Linux/macOS
install_zoho.bat           # Windows
```

## Licencia

Uso interno empresarial. Zoho Assist es marca registrada de Zoho Corporation.
