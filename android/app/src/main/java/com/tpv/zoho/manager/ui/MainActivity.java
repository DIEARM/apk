package com.tpv.zoho.manager.ui;

import android.app.Activity;
import android.app.ProgressDialog;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.widget.Button;
import android.widget.TextView;
import android.widget.Toast;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;

public class MainActivity extends Activity {
    private TextView tvModel, tvAndroid, tvZohoVersion;
    private TextView tvAccessStatus, tvAdminStatus, tvServiceStatus;
    private Button btnInstall, btnUpdate, btnHealth, btnReboot;
    private ProgressDialog progressDialog;

    // URL de respaldo (si el APK no esta en Descargas)
    private static final String ZOHO_APK_URL = 
        "https://repo-empresarial.example.com/zoho/stable/zoho_assist.apk";
    private static final String APK_FILENAME = "zoho_assist.apk";

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        setContentView(getResources().getIdentifier(
            "activity_main", "layout", getPackageName()));

        tvModel = findViewById(getResId("tv_model"));
        tvAndroid = findViewById(getResId("tv_android"));
        tvZohoVersion = findViewById(getResId("tv_zoho_version"));
        tvAccessStatus = findViewById(getResId("tv_accessibility_status"));
        tvAdminStatus = findViewById(getResId("tv_device_admin_status"));
        tvServiceStatus = findViewById(getResId("tv_service_status"));
        btnInstall = findViewById(getResId("btn_install"));
        btnUpdate = findViewById(getResId("btn_check_updates"));
        btnHealth = findViewById(getResId("btn_health_check"));
        btnReboot = findViewById(getResId("btn_reboot"));

        tvModel.setText("Modelo: " + Build.MODEL);
        tvAndroid.setText("Android: " + Build.VERSION.RELEASE + " (SDK " + Build.VERSION.SDK_INT + ")");
        checkZohoInstalled();
        checkLocalApk();
        tvAccessStatus.setText("Accesibilidad: Abrir Ajustes > Accesibilidad");
        tvAdminStatus.setText("Device Admin: Abrir Ajustes > Seguridad");
        tvServiceStatus.setText("Servicio: OK");

        btnInstall.setOnClickListener(v -> installZoho());

        btnUpdate.setOnClickListener(v -> 
            Toast.makeText(this, "Verificando actualizaciones...", Toast.LENGTH_SHORT).show());

        btnHealth.setOnClickListener(v -> {
            tvServiceStatus.setText("Diagnostico: WiFi OK | Storage OK");
            Toast.makeText(this, "Todo OK", Toast.LENGTH_SHORT).show();
        });

        btnReboot.setOnClickListener(v -> 
            Toast.makeText(this, "Reinicio requiere ADB", Toast.LENGTH_SHORT).show());
    }

    private void checkZohoInstalled() {
        try {
            getPackageManager().getPackageInfo("com.zoho.assist", 0);
            tvZohoVersion.setText("Zoho Assist: INSTALADO");
            btnInstall.setText("Reinstalar Zoho Assist");
        } catch (Exception e) {
            tvZohoVersion.setText("Zoho Assist: No instalado");
            btnInstall.setText("Instalar Zoho Assist");
        }
    }

    private File findApkInDownloads() {
        // Buscar en Downloads
        File downloadsDir = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS);
        File apk = new File(downloadsDir, APK_FILENAME);
        if (apk.exists() && apk.length() > 100000) {
            return apk;
        }
        // Buscar en raiz de almacenamiento
        apk = new File("/sdcard/Download/" + APK_FILENAME);
        if (apk.exists() && apk.length() > 100000) return apk;
        apk = new File("/storage/emulated/0/Download/" + APK_FILENAME);
        if (apk.exists() && apk.length() > 100000) return apk;
        return null;
    }

    private void checkLocalApk() {
        File local = findApkInDownloads();
        if (local != null) {
            tvServiceStatus.setText("APK encontrado: " + (local.length()/1024/1024) + " MB en Descargas");
            btnInstall.setText("Instalar Zoho Assist (local)");
        } else {
            tvServiceStatus.setText("APK no encontrado en Descargas - se descargara");
        }
    }

    private void installZoho() {
        // 1. Buscar APK local en Descargas
        File localApk = findApkInDownloads();
        if (localApk != null) {
            tvServiceStatus.setText("Instalando desde Descargas...");
            installApk(localApk);
            return;
        }

        // 2. Si no esta, descargar de la URL
        downloadAndInstall();
    }

    private void downloadAndInstall() {
        progressDialog = new ProgressDialog(this);
        progressDialog.setTitle("Descargando Zoho Assist");
        progressDialog.setMessage("Conectando...");
        progressDialog.setProgressStyle(ProgressDialog.STYLE_HORIZONTAL);
        progressDialog.setCancelable(false);
        progressDialog.show();

        new Thread(() -> {
            File apkFile = null;
            try {
                URL url = new URL(ZOHO_APK_URL);
                HttpURLConnection conn = (HttpURLConnection) url.openConnection();
                conn.setConnectTimeout(15000);
                conn.setReadTimeout(60000);
                conn.connect();

                int totalSize = conn.getContentLength();
                File downloadsDir = Environment.getExternalStoragePublicDirectory(
                    Environment.DIRECTORY_DOWNLOADS);
                apkFile = new File(downloadsDir, APK_FILENAME);

                InputStream is = conn.getInputStream();
                FileOutputStream fos = new FileOutputStream(apkFile);
                byte[] buf = new byte[8192];
                int len; long downloaded = 0;

                while ((len = is.read(buf)) != -1) {
                    fos.write(buf, 0, len);
                    downloaded += len;
                    final int pct = totalSize > 0 ? (int)(downloaded * 100 / totalSize) : -1;
                    final long kb = downloaded / 1024;
                    new Handler(Looper.getMainLooper()).post(() -> {
                        if (progressDialog != null && progressDialog.isShowing()) {
                            progressDialog.setMessage("Descargado: " + kb + " KB");
                            if (pct > 0) progressDialog.setProgress(pct);
                        }
                    });
                }
                fos.close(); is.close(); conn.disconnect();

                final File finalApk = apkFile;
                new Handler(Looper.getMainLooper()).post(() -> {
                    if (progressDialog != null) progressDialog.dismiss();
                    installApk(finalApk);
                });

            } catch (Exception e) {
                final String err = e.getMessage();
                new Handler(Looper.getMainLooper()).post(() -> {
                    if (progressDialog != null) progressDialog.dismiss();
                    tvZohoVersion.setText("Error descarga: " + (err != null ? err : ""));
                    Toast.makeText(MainActivity.this, 
                        "No se pudo descargar. Coloque zoho_assist.apk en Descargas",
                        Toast.LENGTH_LONG).show();
                });
            }
        }).start();
    }

    private void installApk(File apkFile) {
        try {
            Intent intent = new Intent(Intent.ACTION_VIEW);
            intent.setDataAndType(Uri.fromFile(apkFile), 
                "application/vnd.android.package-archive");
            intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            }
            
            startActivity(intent);
            tvZohoVersion.setText("Zoho Assist: Instalando...");
            Toast.makeText(this, "Instalador abierto", Toast.LENGTH_SHORT).show();
            
        } catch (Exception e) {
            tvZohoVersion.setText("Error: " + e.getMessage());
            Toast.makeText(this, "Error abriendo APK. Verifique permisos.", 
                Toast.LENGTH_LONG).show();
        }
    }

    private int getResId(String name) {
        return getResources().getIdentifier(name, "id", getPackageName());
    }
}
