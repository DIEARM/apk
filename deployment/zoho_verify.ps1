# zoho_verify.ps1 — Verificación rápida de 10 puntos para Zoho Assist TPV
# Uso: .\zoho_verify.ps1 [-DeviceSerial SERIAL]

param(
    [string]$DeviceSerial
)

if (-not $DeviceSerial) {
    $DeviceSerial = (adb devices | Select-Object -Skip 1 | Select-Object -First 1) -replace '\s+.*',''
}

if (-not $DeviceSerial) {
    Write-Host "ERROR: No se detectó ningún dispositivo Android vía ADB." -ForegroundColor Red
    exit 1
}

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Verificación Zoho Assist TPV — 10 puntos" -ForegroundColor Cyan
Write-Host "  Dispositivo: $DeviceSerial" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

$Pass = 0
$Fail = 0

function Check {
    param($Num, $Label, [ScriptBlock]$Test)
    Write-Host "`n[$Num] $Label"
    if (& $Test) {
        Write-Host "  ✅ OK" -ForegroundColor Green
        $script:Pass++
    } else {
        Write-Host "  ❌ FALLO" -ForegroundColor Red
        $script:Fail++
    }
}

# 1
Check 1 "APK instalado" {
    $r = adb -s $DeviceSerial shell pm list packages
    $r -match "com.zoho.assist"
}

# 2
Write-Host "`n[2] Versión:"
$ver = adb -s $DeviceSerial shell dumpsys package com.zoho.assist 2>&1 | Select-String "versionName"
if ($ver) { Write-Host "  $ver"; $Pass++ } else { Write-Host "  ❌ No detectada" -ForegroundColor Red; $Fail++ }

# 3
Check 3 "Servicio de accesibilidad habilitado" {
    $r = adb -s $DeviceSerial shell settings get secure enabled_accessibility_services
    $r -match "com.zoho.assist"
}

# 4
Write-Host "`n[4] Permiso SYSTEM_ALERT_WINDOW:"
$ov = adb -s $DeviceSerial shell appops get com.zoho.assist SYSTEM_ALERT_WINDOW 2>&1
Write-Host "  $ov"
if ($ov -match "allow") { Write-Host "  ✅ OK" -ForegroundColor Green; $Pass++ } else { Write-Host "  ❌ FALLO" -ForegroundColor Red; $Fail++ }

# 5
Write-Host "`n[5] Permiso PROJECT_MEDIA (captura pantalla):"
$pm = adb -s $DeviceSerial shell appops get com.zoho.assist PROJECT_MEDIA 2>&1
Write-Host "  $pm"
if ($pm -match "allow") { Write-Host "  ✅ OK" -ForegroundColor Green; $Pass++ } else { Write-Host "  ❌ FALLO" -ForegroundColor Red; $Fail++ }

# 6
Check 6 "Optimización batería deshabilitada" {
    $r = adb -s $DeviceSerial shell dumpsys deviceidle whitelist +com.zoho.assist 2>&1
    $r -match "com.zoho.assist"
}

# 7
Check 7 "Config JSON presente" {
    $r = adb -s $DeviceSerial shell ls -la /sdcard/zoho_tpv_config.json 2>&1
    $LASTEXITCODE -eq 0
}

# 8
Write-Host "`n[8] Conectividad de red:"
$ping = adb -s $DeviceSerial shell "ping -c 2 -W 5 assist.zoho.com 2>&1"
Write-Host "  $($ping[-1])"
if ($ping -match " 0% packet loss") { Write-Host "  ✅ OK" -ForegroundColor Green; $Pass++ } else { Write-Host "  ❌ FALLO" -ForegroundColor Red; $Fail++ }

# 9
Check 9 "Proceso vivo" {
    $r = adb -s $DeviceSerial shell ps
    $r -match "com.zoho.assist"
}

# 10
Write-Host "`n[10] MD5 — Comparar manualmente con manifest.json del repositorio"

# Resultado
Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host "  Resultado: $Pass/10 aprobados, $Fail fallos" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

if ($Pass -eq 10) {
    Write-Host "✅ Dispositivo listo para producción." -ForegroundColor Green
} elseif ($Pass -ge 8) {
    Write-Host "⚠️  Revisar fallos. Si son recuperables, reintentar." -ForegroundColor Yellow
} else {
    Write-Host "❌ Menos de 8/10. Se recomienda reinstalar con install_zoho.bat" -ForegroundColor Red
}
