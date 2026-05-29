@echo off
:: Este script compila la app Zoho TPV Manager
:: Doble clic para ejecutar

cd /d "C:\Users\SIE\Desktop\zoho-tpv-manager\android"

echo ============================================================
echo   Zoho TPV Manager — Compilar APK
echo ============================================================
echo.

javac -version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Java no encontrado. Instala JDK 17:
    echo https://adoptium.net/download/
    pause
    exit
)
echo [OK] Java OK

:: Buscar SDK
if exist "%ANDROID_HOME%\build-tools" goto :ok
if exist "%LOCALAPPDATA%\Android\Sdk\build-tools" set ANDROID_HOME=%LOCALAPPDATA%\Android\Sdk&& goto :ok
echo [ERROR] Android SDK no encontrado.
echo Instala Android Studio: https://developer.android.com/studio
pause
exit

:ok
for /d %%d in ("%ANDROID_HOME%\build-tools\*") do set BT=%%d
set PLATFORM=%ANDROID_HOME%\platforms\android-34\android.jar

echo [OK] SDK en %ANDROID_HOME%

set SRC=app\src\main\java
set RES=app\src\main\res
set MANIFEST=app\src\main\AndroidManifest.xml
set OUT=build\manual
set G=%OUT%\gen
set C=%OUT%\classes

rmdir /s /q "%OUT%" 2>nul
mkdir "%G%" "%C%" 2>nul

echo Compilando...
for /r "%RES%" %%f in (*.xml) do "%BT%\aapt2.exe" compile "%%f" -o "%G%" 2>nul
"%BT%\aapt2.exe" link -o "%OUT%\base.apk" -I "%PLATFORM%" --manifest "%MANIFEST%" 2>nul
dir /s /b "%SRC%\*.java" > "%OUT%\sources.txt"
javac -d "%C%" -cp "%PLATFORM%" -source 1.8 -target 1.8 @"%OUT%\sources.txt"
if errorlevel 1 (
    echo ERROR COMPILACION
    pause && exit
)

dir /s /b "%C%\*.class" > "%OUT%\classes.txt"
call "%BT%\d8.bat" --lib "%PLATFORM%" --output "%OUT%" @"%OUT%\classes.txt" 2>nul

copy /y "%OUT%\base.apk" "%OUT%\tmp.apk" >nul
cd "%OUT%" && "%BT%\aapt2.exe" add tmp.apk classes.dex 2>nul && cd ..\..

"%BT%\zipalign.exe" -p 4 "%OUT%\tmp.apk" "%OUT%\aligned.apk" 2>nul

if not exist "app\zoho_tpv.keystore" (
    keytool -genkey -v -keystore app\zoho_tpv.keystore -alias zoho_tpv -keyalg RSA -keysize 2048 -validity 10000 -storepass tpv2026! -keypass tpv2026! -dname "CN=TPV, OU=IT, O=Empresa, L=Madrid, ST=Madrid, C=ES" 2>nul
)

"%BT%\apksigner.bat" sign --ks app\zoho_tpv.keystore --ks-pass pass:tpv2026! --ks-key-alias zoho_tpv --out ..\releases\zoho_tpv_manager.apk "%OUT%\aligned.apk"

echo.
echo ============================================================
echo   APK generado: releases\zoho_tpv_manager.apk
echo ============================================================
pause
