@echo off
setlocal enabledelayedexpansion

set "ADB=adb"
set "XAPK_DIR=%~dp0..\update-server\apks\zoho_assist_xapk"
set "PACKAGE=com.zoho.assist.agent"

echo ============================================================
echo   Zoho Assist Customer - Instalacion XAPK por ADB
echo ============================================================
echo.

%ADB% version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] adb no esta en PATH.
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

if not exist "%XAPK_DIR%\com.zoho.assist.agent.apk" (
    echo [ERROR] No encuentro el XAPK extraido en:
    echo        %XAPK_DIR%
    exit /b 1
)

echo [INFO] Instalando Zoho Assist Customer con splits...
%ADB% -s %DEVICE% install-multiple -r ^
    "%XAPK_DIR%\com.zoho.assist.agent.apk" ^
    "%XAPK_DIR%\config.armeabi_v7a.apk" ^
    "%XAPK_DIR%\config.en.apk" ^
    "%XAPK_DIR%\config.es.apk" ^
    "%XAPK_DIR%\config.mdpi.apk"

if errorlevel 1 (
    echo [ERROR] Fallo la instalacion.
    exit /b 1
)

echo [OK] Instalado. Verificando version...
%ADB% -s %DEVICE% shell dumpsys package %PACKAGE% | findstr /i "versionName versionCode"

echo [INFO] Abriendo Zoho Assist...
%ADB% -s %DEVICE% shell monkey -p %PACKAGE% -c android.intent.category.LAUNCHER 1 >nul

echo [OK] Listo.
exit /b 0
