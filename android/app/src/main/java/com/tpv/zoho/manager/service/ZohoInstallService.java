package com.tpv.zoho.manager.service;

import android.app.IntentService;
import android.app.PendingIntent;
import android.app.admin.DevicePolicyManager;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInstaller;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.widget.Toast;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import org.json.JSONObject;

/**
 * Servicio de instalación desatendida de Zoho Assist.
 * Si el dispositivo es Device Owner → instalación silenciosa vía PackageInstaller.
 * Si no → fallback al instalador del sistema (requiere tocar Aceptar).
 */
public class ZohoInstallService extends IntentService {

    private static final String ACTION_INSTALL = "com.tpv.zoho.manager.INSTALL_ZOHO";
    private static final String EXTRA_APK_PATH = "apk_path";
    private static final String EXTRA_APK_URL = "apk_url";
    private static final String APK_FILENAME = "zoho_assist.apk";
    private static final String CONFIG_FILENAME = "zoho_tpv_config.json";
    private static final String DEFAULT_URL =
        "https://repo-empresarial.example.com/zoho/stable/zoho_assist.apk";

    private Handler mainHandler;

    public ZohoInstallService() { super("ZohoInstallService"); }

    @Override
    public void onCreate() {
        super.onCreate();
        mainHandler = new Handler(Looper.getMainLooper());
    }

    @Override
    protected void onHandleIntent(Intent intent) {
        if (intent == null || !ACTION_INSTALL.equals(intent.getAction())) return;

        String apkPath = intent.getStringExtra(EXTRA_APK_PATH);
        String apkUrl = intent.getStringExtra(EXTRA_APK_URL);
        if (apkUrl == null || apkUrl.trim().length() == 0) {
            apkUrl = getConfiguredApkUrl();
        }
        if (apkUrl == null || apkUrl.trim().length() == 0) {
            apkUrl = DEFAULT_URL;
        }

        File apkFile = locateOrDownload(apkPath, apkUrl);
        if (apkFile == null) {
            toast("No se pudo obtener el APK de Zoho Assist");
            return;
        }

        if (isDeviceOwner()) {
            silentInstall(apkFile);
        } else {
            toast("Modo manual. Configure Device Owner para instalacion desatendida.");
            normalInstall(apkFile);
        }
    }

    // ── Localizar / Descargar APK ─────────────────────────────────────

    private File locateOrDownload(String apkPath, String apkUrl) {
        if (apkPath != null) {
            File f = new File(apkPath);
            if (f.exists() && f.length() > 100000) return f;
        }
        File local = findInDownloads();
        if (local != null) return local;

        toast("Descargando Zoho Assist...");
        return download(apkUrl);
    }

    private File findInDownloads() {
        for (String d : new String[]{
            Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS).getAbsolutePath(),
            "/sdcard/Download", "/storage/emulated/0/Download"
        }) {
            File f = new File(d, APK_FILENAME);
            if (f.exists() && f.length() > 100000) return f;
        }
        return null;
    }

    private File download(String urlStr) {
        try {
            URL url = new URL(urlStr);
            HttpURLConnection c = (HttpURLConnection) url.openConnection();
            c.setConnectTimeout(15000);
            c.setReadTimeout(120000);
            c.connect();

            File out = new File(Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS), APK_FILENAME);
            InputStream in = c.getInputStream();
            FileOutputStream fos = new FileOutputStream(out);
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) != -1) fos.write(buf, 0, n);
            fos.close(); in.close(); c.disconnect();
            return out;
        } catch (Exception e) {
            toast("Error descargando: " + e.getMessage());
            return null;
        }
    }

    private String getConfiguredApkUrl() {
        File config = new File(Environment.getExternalStorageDirectory(), CONFIG_FILENAME);
        if (!config.exists()) {
            config = new File(Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS), CONFIG_FILENAME);
        }
        if (!config.exists()) return null;

        try (FileInputStream in = new FileInputStream(config)) {
            byte[] data = new byte[(int) config.length()];
            int read = in.read(data);
            if (read <= 0) return null;

            JSONObject root = new JSONObject(new String(data, 0, read, "UTF-8"));
            JSONObject zoho = root.optJSONObject("zoho_assist");
            if (zoho != null) {
                String directUrl = zoho.optString("apk_download_url", "");
                if (directUrl.trim().length() > 0) return directUrl.trim();
            }

            JSONObject repo = root.optJSONObject("update_repository");
            if (repo != null) {
                String baseUrl = repo.optString("base_url", "");
                String channel = repo.optString("channel", "stable");
                if (baseUrl.trim().length() > 0) {
                    if (baseUrl.endsWith("/")) {
                        baseUrl = baseUrl.substring(0, baseUrl.length() - 1);
                    }
                    return baseUrl + "/" + channel + "/zoho_assist.apk";
                }
            }
        } catch (Exception e) {
            toast("Config invalida, usando URL por defecto");
        }
        return null;
    }

    // ── Instalación silenciosa (Device Owner) ─────────────────────────

    private void silentInstall(File apkFile) {
        try {
            PackageInstaller pi = getPackageManager().getPackageInstaller();
            PackageInstaller.SessionParams params =
                new PackageInstaller.SessionParams(
                    PackageInstaller.SessionParams.MODE_FULL_INSTALL);

            int sid = pi.createSession(params);
            PackageInstaller.Session session = pi.openSession(sid);

            try (OutputStream out = session.openWrite("apk", 0, apkFile.length());
                 FileInputStream in = new FileInputStream(apkFile)) {
                byte[] buf = new byte[8192];
                int n;
                while ((n = in.read(buf)) != -1) out.write(buf, 0, n);
                session.fsync(out);
            }

            Intent confirm = new Intent("com.tpv.zoho.manager.INSTALL_DONE");
            PendingIntent pi2 = PendingIntent.getBroadcast(this, sid, confirm,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            session.commit(pi2.getIntentSender());
            session.close();

            toast("Zoho Assist instalado en segundo plano");
        } catch (Exception e) {
            toast("Fallo silent install, intentando normal: " + e.getMessage());
            normalInstall(apkFile);
        }
    }

    // ── Instalación normal (fallback) ────────────────────────────────

    private void normalInstall(File apkFile) {
        try {
            Intent intent = new Intent(Intent.ACTION_VIEW);
            intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);

            Uri uri;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                uri = com.tpv.zoho.manager.utils.ApkFileProvider
                    .getUriForFile(this, apkFile);
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            } else {
                uri = Uri.fromFile(apkFile);
            }
            intent.setDataAndType(uri, "application/vnd.android.package-archive");
            startActivity(intent);

        } catch (Exception e) {
            toast("Error abriendo instalador: " + e.getMessage());
        }
    }

    // ── Device Owner check ───────────────────────────────────────────

    private boolean isDeviceOwner() {
        DevicePolicyManager dpm = (DevicePolicyManager)
            getSystemService(Context.DEVICE_POLICY_SERVICE);
        return dpm != null && dpm.isDeviceOwnerApp(getPackageName());
    }

    private void toast(String msg) {
        mainHandler.post(() ->
            Toast.makeText(ZohoInstallService.this, msg, Toast.LENGTH_LONG).show());
    }

    // ── API pública ──────────────────────────────────────────────────

    public static void start(Context ctx, File apkFile, String apkUrl) {
        Intent i = new Intent(ctx, ZohoInstallService.class);
        i.setAction(ACTION_INSTALL);
        if (apkFile != null) i.putExtra(EXTRA_APK_PATH, apkFile.getAbsolutePath());
        if (apkUrl != null) i.putExtra(EXTRA_APK_URL, apkUrl);
        ctx.startService(i);
    }

    public static void start(Context ctx) {
        start(ctx, null, null);
    }
}
