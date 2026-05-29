@echo off
setlocal enabledelayedexpansion

set "ADB=adb"
set "MANAGER_APK=%~dp0..\releases\zoho_tpv_manager.apk"
set "CONFIG_FILE=%~dp0zoho_tpv_config.json"
set "MANAGER_PACKAGE=com.tpv.zoho.manager"
set "ADMIN_COMPONENT=com.tpv.zoho.manager/.receiver.DeviceAdminReceiver"

echo ============================================================
echo   Zoho TPV Manager - Device Owner setup
echo ============================================================
echo.

%ADB% version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] adb no esta en PATH. Usa C:\Android\platform-tools o Android SDK Platform Tools.
    exit /b 1
)

for /f "skip=1 tokens=1" %%d in ('%ADB% devices') do (
    if not "%%d"=="" (
        set "DEVICE=%%d"
        goto :device_found
    )
)

echo [ERROR] No hay dispositivo conectado por ADB.
exit /b 1

:device_found
echo [OK] Dispositivo: %DEVICE%

if not exist "%MANAGER_APK%" (
    echo [ERROR] No existe %MANAGER_APK%
    exit /b 1
)

echo [INFO] Instalando gestor TPV...
%ADB% -s %DEVICE% install -r "%MANAGER_APK%"
if errorlevel 1 exit /b 1

if exist "%CONFIG_FILE%" (
    echo [INFO] Copiando configuracion...
    %ADB% -s %DEVICE% push "%CONFIG_FILE%" /sdcard/zoho_tpv_config.json
)

echo [INFO] Configurando Device Owner...
echo       Esto solo funciona si el dispositivo no tiene cuentas/owner previo.
%ADB% -s %DEVICE% shell dpm set-device-owner "%ADMIN_COMPONENT%"
if errorlevel 1 (
    echo [WARN] No se pudo activar Device Owner.
    echo        Para instalacion desatendida, restablece el TPV de fabrica o usa MDM/QR provisioning.
    echo        Sin Device Owner, Android pedira confirmacion manual.
    exit /b 2
)

echo [OK] Device Owner activado.
echo [INFO] Abriendo Zoho TPV Manager...
%ADB% -s %DEVICE% shell monkey -p %MANAGER_PACKAGE% -c android.intent.category.LAUNCHER 1 >nul

echo.
echo Listo. Al pulsar "INSTALAR ZOHO ASSIST", el gestor descargara el APK
echo definido en zoho_tpv_config.json y lo instalara en segundo plano.
exit /b 0
