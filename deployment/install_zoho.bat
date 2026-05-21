@echo off
REM ============================================================================
REM  Zoho Assist TPV Deployment Script - Windows
REM  Instalacion automatizada para entornos TPV Android sin Play Store
REM  Version: 1.0.0 | Fecha: 2026-05-21
REM ============================================================================
setlocal enabledelayedexpansion

:: ── Configuracion ──────────────────────────────────────────────────────────
set "CONFIG_FILE=zoho_tpv_config.json"
set "APK_URL=https://repo-empresarial.example.com/zoho/assist/latest.apk"
set "APK_LOCAL=%~dp0zoho_assist.apk"
set "MD5_EXPECTED="
set "ADB=adb"
set "LOG_FILE=%~dp0install_%date:~-4,4%%date:~-7,2%%date:~-10,2%_%time:~0,2%%time:~3,2%%time:~6,2%.log"
set "LOG_FILE=%LOG_FILE: =0%"

:: ── Banner ─────────────────────────────────────────────────────────────────
echo ============================================================
echo   Zoho Assist - Instalador TPV Empresarial v1.0.0
echo   %date% %time%
echo ============================================================
echo.

:: ── Verificar ADB ──────────────────────────────────────────────────────────
call :log "INFO" "Verificando ADB..."
%ADB% version >nul 2>&1
if errorlevel 1 (
    call :log "ERROR" "ADB no encontrado. Instale Android SDK Platform Tools."
    echo [ERROR] ADB no encontrado en PATH.
    echo Descargue: https://developer.android.com/studio/releases/platform-tools
    pause
    exit /b 1
)
call :log "OK" "ADB detectado correctamente."

:: ── Detectar dispositivos ──────────────────────────────────────────────────
call :log "INFO" "Buscando dispositivos Android conectados..."
for /f "skip=1 tokens=1" %%d in ('%ADB% devices') do (
    if not "%%d"=="" (
        if not "%%d"=="List" (
            set "DEVICE=%%d"
            goto :device_found
        )
    )
)

echo [ERROR] No se detecto ningun dispositivo Android.
echo Conecte el dispositivo via USB y asegurese de que:
echo   1. Depuracion USB esta habilitada
echo   2. El dispositivo esta desbloqueado
echo   3. Acepto la huella RSA en la pantalla del dispositivo
pause
exit /b 1

:device_found
call :log "OK" "Dispositivo detectado: %DEVICE%"

:: ── Verificar conexion ─────────────────────────────────────────────────────
call :log "INFO" "Verificando conexion con el dispositivo..."
%ADB% -s %DEVICE% shell echo "connected" >nul 2>&1
if errorlevel 1 (
    call :log "ERROR" "No se pudo establecer conexion con %DEVICE%"
    pause
    exit /b 1
)
call :log "OK" "Conexion establecida."

:: ── Obtener info del dispositivo ───────────────────────────────────────────
call :log "INFO" "Recopilando informacion del dispositivo..."
for /f "delims=" %%i in ('%ADB% -s %DEVICE% shell getprop ro.product.manufacturer') do set "MANUFACTURER=%%i"
for /f "delims=" %%i in ('%ADB% -s %DEVICE% shell getprop ro.product.model') do set "MODEL=%%i"
for /f "delims=" %%i in ('%ADB% -s %DEVICE% shell getprop ro.build.version.release') do set "ANDROID_VER=%%i"
for /f "delims=" %%i in ('%ADB% -s %DEVICE% shell getprop ro.build.version.sdk') do set "SDK=%%i"

echo   Fabricante : %MANUFACTURER%
echo   Modelo     : %MODEL%
echo   Android    : %ANDROID_VER% (SDK %SDK%)
call :log "INFO" "Dispositivo: %MANUFACTURER% %MODEL% | Android %ANDROID_VER% (SDK %SDK%)"

:: ── Verificar SDK minimo ───────────────────────────────────────────────────
if %SDK% LSS 24 (
    call :log "ERROR" "SDK %SDK% no compatible. Se requiere Android 7.0 (SDK 24) o superior."
    pause
    exit /b 1
)

:: ── Descargar/Copiar APK ──────────────────────────────────────────────────
call :log "INFO" "Preparando APK de Zoho Assist..."
if exist "%APK_LOCAL%" (
    call :log "INFO" "APK local encontrado: %APK_LOCAL%"

    :: Verificar MD5 del APK local
    if not "%MD5_EXPECTED%"=="" (
        call :log "INFO" "Verificando integridad del APK (MD5)..."
        for /f "delims=" %%h in ('certutil -hashfile "%APK_LOCAL%" MD5 ^| findstr /v ":" ^| findstr /v "^$"') do set "MD5_ACTUAL=%%h"
        set "MD5_ACTUAL=!MD5_ACTUAL: =!"

        if /i not "!MD5_ACTUAL!"=="%MD5_EXPECTED%" (
            call :log "ERROR" "MD5 mismatch! Esperado: %MD5_EXPECTED% | Obtenido: !MD5_ACTUAL!"
            echo [ERROR] Fallo la verificacion de integridad del APK.
            pause
            exit /b 1
        )
        call :log "OK" "MD5 verificado correctamente."
    )
) else (
    call :log "INFO" "APK local no encontrado. Descargando desde repositorio..."
    echo Descargando APK desde: %APK_URL%
    powershell -Command "& {Invoke-WebRequest -Uri '%APK_URL%' -OutFile '%APK_LOCAL%'}" 2>nul
    if errorlevel 1 (
        :: Fallback a curl
        curl -L -o "%APK_LOCAL%" "%APK_URL%" 2>nul
        if errorlevel 1 (
            call :log "ERROR" "No se pudo descargar el APK. Verifique la URL o coloque el APK manualmente."
            echo [ERROR] Descarga fallida. Coloque zoho_assist.apk en el mismo directorio que este script.
            pause
            exit /b 1
        )
    )
    call :log "OK" "APK descargado correctamente."
)

:: ── Desinstalar version anterior (si existe) ───────────────────────────────
call :log "INFO" "Verificando instalaciones previas..."
%ADB% -s %DEVICE% shell pm list packages com.zoho.assist >nul 2>&1
if not errorlevel 1 (
    call :log "INFO" "Zoho Assist ya instalado. Desinstalando version anterior..."
    %ADB% -s %DEVICE% uninstall com.zoho.assist
    call :log "OK" "Version anterior desinstalada."
)

:: ── Instalar APK ───────────────────────────────────────────────────────────
call :log "INFO" "Instalando Zoho Assist en %DEVICE%..."
%ADB% -s %DEVICE% install -r -d "%APK_LOCAL%"
if errorlevel 1 (
    call :log "ERROR" "Fallo la instalacion del APK."
    echo [ERROR] Instalacion fallida. Verifique:
    echo   - Espacio disponible en el dispositivo
    echo   - Compatibilidad de arquitectura (arm64-v8a / armeabi-v7a)
    echo   - Permisos de instalacion desde fuentes desconocidas
    pause
    exit /b 1
)
call :log "OK" "Zoho Assist instalado correctamente."

:: ── Conceder permisos especiales ───────────────────────────────────────────
call :log "INFO" "Configurando permisos especiales para control remoto..."
echo Concediendo permisos (esto puede tomar unos segundos)...

:: Permisos de accesibilidad (necesario para control remoto)
%ADB% -s %DEVICE% shell settings put secure enabled_accessibility_services com.zoho.assist/com.zoho.assist.service.AssistAccessibilityService
%ADB% -s %DEVICE% shell settings put secure accessibility_enabled 1

:: Permiso de overlay (screen sharing)
%ADB% -s %DEVICE% shell appops set com.zoho.assist SYSTEM_ALERT_WINDOW allow

:: Permiso de captura de pantalla
%ADB% -s %DEVICE% shell appops set com.zoho.assist PROJECT_MEDIA allow

:: Permiso de notificaciones
%ADB% -s %DEVICE% shell appops set com.zoho.assist POST_NOTIFICATIONS allow

:: Permisos runtime via ADB
for %%p in (
    android.permission.CAMERA
    android.permission.RECORD_AUDIO
    android.permission.ACCESS_FINE_LOCATION
    android.permission.READ_EXTERNAL_STORAGE
    android.permission.WRITE_EXTERNAL_STORAGE
    android.permission.READ_PHONE_STATE
    android.permission.SYSTEM_ALERT_WINDOW
    android.permission.WRITE_SETTINGS
    android.permission.PACKAGE_USAGE_STATS
    android.permission.BIND_ACCESSIBILITY_SERVICE
    android.permission.BIND_DEVICE_ADMIN
) do (
    %ADB% -s %DEVICE% shell pm grant com.zoho.assist %%p 2>nul
)

:: Permiso de Device Admin (evita confirmaciones en control remoto)
%ADB% -s %DEVICE% shell dpm set-device-owner com.zoho.assist/.receiver.DeviceAdminReceiver 2>nul
if errorlevel 1 (
    call :log "WARN" "Device Admin no se pudo configurar (posiblemente ya hay otro Device Owner)."
    echo [WARN] Device Admin omitido. Algunas confirmaciones podrian persistir.
)

:: Deshabilitar optimizacion de bateria para Zoho Assist
%ADB% -s %DEVICE% shell dumpsys deviceidle whitelist +com.zoho.assist 2>nul

call :log "OK" "Permisos configurados."

:: ── Push de configuracion JSON ─────────────────────────────────────────────
if exist "%CONFIG_FILE%" (
    call :log "INFO" "Desplegando archivo de configuracion..."
    %ADB% -s %DEVICE% push "%CONFIG_FILE%" /sdcard/zoho_tpv_config.json
    call :log "OK" "Configuracion desplegada en /sdcard/zoho_tpv_config.json"
) else (
    call :log "WARN" "Archivo de configuracion no encontrado: %CONFIG_FILE%"
)

:: ── Push de script de auto-actualizacion ───────────────────────────────────
if exist "auto_updater.sh" (
    call :log "INFO" "Desplegando script de auto-actualizacion..."
    %ADB% -s %DEVICE% push "auto_updater.sh" /sdcard/zoho_auto_updater.sh
    call :log "OK" "Script de actualizacion desplegado."
)

:: ── Iniciar aplicacion ─────────────────────────────────────────────────────
call :log "INFO" "Iniciando Zoho Assist..."
%ADB% -s %DEVICE% shell monkey -p com.zoho.assist -c android.intent.category.LAUNCHER 1 >nul 2>&1
call :log "OK" "Zoho Assist iniciado."

:: ── Verificar instalacion ──────────────────────────────────────────────────
call :log "INFO" "Verificando instalacion..."

:: Verificar que el paquete existe
%ADB% -s %DEVICE% shell pm list packages com.zoho.assist | findstr "com.zoho.assist" >nul
if errorlevel 1 (
    call :log "ERROR" "Verificacion fallida: paquete no encontrado."
    pause
    exit /b 1
)

:: Verificar version instalada
for /f "delims=" %%v in ('%ADB% -s %DEVICE% shell dumpsys package com.zoho.assist ^| findstr "versionName"') do set "VERSION=%%v"
call :log "OK" "Instalacion verificada. %VERSION%"

:: ── Resumen ────────────────────────────────────────────────────────────────
echo.
echo ============================================================
echo   INSTALACION COMPLETADA EXITOSAMENTE
echo ============================================================
echo   Dispositivo : %MANUFACTURER% %MODEL%
echo   Android     : %ANDROID_VER%
echo   Zoho Assist : Instalado y configurado
echo   Log         : %LOG_FILE%
echo ============================================================
echo.
call :log "OK" "Instalacion completada exitosamente."
pause
exit /b 0

:: ── Funcion de log ─────────────────────────────────────────────────────────
:log
set "level=%~1"
set "message=%~2"
set "timestamp=%date% %time%"
echo [%timestamp%] [%level%] %message% >> "%LOG_FILE%"
echo [%level%] %message%
exit /b 0
