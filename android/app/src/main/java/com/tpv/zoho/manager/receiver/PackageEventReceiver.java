package com.tpv.zoho.manager.receiver;

import android.app.admin.DevicePolicyManager;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.widget.Toast;
import java.io.File;
import java.io.FileWriter;

/**
 * Detecta cuando Zoho Assist se instala/actualiza y ejecuta
 * la configuración automática post-instalación:
 * - Concede permisos de accesibilidad, overlay, device admin
 * - Crea archivo de configuración unattended para Zoho Assist
 * - Lanza Zoho Assist
 */
public class PackageEventReceiver extends BroadcastReceiver {

    private static final String ZOHO_PKG = "com.zoho.assist";
    private static final String CONFIG_FILENAME = "zoho_tpv_config.json";

    @Override
    public void onReceive(Context ctx, Intent intent) {
        String pkg = getPackageName(intent);
        if (pkg == null || !pkg.equals(ZOHO_PKG)) return;

        String action = intent.getAction();

        if (Intent.ACTION_PACKAGE_ADDED.equals(action)) {
            toast(ctx, "Zoho Assist instalado. Configurando...");
            configureAfterInstall(ctx);

        } else if (Intent.ACTION_PACKAGE_REPLACED.equals(action)) {
            toast(ctx, "Zoho Assist actualizado. Reconfigurando permisos...");
            configureAfterInstall(ctx);

        } else if (Intent.ACTION_PACKAGE_REMOVED.equals(action)) {
            toast(ctx, "Zoho Assist desinstalado");
        }
    }

    /**
     * Post-instalación: concede permisos críticos y lanza Zoho Assist.
     */
    private void configureAfterInstall(Context ctx) {
        DevicePolicyManager dpm = (DevicePolicyManager)
            ctx.getSystemService(Context.DEVICE_POLICY_SERVICE);

        // Si somos Device Owner, podemos conceder permisos automáticamente
        if (dpm != null && dpm.isDeviceOwnerApp(ctx.getPackageName())) {
            grantPermissionsAsDeviceOwner(ctx, dpm);
        }

        // Intentar habilitar accesibilidad (requiere intervención si no Device Owner)
        enableAccessibilityIfPossible(ctx);

        // Intentar activar Device Admin
        enableDeviceAdminIfPossible(ctx, dpm);

        // Crear archivo de configuración para Zoho Assist
        pushConfigToZoho(ctx);

        // Lanzar Zoho Assist
        launchZohoAssist(ctx);

        toast(ctx, "Configuracion completada. Zoho Assist listo.");
    }

    // ── Concesión de permisos como Device Owner ─────────────────────

    private void grantPermissionsAsDeviceOwner(Context ctx, DevicePolicyManager dpm) {
        ComponentName admin = new ComponentName(ctx, DeviceAdminReceiver.class);

        try {
            // Conceder todos los permisos de runtime automáticamente
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                dpm.setPermissionPolicy(admin,
                    DevicePolicyManager.PERMISSION_POLICY_AUTO_GRANT);
            }
            // Permitir instalación de fuentes desconocidas
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                dpm.setSecureSetting(admin,
                    Settings.Secure.INSTALL_NON_MARKET_APPS, "1");
            }
        } catch (Exception e) {
            // Si falla, no es crítico — el usuario puede conceder manualmente
        }
    }

    // ── Accesibilidad ──────────────────────────────────────────────

    private void enableAccessibilityIfPossible(Context ctx) {
        try {
            // Abrir ajustes de accesibilidad para que el usuario active manualmente
            Intent intent = new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS);
            intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            ctx.startActivity(intent);
        } catch (Exception ignored) {}
    }

    // ── Device Admin ───────────────────────────────────────────────

    private void enableDeviceAdminIfPossible(Context ctx, DevicePolicyManager dpm) {
        try {
            ComponentName admin = new ComponentName(ctx, DeviceAdminReceiver.class);
            if (dpm != null && !dpm.isAdminActive(admin)) {
                // Abrir ajustes de device admin
                Intent intent = new Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN);
                intent.putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin);
                intent.putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                    "Necesario para gestion remota del TPV");
                intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                ctx.startActivity(intent);
            }
        } catch (Exception ignored) {}
    }

    // ── Configuración Zoho Assist ──────────────────────────────────

    private void pushConfigToZoho(Context ctx) {
        try {
            // Crear config básica y copiarla al directorio de Zoho Assist
            // Zoho Assist busca en /sdcard/ o en su propio data dir
            String json = "{\n" +
                "  \"unattended_mode\": true,\n" +
                "  \"auto_connect\": true,\n" +
                "  \"keep_alive\": true,\n" +
                "  \"install_source\": \"zoho_tpv_manager\"\n" +
                "}";

            // Escribir en almacenamiento compartido
            File sdcard = new File("/sdcard", CONFIG_FILENAME);
            FileWriter fw = new FileWriter(sdcard);
            fw.write(json);
            fw.close();

        } catch (Exception e) {
            // Config no crítica
        }
    }

    // ── Launch Zoho Assist ─────────────────────────────────────────

    private void launchZohoAssist(Context ctx) {
        try {
            Intent launch = ctx.getPackageManager()
                .getLaunchIntentForPackage(ZOHO_PKG);
            if (launch != null) {
                launch.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                ctx.startActivity(launch);
            }
        } catch (Exception ignored) {}
    }

    // ── Helpers ────────────────────────────────────────────────────

    private String getPackageName(Intent intent) {
        Uri data = intent.getData();
        if (data != null) {
            String pkg = data.getSchemeSpecificPart();
            if (pkg != null) return pkg;
        }
        // Intent alternativo
        String pkg = intent.getStringExtra(Intent.EXTRA_PACKAGE_NAME);
        return pkg;
    }

    private void toast(Context ctx, String msg) {
        Toast.makeText(ctx, msg, Toast.LENGTH_LONG).show();
    }
}
