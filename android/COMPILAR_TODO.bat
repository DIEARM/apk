@echo off
title Zoho TPV Manager — Compilar APK (TODO EN UNO)
cd /d "%~dp0"

echo ============================================================
echo   Zoho TPV Manager — Compilador
echo   Descarga SDK + Compila + Firma = APK listo
echo ============================================================
echo.

:: ── 1. Java ──
java -version >nul 2>&1 || (echo Instala JDK 17: https://adoptium.net & pause & exit /b 1)

:: ── 2. SDK ──
set ANDROID_SDK=%LOCALAPPDATA%\Android\Sdk
if not exist "%ANDROID_SDK%\cmdline-tools\latest\bin\sdkmanager.bat" (
    echo Descargando Android SDK command-line tools...
    mkdir "%ANDROID_SDK%\cmdline-tools\latest" 2>nul
    powershell -Command "Invoke-WebRequest 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip' -OutFile '%TEMP%\sdk.zip'" || (echo Error de red & pause & exit /b 1)
    powershell -Command "Expand-Archive '%TEMP%\sdk.zip' '%TEMP%\sdk'" -Force
    xcopy "%TEMP%\sdk\cmdline-tools\*" "%ANDROID_SDK%\cmdline-tools\latest\" /E /Y >nul
)

:: ── 3. Platform ──
set ANDROID_HOME=%ANDROID_SDK%
set PLATFORM=%ANDROID_HOME%\platforms\android-34\android.jar
if not exist "%PLATFORM%" (
    echo Instalando Android 34 platform...
    echo y | "%ANDROID_SDK%\cmdline-tools\latest\bin\sdkmanager.bat" --sdk_root="%ANDROID_SDK%" "platforms;android-34" "build-tools;34.0.0"
)

:: ── 4. Build ──
echo Compilando APK...
set BT=%ANDROID_HOME%\build-tools\34.0.0
set PROJ=%~dp0

mkdir "%PROJ%build\tmp" 2>nul

:: Compile resources
"%BT%\aapt2.exe" compile --dir "%PROJ%app\src\main\res" -o "%PROJ%build\tmp\res" 2>nul

:: Compile Java
dir /s /b "%PROJ%app\src\main\java\*.java" > "%PROJ%build\tmp\sources.txt"
javac -d "%PROJ%build\tmp\classes" -cp "%PLATFORM%" -encoding UTF-8 @"%PROJ%build\tmp\sources.txt" 2>&1
if errorlevel 1 (echo ERROR JAVA & pause & exit /b 1)

:: D8
dir /s /b "%PROJ%build\tmp\classes\*.class" > "%PROJ%build\tmp\classes.txt"
call "%BT%\d8.bat" --lib "%PLATFORM%" --output "%PROJ%build\tmp" @"%PROJ%build\tmp\classes.txt" 2>nul

:: Link APK
dir /b "%PROJ%build\tmp\res\*.flat" > "%PROJ%build\tmp\flats.txt"
pushd "%PROJ%build\tmp\res"
"%BT%\aapt2.exe" link -o "%PROJ%build\tmp\unaligned.apk" --manifest "%PROJ%app\src\main\AndroidManifest.xml" -I "%PLATFORM%" @..\flats.txt 2>&1
popd

:: Add dex
copy "%PROJ%build\tmp\unaligned.apk" "%PROJ%build\tmp\with-dex.apk" >nul
pushd "%PROJ%build\tmp"
"%BT%\aapt2.exe" add with-dex.apk classes.dex 2>nul
popd

:: Align
"%BT%\zipalign.exe" -p 4 "%PROJ%build\tmp\with-dex.apk" "%PROJ%build\tmp\aligned.apk" 2>nul

:: Sign
if not exist "%PROJ%app\zoho_tpv.keystore" (
    keytool -genkey -v -keystore "%PROJ%app\zoho_tpv.keystore" -alias zoho_tpv -keyalg RSA -keysize 2048 -validity 10000 -storepass tpv2026! -keypass tpv2026! -dname "CN=TPV, OU=IT, O=Empresa, L=Madrid, ST=Madrid, C=ES" 2>nul
)
"%BT%\apksigner.bat" sign --ks "%PROJ%app\zoho_tpv.keystore" --ks-pass pass:tpv2026! --ks-key-alias zoho_tpv --out "%PROJ%..\releases\zoho_tpv_manager.apk" "%PROJ%build\tmp\aligned.apk" 2>nul

echo.
if exist "%PROJ%..\releases\zoho_tpv_manager.apk" (
    echo ============================================================
    echo   APK LISTO: releases\zoho_tpv_manager.apk
    echo ============================================================
) else (
    echo ERROR
)
pause
