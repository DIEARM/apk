package com.tpv.zoho.manager.service;

import android.content.Context;
import android.content.pm.PackageInfo;
import android.os.Build;
import android.os.Environment;

import com.tpv.zoho.manager.model.UpdateManifest;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;

public class UpdateChecker {
    public interface Callback {
        void onStatus(String message);
        void onUpdateReady(File apkFile, UpdateManifest manifest);
        void onNoUpdate(String message);
        void onError(String message);
    }

    private static final String PACKAGE_ZOHO_ASSIST = "com.zoho.assist.agent";
    private static final String DEFAULT_BASE_URL =
        "https://repo-empresarial.example.com/zoho";
    private static final String DEFAULT_CHANNEL = "stable";

    public static void checkAndDownload(Context context, Callback callback) {
        checkAndDownload(context, DEFAULT_BASE_URL, DEFAULT_CHANNEL, callback);
    }

    public static void checkAndDownload(
        Context context,
        String baseUrl,
        String channel,
        Callback callback
    ) {
        new Thread(() -> {
            try {
                String manifestUrl = normalizeBase(baseUrl) + "/" + channel + "/manifest.json";
                callback.onStatus("Consultando " + manifestUrl);

                UpdateManifest manifest = UpdateManifest.fromJson(httpGet(manifestUrl));
                if (!manifest.hasDownload()) {
                    callback.onNoUpdate("El repositorio no tiene APK disponible");
                    return;
                }

                if (Build.VERSION.SDK_INT < manifest.minSdk) {
                    callback.onError("Android SDK " + Build.VERSION.SDK_INT
                        + " no cumple minSdk " + manifest.minSdk);
                    return;
                }

                int installedCode = getInstalledVersionCode(context);
                if (installedCode >= manifest.versionCode) {
                    callback.onNoUpdate("Zoho Assist ya esta actualizado");
                    return;
                }

                String apkUrl = absoluteUrl(baseUrl, manifest.getPackageUrl());
                callback.onStatus("Descargando Zoho Assist " + manifest.version);
                File apkFile = downloadPackage(apkUrl);

                if (manifest.md5 != null && manifest.md5.trim().length() > 0) {
                    String actualMd5 = md5(apkFile);
                    if (!manifest.md5.equalsIgnoreCase(actualMd5)) {
                        apkFile.delete();
                        callback.onError("MD5 invalido. Esperado " + manifest.md5
                            + ", obtenido " + actualMd5);
                        return;
                    }
                }

                callback.onUpdateReady(apkFile, manifest);
            } catch (Exception e) {
                callback.onError(e.getMessage() != null ? e.getMessage() : e.toString());
            }
        }).start();
    }

    private static String httpGet(String urlStr) throws Exception {
        HttpURLConnection connection = (HttpURLConnection) new URL(urlStr).openConnection();
        connection.setConnectTimeout(15000);
        connection.setReadTimeout(30000);
        connection.setRequestProperty("Accept", "application/json");
        try (InputStream in = connection.getInputStream()) {
            byte[] buffer = new byte[8192];
            StringBuilder out = new StringBuilder();
            int read;
            while ((read = in.read(buffer)) != -1) {
                out.append(new String(buffer, 0, read, "UTF-8"));
            }
            return out.toString();
        } finally {
            connection.disconnect();
        }
    }

    private static File downloadPackage(String urlStr) throws Exception {
        HttpURLConnection connection = (HttpURLConnection) new URL(urlStr).openConnection();
        connection.setConnectTimeout(15000);
        connection.setReadTimeout(120000);

        String fileName = urlStr.endsWith(".xapk") ? "zoho_assist.xapk" : "zoho_assist.apk";
        File out = new File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            fileName
        );

        try (InputStream in = connection.getInputStream();
             FileOutputStream fos = new FileOutputStream(out)) {
            byte[] buffer = new byte[8192];
            int read;
            while ((read = in.read(buffer)) != -1) {
                fos.write(buffer, 0, read);
            }
        } finally {
            connection.disconnect();
        }

        return out;
    }

    private static int getInstalledVersionCode(Context context) {
        try {
            PackageInfo pi = context.getPackageManager().getPackageInfo(PACKAGE_ZOHO_ASSIST, 0);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                return (int) pi.getLongVersionCode();
            }
            return pi.versionCode;
        } catch (Exception ignored) {
            return 0;
        }
    }

    private static String md5(File file) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("MD5");
        try (FileInputStream in = new FileInputStream(file)) {
            byte[] buffer = new byte[8192];
            int read;
            while ((read = in.read(buffer)) != -1) {
                digest.update(buffer, 0, read);
            }
        }

        StringBuilder hex = new StringBuilder();
        for (byte b : digest.digest()) {
            hex.append(String.format("%02x", b & 0xff));
        }
        return hex.toString();
    }

    private static String normalizeBase(String baseUrl) {
        if (baseUrl.endsWith("/")) {
            return baseUrl.substring(0, baseUrl.length() - 1);
        }
        return baseUrl;
    }

    private static String absoluteUrl(String baseUrl, String apkUrl) throws Exception {
        if (apkUrl.startsWith("http://") || apkUrl.startsWith("https://")) {
            return apkUrl;
        }
        URL base = new URL(normalizeBase(baseUrl));
        if (apkUrl.startsWith("/")) {
            return base.getProtocol() + "://" + base.getAuthority() + apkUrl;
        }
        return new URL(new URL(normalizeBase(baseUrl) + "/"), apkUrl).toString();
    }
}
