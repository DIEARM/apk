package com.tpv.zoho.manager.ui;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.net.ConnectivityManager;
import android.net.NetworkInfo;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.os.StatFs;
import android.widget.Button;
import android.widget.TextView;
import java.io.BufferedReader;
import java.io.FileReader;

public class DeviceDashboardActivity extends Activity {

    private TextView tvDevice, tvBattery, tvStorage, tvRam, tvUptime;
    private TextView tvModel, tvAndroid, tvSdk, tvZoho, tvNetwork;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        setContentView(getResources().getIdentifier(
            "activity_dashboard", "layout", getPackageName()));

        bindViews();
        loadMetrics();
        loadDetails();

        findViewById(getResId("btn_back")).setOnClickListener(v -> finish());
    }

    private void bindViews() {
        tvDevice = findViewById(getResId("tv_dashboard_device"));
        tvBattery = findViewById(getResId("tv_metric_battery"));
        tvStorage = findViewById(getResId("tv_metric_storage"));
        tvRam = findViewById(getResId("tv_metric_ram"));
        tvUptime = findViewById(getResId("tv_metric_uptime"));
        tvModel = findViewById(getResId("tv_detail_model"));
        tvAndroid = findViewById(getResId("tv_detail_android"));
        tvSdk = findViewById(getResId("tv_detail_sdk"));
        tvZoho = findViewById(getResId("tv_detail_zoho"));
        tvNetwork = findViewById(getResId("tv_detail_network"));
    }

    private void loadMetrics() {
        tvDevice.setText(Build.MANUFACTURER + " " + Build.MODEL);

        // Batería
        Intent batIntent = registerReceiver(null,
            new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
        if (batIntent != null) {
            int level = batIntent.getIntExtra(
                android.os.BatteryManager.EXTRA_LEVEL, -1);
            int scale = batIntent.getIntExtra(
                android.os.BatteryManager.EXTRA_SCALE, 100);
            int pct = (int)(level * 100f / scale);

            String icon = pct > 75 ? "🟢 " : pct > 30 ? "🟡 " : "🔴 ";
            tvBattery.setText(icon + pct + "%");

            int plugged = batIntent.getIntExtra(
                android.os.BatteryManager.EXTRA_PLUGGED, -1);
            if (plugged > 0) tvBattery.append(" ⚡");
        }

        // Almacenamiento
        try {
            StatFs stat = new StatFs(Environment.getDataDirectory().getPath());
            long total = stat.getBlockCountLong() * stat.getBlockSizeLong();
            long free = stat.getAvailableBlocksLong() * stat.getBlockSizeLong();
            long usedPct = (total - free) * 100 / total;
            tvStorage.setText(free / (1024 * 1024) + " MB\n" + usedPct + "% usado");
        } catch (Exception e) {
            tvStorage.setText("--");
        }

        // RAM
        try {
            BufferedReader reader = new BufferedReader(
                new FileReader("/proc/meminfo"));
            String line;
            long totalRam = 0, freeRam = 0;
            while ((line = reader.readLine()) != null) {
                if (line.startsWith("MemTotal:"))
                    totalRam = parseKb(line);
                if (line.startsWith("MemAvailable:"))
                    freeRam = parseKb(line);
            }
            reader.close();
            if (totalRam > 0 && freeRam > 0) {
                tvRam.setText(freeRam / 1024 + " MB\n" +
                    ((totalRam - freeRam) * 100 / totalRam) + "% usado");
            } else {
                tvRam.setText("--");
            }
        } catch (Exception e) {
            tvRam.setText("--");
        }

        // Uptime
        try {
            long uptime = android.os.SystemClock.elapsedRealtime() / 1000;
            long h = uptime / 3600;
            long m = (uptime % 3600) / 60;
            tvUptime.setText(h + "h " + m + "m");
        } catch (Exception e) {
            tvUptime.setText("--");
        }
    }

    private void loadDetails() {
        tvModel.setText("Modelo: " + Build.MANUFACTURER + " " + Build.MODEL);
        tvAndroid.setText("Android: " + Build.VERSION.RELEASE);
        tvSdk.setText("SDK: " + Build.VERSION.SDK_INT);

        // Zoho Assist
        try {
            android.content.pm.PackageInfo pi = getPackageManager()
                .getPackageInfo("com.zoho.assist.agent", 0);
            tvZoho.setText("Zoho Assist: v" + pi.versionName + " ✅");
        } catch (Exception e) {
            tvZoho.setText("Zoho Assist: No instalado ❌");
        }

        // Network
        ConnectivityManager cm = (ConnectivityManager)
            getSystemService(Context.CONNECTIVITY_SERVICE);
        NetworkInfo ni = cm != null ? cm.getActiveNetworkInfo() : null;
        if (ni != null && ni.isConnected()) {
            String type = ni.getTypeName().toUpperCase();
            tvNetwork.setText("Red: " + type + " ● Conectado");
        } else {
            tvNetwork.setText("Red: Sin conexión");
        }
    }

    private long parseKb(String line) {
        String[] parts = line.split("\\s+");
        for (String p : parts) {
            try { return Long.parseLong(p); } catch (NumberFormatException ignored) {}
        }
        return 0;
    }

    private int getResId(String name) {
        return getResources().getIdentifier(name, "id", getPackageName());
    }
}
