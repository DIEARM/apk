@echo off
chcp 65001 >nul
title Zoho TPV Manager — Compilacion
cd /d "%~dp0"

echo.
echo ============================================================
echo   Zoho TPV Manager - Compilacion manual
echo ============================================================
echo.

:: ── 1. Verificar Java ──
echo [1] Verificando Java...
javac -version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Java no encontrado. Instala JDK 17+:
    echo https://adoptium.net/download/
    pause
    exit /b 1
)
echo [OK] Java detectado

:: ── 2. Configurar Android SDK ──
echo.
echo [2] Configurando Android SDK...

:: Buscar SDK en ubicaciones comunes
if exist "%ANDROID_HOME%\build-tools" goto :sdk_ok
if exist "%LOCALAPPDATA%\Android\Sdk\build-tools" (
    set ANDROID_HOME=%LOCALAPPDATA%\Android\Sdk
    goto :sdk_ok
)
if exist "C:\Android\Sdk\build-tools" (
    set ANDROID_HOME=C:\Android\Sdk
    goto :sdk_ok
)

echo [ERROR] Android SDK no encontrado.
echo.
echo Instalalo desde: https://developer.android.com/studio
echo O descarga solo las command-line tools:
echo https://developer.android.com/studio#command-line-tools-only
echo.
echo Despues de instalarlo, asegurate de tener:
echo   - build-tools 34.0.0
echo   - platform android-34
echo.
pause
exit /b 1

:sdk_ok
echo [OK] ANDROID_HOME=%ANDROID_HOME%

:: ── 3. Buscar build-tools ──
echo.
echo [3] Buscando build-tools...
for /d %%d in ("%ANDROID_HOME%\build-tools\*") do set BT=%%d
if not exist "%BT%\aapt2.exe" (
    echo [ERROR] build-tools no encontrado.
    echo Instala build-tools 34.0.0 desde Android Studio SDK Manager.
    pause
    exit /b 1
)
echo [OK] Build-tools: %BT%

:: ── 4. Plataforma ──
set PLATFORM=%ANDROID_HOME%\platforms\android-34\android.jar
if not exist "%PLATFORM%" (
    echo [ERROR] android-34 platform no encontrado.
    pause
    exit /b 1
)
echo [OK] Platform: android-34

:: ── 5. Compilar ──
echo.
echo [4] Compilando...

set SRC=app\src\main\java
set RES=app\src\main\res
set MANIFEST=app\src\main\AndroidManifest.xml
set OUT=build\manual
set GEN=%OUT%\gen
set CLASSES=%OUT%\classes

rmdir /s /q "%OUT%" 2>nul
mkdir "%GEN%" 2>nul
mkdir "%CLASSES%" 2>nul

:: Compilar recursos
echo   - aapt2 compile...
for /r "%RES%" %%f in (*.xml *.png) do (
    "%BT%\aapt2.exe" compile "%%f" -o "%GEN%" 2>nul
)

:: Linkear APK base
echo   - aapt2 link...
"%BT%\aapt2.exe" link -o "%OUT%\base.apk" -I "%PLATFORM%" --manifest "%MANIFEST%" 2>nul

:: Java sources
echo   - javac...
dir /s /b "%SRC%\*.java" > "%OUT%\sources.txt"
javac -d "%CLASSES%" -cp "%PLATFORM%" -source 1.8 -target 1.8 @"%OUT%\sources.txt"
if errorlevel 1 (
    echo [ERROR] Fallo compilacion Java
    type "%OUT%\sources.txt"
    pause
    exit /b 1
)

:: d8
echo   - d8...
call "%BT%\d8.bat" --lib "%PLATFORM%" --output "%OUT%" "%CLASSES%\com\tpv\zoho\manager\**\*.class" 2>nul
if not exist "%OUT%\classes.dex" (
    echo [WARN] d8 no genero classes.dex, intentando alternativa...
    dir /s /b "%CLASSES%\*.class" > "%OUT%\classes.txt"
    call "%BT%\d8.bat" --lib "%PLATFORM%" --output "%OUT%" @"%OUT%\classes.txt" 2>nul
)

:: Añadir dex al APK
if exist "%OUT%\classes.dex" (
    copy /y "%OUT%\base.apk" "%OUT%\with-dex.apk" >nul
    cd "%OUT%"
    "%BT%\aapt2.exe" add with-dex.apk classes.dex 2>nul
    cd ..\..
) else (
    echo [ERROR] No se genero classes.dex
    pause
    exit /b 1
)

:: Align + Sign
echo   - zipalign + sign...
"%BT%\zipalign.exe" -p 4 "%OUT%\with-dex.apk" "%OUT%\aligned.apk" 2>nul

if not exist "app\zoho_tpv.keystore" (
    echo   - Generando keystore...
    keytool -genkey -v -keystore app\zoho_tpv.keystore -alias zoho_tpv -keyalg RSA -keysize 2048 -validity 10000 -storepass tpv2026! -keypass tpv2026! -dname "CN=TPV, OU=IT, O=Empresa, L=Madrid, ST=Madrid, C=ES" 2>nul
)

"%BT%\apksigner.bat" sign --ks app\zoho_tpv.keystore --ks-pass pass:tpv2026! --ks-key-alias zoho_tpv --out ..\releases\zoho_tpv_manager.apk "%OUT%\aligned.apk"

:: ── 6. Resultado ──
echo.
if exist "..\releases\zoho_tpv_manager.apk" (
    echo ============================================================
    echo   COMPILACION EXITOSA
    echo   APK: ..\releases\zoho_tpv_manager.apk
    echo ============================================================
) else (
    echo ============================================================
    echo   ERROR - No se genero el APK
    echo ============================================================
)
pause
