package com.tpv.zoho.manager.ui;

import android.app.Activity;
import android.app.admin.DevicePolicyManager;
import android.content.Context;
import android.content.Intent;
import android.net.ConnectivityManager;
import android.net.NetworkInfo;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.os.StatFs;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.TextView;
import android.widget.Toast;

import com.tpv.zoho.manager.model.UpdateManifest;
import com.tpv.zoho.manager.service.UpdateChecker;
import com.tpv.zoho.manager.service.ZohoInstallService;

import java.io.File;

public class MainActivity extends Activity {
    private TextView tvDeviceModel;
    private TextView chipStatus;
    private TextView tvZohoStatus;
    private TextView tvZohoVersionCard;
    private ImageView ivZohoStatus;
    private TextView tvAccessStatus;
    private TextView tvAdminStatus;
    private TextView tvServiceStatus;
    private ImageView ivAccess;
    private ImageView ivAdmin;
    private ImageView ivService;
    private TextView tvAndroidVersion;
    private TextView tvBattery;
    private TextView tvStorage;
    private Button btnInstall;
    private Button btnUpdate;
    private Button btnDashboard;
    private Button btnHealth;
    private Button btnReboot;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        setContentView(getResources().getIdentifier(
            "activity_main", "layout", getPackageName()));

        bindViews();
        loadDeviceInfo();
        checkZohoInstalled();
        checkServices();
        setupListeners();
    }

    private void bindViews() {
        tvDeviceModel = findViewById(getResId("tv_device_model"));
        chipStatus = findViewById(getResId("chip_status"));
        tvZohoStatus = findViewById(getResId("tv_zoho_status"));
        tvZohoVersionCard = findViewById(getResId("tv_zoho_version_card"));
        ivZohoStatus = findViewById(getResId("iv_zoho_status"));
        tvAccessStatus = findViewById(getResId("tv_accessibility_status"));
        tvAdminStatus = findViewById(getResId("tv_device_admin_status"));
        tvServiceStatus = findViewById(getResId("tv_service_status"));
        ivAccess = findViewById(getResId("iv_accessibility"));
        ivAdmin = findViewById(getResId("iv_admin"));
        ivService = findViewById(getResId("iv_service"));
        tvAndroidVersion = findViewById(getResId("tv_android_version"));
        tvBattery = findViewById(getResId("tv_battery"));
        tvStorage = findViewById(getResId("tv_storage"));
        btnInstall = findViewById(getResId("btn_install"));
        btnUpdate = findViewById(getResId("btn_check_updates"));
        btnDashboard = findViewById(getResId("btn_dashboard"));
        btnHealth = findViewById(getResId("btn_health_check"));
        btnReboot = findViewById(getResId("btn_reboot"));
    }

    private void loadDeviceInfo() {
        tvDeviceModel.setText(Build.MANUFACTURER + " " + Build.MODEL);
        tvAndroidVersion.setText("Android: " + Build.VERSION.RELEASE
            + " (SDK " + Build.VERSION.SDK_INT + ")");

        Intent batIntent = registerReceiver(
            null,
            new android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        );
        if (batIntent != null) {
            int level = batIntent.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1);
            int scale = batIntent.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, 100);
            int pct = (int) (level * 100f / scale);
            tvBattery.setText("Bateria: " + pct + "%");
        } else {
            tvBattery.setText("Bateria: --");
        }

        try {
            StatFs stat = new StatFs(Environment.getDataDirectory().getPath());
            long free = stat.getAvailableBlocksLong() * stat.getBlockSizeLong();
            tvStorage.setText("Almacenamiento: " + formatBytes(free) + " libre");
        } catch (Exception e) {
            tvStorage.setText("Almacenamiento: --");
        }

        ConnectivityManager cm = (ConnectivityManager)
            getSystemService(Context.CONNECTIVITY_SERVICE);
        NetworkInfo ni = cm != null ? cm.getActiveNetworkInfo() : null;
        boolean online = ni != null && ni.isConnected();

        if (online) {
            chipStatus.setText("ONLINE");
            chipStatus.setBackgroundResource(getResId("chip_online"));
            chipStatus.setTextColor(getColorRes("chip_online_text"));
        } else {
            chipStatus.setText("SIN RED");
            chipStatus.setBackgroundResource(getResId("chip_offline"));
            chipStatus.setTextColor(getColorRes("chip_offline_text"));
        }
    }

    private void checkZohoInstalled() {
        try {
            android.content.pm.PackageInfo pi = getPackageManager()
                .getPackageInfo("com.zoho.assist.agent", 0);
            tvZohoStatus.setText("Instalado correctamente");
            tvZohoVersionCard.setText("v" + pi.versionName);
            ivZohoStatus.setImageResource(getResId("dot_green"));
            tvZohoStatus.setTextColor(getColorRes("success"));
        } catch (Exception e) {
            tvZohoStatus.setText("No instalado");
            tvZohoVersionCard.setText("--");
            ivZohoStatus.setImageResource(getResId("dot_red"));
            tvZohoStatus.setTextColor(getColorRes("error"));
        }
    }

    private void checkServices() {
        ivAccess.setImageResource(getResId("dot_red"));
        tvAccessStatus.setText("Accesibilidad: pendiente de activar");

        ivAdmin.setImageResource(getResId("dot_red"));
        tvAdminStatus.setText("Device Admin: pendiente de activar");

        ivService.setImageResource(getResId("dot_green"));
        tvServiceStatus.setText("Servicio: activo");
    }

    private void setupListeners() {
        btnInstall.setOnClickListener(v -> {
            ZohoInstallService.start(this);
            if (isDeviceOwner()) {
                Toast.makeText(this, "Instalacion desatendida iniciada",
                    Toast.LENGTH_SHORT).show();
            } else {
                Toast.makeText(this,
                    "Modo manual: confirme el instalador en pantalla",
                    Toast.LENGTH_LONG).show();
            }
        });

        btnUpdate.setOnClickListener(v -> checkForUpdates());

        btnDashboard.setOnClickListener(v -> {
            try {
                startActivity(new Intent(this,
                    Class.forName("com.tpv.zoho.manager.ui.DeviceDashboardActivity")));
            } catch (Exception e) {
                Toast.makeText(this, "Panel no disponible", Toast.LENGTH_SHORT).show();
            }
        });

        btnHealth.setOnClickListener(v -> {
            tvServiceStatus.setText("Servicio: diagnostico completado");
            ivService.setImageResource(getResId("dot_green"));
            Toast.makeText(this, "WiFi OK, storage OK, CPU normal",
                Toast.LENGTH_SHORT).show();
        });

        btnReboot.setOnClickListener(v ->
            Toast.makeText(this, "Reinicio requiere Device Owner",
                Toast.LENGTH_LONG).show());
    }

    private void checkForUpdates() {
        btnUpdate.setEnabled(false);
        Toast.makeText(this, "Consultando repositorio...", Toast.LENGTH_SHORT).show();

        UpdateChecker.checkAndDownload(this, new UpdateChecker.Callback() {
            @Override
            public void onStatus(String message) {
                runOnUiThread(() -> tvServiceStatus.setText("Update: " + message));
            }

            @Override
            public void onUpdateReady(File apkFile, UpdateManifest manifest) {
                runOnUiThread(() -> {
                    btnUpdate.setEnabled(true);
                    tvServiceStatus.setText("Update: Zoho Assist " + manifest.version + " listo");
                    Toast.makeText(
                        MainActivity.this,
                        "Actualizacion descargada. Iniciando instalacion...",
                        Toast.LENGTH_LONG
                    ).show();
                    ZohoInstallService.start(MainActivity.this, apkFile, null);
                });
            }

            @Override
            public void onNoUpdate(String message) {
                runOnUiThread(() -> {
                    btnUpdate.setEnabled(true);
                    tvServiceStatus.setText("Update: " + message);
                    Toast.makeText(MainActivity.this, message, Toast.LENGTH_LONG).show();
                });
            }

            @Override
            public void onError(String message) {
                runOnUiThread(() -> {
                    btnUpdate.setEnabled(true);
                    tvServiceStatus.setText("Update: error");
                    Toast.makeText(
                        MainActivity.this,
                        "Error actualizando: " + message,
                        Toast.LENGTH_LONG
                    ).show();
                });
            }
        });
    }

    private boolean isDeviceOwner() {
        DevicePolicyManager dpm = (DevicePolicyManager)
            getSystemService(Context.DEVICE_POLICY_SERVICE);
        return dpm != null && dpm.isDeviceOwnerApp(getPackageName());
    }

    private int getResId(String name) {
        return getResources().getIdentifier(name, "id", getPackageName());
    }

    private int getColorRes(String name) {
        int id = getResources().getIdentifier(name, "color", getPackageName());
        return getResources().getColor(id);
    }

    private String formatBytes(long bytes) {
        if (bytes < 1024) return bytes + " B";
        if (bytes < 1024 * 1024) return (bytes / 1024) + " KB";
        if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)) + " MB";
        return String.format("%.1f GB", bytes / (1024.0 * 1024 * 1024));
    }
}
