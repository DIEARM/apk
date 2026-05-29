package com.tpv.zoho.manager.service;

import android.app.IntentService;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
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

import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.List;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

public class ZohoInstallService extends IntentService {
    private static final String ACTION_INSTALL = "com.tpv.zoho.manager.INSTALL_ZOHO";
    private static final String EXTRA_APK_PATH = "apk_path";
    private static final String EXTRA_APK_URL = "apk_url";
    private static final String APK_FILENAME = "zoho_assist.apk";
    private static final String XAPK_FILENAME = "zoho_assist.xapk";
    private static final String CONFIG_FILENAME = "zoho_tpv_config.json";
    private static final String DEFAULT_URL = "";
    private static final String CHANNEL_ID = "zoho_install";

    private Handler mainHandler;

    public ZohoInstallService() {
        super("ZohoInstallService");
    }

    @Override
    public void onCreate() {
        super.onCreate();
        mainHandler = new Handler(Looper.getMainLooper());
        startForeground(1001, buildNotification("Preparando instalacion de Zoho Assist"));
    }

    @Override
    protected void onHandleIntent(Intent intent) {
        if (intent == null || !ACTION_INSTALL.equals(intent.getAction())) return;

        String packagePath = intent.getStringExtra(EXTRA_APK_PATH);
        String packageUrl = intent.getStringExtra(EXTRA_APK_URL);
        if (packageUrl == null || packageUrl.trim().length() == 0) {
            packageUrl = getConfiguredPackageUrl();
        }
        if (packageUrl == null || packageUrl.trim().length() == 0) {
            packageUrl = DEFAULT_URL;
        }

        File packageFile = locateOrDownload(packagePath, packageUrl);
        if (packageFile == null) {
            toast("No hay APK/XAPK configurado en update-server");
            return;
        }

        if (isXapk(packageFile)) {
            installXapk(packageFile);
        } else if (isDeviceOwner()) {
            installPackageSet(singleton(packageFile), true);
        } else {
            toast("Modo manual. Configure Device Owner para instalacion desatendida.");
            normalInstall(packageFile);
        }
    }

    private File locateOrDownload(String packagePath, String packageUrl) {
        if (packagePath != null) {
            File f = new File(packagePath);
            if (f.exists() && f.length() > 100000) return f;
        }

        File local = findInDownloads(XAPK_FILENAME);
        if (local != null) return local;
        local = findInDownloads(APK_FILENAME);
        if (local != null) return local;

        if (packageUrl == null || packageUrl.trim().length() == 0) return null;
        if (!(packageUrl.endsWith(".apk") || packageUrl.endsWith(".xapk"))) return null;

        toast("Descargando Zoho Assist desde update-server...");
        return download(packageUrl);
    }

    private File findInDownloads(String fileName) {
        for (String d : new String[]{
            Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS).getAbsolutePath(),
            "/sdcard/Download", "/storage/emulated/0/Download"
        }) {
            File f = new File(d, fileName);
            if (f.exists() && f.length() > 100000) return f;
        }
        return null;
    }

    private Notification buildNotification(String text) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                "Instalacion Zoho Assist",
                NotificationManager.IMPORTANCE_LOW
            );
            NotificationManager manager = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
            if (manager != null) manager.createNotificationChannel(channel);
        }

        Notification.Builder builder = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
            ? new Notification.Builder(this, CHANNEL_ID)
            : new Notification.Builder(this);

        int icon = getApplicationInfo().icon;
        if (icon == 0) icon = android.R.drawable.stat_sys_download;
        return builder
            .setSmallIcon(icon)
            .setContentTitle("Zoho TPV Manager")
            .setContentText(text)
            .setOngoing(true)
            .build();
    }

    private File download(String urlStr) {
        HttpURLConnection connection = null;
        try {
            URL url = new URL(urlStr);
            connection = (HttpURLConnection) url.openConnection();
            connection.setConnectTimeout(15000);
            connection.setReadTimeout(180000);
            connection.connect();

            if (connection.getResponseCode() >= 400) {
                throw new IllegalStateException("HTTP " + connection.getResponseCode());
            }

            String fileName = urlStr.endsWith(".xapk") ? XAPK_FILENAME : APK_FILENAME;
            File out = new File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                fileName
            );

            try (InputStream in = connection.getInputStream();
                 FileOutputStream fos = new FileOutputStream(out)) {
                byte[] buf = new byte[8192];
                int n;
                while ((n = in.read(buf)) != -1) fos.write(buf, 0, n);
            }
            return out;
        } catch (Exception e) {
            toast("Error descargando: " + e.getMessage());
            return null;
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    private String getConfiguredPackageUrl() {
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
                String xapkUrl = zoho.optString("xapk_download_url", "");
                if (xapkUrl.trim().length() > 0) return xapkUrl.trim();
            }

            JSONObject repo = root.optJSONObject("update_repository");
            if (repo != null) {
                String baseUrl = repo.optString("base_url", "");
                String channel = repo.optString("channel", "stable");
                if (baseUrl.trim().length() > 0) {
                    if (baseUrl.endsWith("/")) {
                        baseUrl = baseUrl.substring(0, baseUrl.length() - 1);
                    }
                    return baseUrl + "/" + channel + "/zoho_assist.xapk";
                }
            }
        } catch (Exception e) {
            toast("Config invalida: " + e.getMessage());
        }
        return null;
    }

    private void installXapk(File xapkFile) {
        try {
            List<File> apks = extractXapk(xapkFile);
            if (apks.isEmpty()) {
                toast("XAPK sin APKs internos");
                return;
            }
            installPackageSet(apks, isDeviceOwner());
        } catch (Exception e) {
            toast("Error instalando XAPK: " + e.getMessage());
        }
    }

    private void installPackageSet(List<File> apkFiles, boolean unattended) {
        try {
            PackageInstaller installer = getPackageManager().getPackageInstaller();
            PackageInstaller.SessionParams params =
                new PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL);

            int sid = installer.createSession(params);
            PackageInstaller.Session session = installer.openSession(sid);

            byte[] buf = new byte[8192];
            for (File apk : apkFiles) {
                try (OutputStream out = session.openWrite(apk.getName(), 0, apk.length());
                     FileInputStream in = new FileInputStream(apk)) {
                    int n;
                    while ((n = in.read(buf)) != -1) out.write(buf, 0, n);
                    session.fsync(out);
                }
            }

            Intent confirm = new Intent("com.tpv.zoho.manager.INSTALL_DONE");
            PendingIntent pi = PendingIntent.getBroadcast(this, sid, confirm,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            session.commit(pi.getIntentSender());
            session.close();

            toast(unattended
                ? "Zoho Assist instalado en segundo plano"
                : "Instalacion iniciada. Android puede pedir confirmacion.");
        } catch (Exception e) {
            toast("Fallo instalacion: " + e.getMessage());
            if (apkFiles.size() == 1) normalInstall(apkFiles.get(0));
        }
    }

    private List<File> extractXapk(File xapkFile) throws Exception {
        File outDir = new File(getCacheDir(), "zoho_assist_xapk");
        deleteRecursive(outDir);
        outDir.mkdirs();

        List<File> apks = new ArrayList<>();
        byte[] buf = new byte[8192];
        try (ZipInputStream zin = new ZipInputStream(new FileInputStream(xapkFile))) {
            ZipEntry entry;
            while ((entry = zin.getNextEntry()) != null) {
                String name = new File(entry.getName()).getName();
                if (entry.isDirectory() || !name.endsWith(".apk")) continue;

                File out = new File(outDir, name);
                try (FileOutputStream fos = new FileOutputStream(out)) {
                    int n;
                    while ((n = zin.read(buf)) != -1) fos.write(buf, 0, n);
                }
                apks.add(out);
            }
        }
        return apks;
    }

    private void normalInstall(File apkFile) {
        try {
            Intent intent = new Intent(Intent.ACTION_VIEW);
            intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);

            Uri uri;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                uri = com.tpv.zoho.manager.utils.ApkFileProvider.getUriForFile(this, apkFile);
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

    private boolean isXapk(File file) {
        return file.getName().toLowerCase().endsWith(".xapk");
    }

    private List<File> singleton(File file) {
        List<File> files = new ArrayList<>();
        files.add(file);
        return files;
    }

    private void deleteRecursive(File file) {
        if (file == null || !file.exists()) return;
        if (file.isDirectory()) {
            File[] children = file.listFiles();
            if (children != null) {
                for (File child : children) deleteRecursive(child);
            }
        }
        file.delete();
    }

    private boolean isDeviceOwner() {
        DevicePolicyManager dpm = (DevicePolicyManager)
            getSystemService(Context.DEVICE_POLICY_SERVICE);
        return dpm != null && dpm.isDeviceOwnerApp(getPackageName());
    }

    private void toast(String msg) {
        mainHandler.post(() ->
            Toast.makeText(ZohoInstallService.this, msg, Toast.LENGTH_LONG).show());
    }

    public static void start(Context ctx, File packageFile, String packageUrl) {
        Intent i = new Intent(ctx, ZohoInstallService.class);
        i.setAction(ACTION_INSTALL);
        if (packageFile != null) i.putExtra(EXTRA_APK_PATH, packageFile.getAbsolutePath());
        if (packageUrl != null) i.putExtra(EXTRA_APK_URL, packageUrl);
        ctx.startService(i);
    }

    public static void start(Context ctx) {
        start(ctx, null, null);
    }
}
