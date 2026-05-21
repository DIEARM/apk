@echo off
REM ============================================================================
REM  Zoho TPV Manager - Script de Compilacion
REM  Genera el APK firmado listo para deployment
REM  Requiere: JDK 17+, Android SDK configurado en ANDROID_HOME
REM ============================================================================
echo ============================================================
echo   Zoho TPV Manager - Build Script v1.0.0
echo ============================================================
echo.

:: Verificar Java
java -version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Java no encontrado. Instale JDK 17+.
    echo https://adoptium.net/download/
    exit /b 1
)

:: Verificar Android SDK
if "%ANDROID_HOME%"=="" (
    if exist "%LOCALAPPDATA%\Android\Sdk" (
        set "ANDROID_HOME=%LOCALAPPDATA%\Android\Sdk"
    ) else (
        echo [ERROR] ANDROID_HOME no configurado.
        echo Configure ANDROID_HOME o instale Android Studio.
        exit /b 1
    )
)
echo [OK] ANDROID_HOME=%ANDROID_HOME%

:: Generar keystore si no existe
if not exist "app\zoho_tpv.keystore" (
    echo [INFO] Generando keystore de firma...
    keytool -genkey -v -keystore app\zoho_tpv.keystore -alias zoho_tpv -keyalg RSA -keysize 2048 -validity 10000 -storepass tpv2026! -keypass tpv2026! -dname "CN=TPV Enterprise, OU=IT, O=EmpresaTPV, L=Madrid, ST=Madrid, C=ES" 2>nul
    echo [OK] Keystore generado.
)

:: Limpiar
echo [INFO] Limpiando builds anteriores...
call gradlew clean 2>nul

:: Compilar
echo [INFO] Compilando APK release...
call gradlew assembleRelease

if errorlevel 1 (
    echo [ERROR] Fallo la compilacion.
    exit /b 1
)

set APK=app\build\outputs\apk\release\app-release.apk
if exist "%APK%" (
    echo ============================================================
    echo   COMPILACION EXITOSA
    echo   APK: %CD%\%APK%
    echo ============================================================
    certutil -hashfile "%APK%" MD5 | findstr /v ":" > app\build\outputs\apk\release\checksum.md5
) else (
    echo [ERROR] APK no encontrado.
    exit /b 1
)
pause
