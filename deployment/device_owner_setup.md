# Configuración de Device Owner — Instalación Desatendida

Para que la app instale Zoho Assist **sin que el usuario toque nada**, el TPV debe
tener esta app configurada como **Device Owner**.

---

## Requisitos previos

- El TPV **NO debe tener cuentas de Google** configuradas (ni Google Workspace, ni
  personal). Si tiene cuentas, elimínalas primero en Ajustes → Cuentas.
- Depuración USB activada en el TPV.
- ADB instalado en el PC de deployment.

---

## Paso 1 — Instalar la app en el TPV

```bash
adb install zoho_tpv_manager.apk
```

---

## Paso 2 — Activar Device Owner

```bash
adb shell dpm set-device-owner com.tpv.zoho.manager/.receiver.DeviceAdminReceiver
```

Si el comando falla con «Not allowed to set the device owner because there are
already some accounts on the device», elimina todas las cuentas:

```bash
# Listar cuentas
adb shell content query --uri content://com.android.settings.accounts/

# Ir a Ajustes → Cuentas en el TPV y eliminar todas manualmente
# Luego reintentar el comando dpm
```

---

## Verificar que funciona

```bash
# Comprobar si es Device Owner
adb shell dumpsys device_policy | grep "Device Owner"
# Debe mostrar: com.tpv.zoho.manager
```

---

## ¿Qué cambia con Device Owner?

| Sin Device Owner | Con Device Owner |
|---|---|
| Al instalar, sale el diálogo «¿Instalar?» y hay que tocar Aceptar | Instalación **silenciosa**, sin intervención |
| Los permisos (accesibilidad, overlay) hay que darlos manualmente | Se conceden **automáticamente** |
| Zoho Assist puede pedir confirmaciones al iniciar | Modo **desatendido** completo |

---

## Quitar Device Owner (si hace falta)

```bash
# Desde la app (si la app lo implementa):
adb shell dpm remove-active-admin com.tpv.zoho.manager/.receiver.DeviceAdminReceiver

# O desde Ajustes → Seguridad → Administradores de dispositivo
```

---

## Despliegue masivo (script)

```bash
#!/bin/bash
# deploy_tpv.sh — Instalar + Device Owner en lote

for serial in $(adb devices | tail -n +2 | awk '{print $1}'); do
    echo "Configurando $serial..."
    adb -s $serial install -r zoho_tpv_manager.apk
    adb -s $serial shell dpm set-device-owner com.tpv.zoho.manager/.receiver.DeviceAdminReceiver
    echo "$serial OK"
done
```
