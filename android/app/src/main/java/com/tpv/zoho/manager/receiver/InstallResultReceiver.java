package com.tpv.zoho.manager.receiver;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInstaller;
import android.util.Log;
import android.widget.Toast;

public class InstallResultReceiver extends BroadcastReceiver {
    private static final String TAG = "InstallResultReceiver";

    @Override
    public void onReceive(Context context, Intent intent) {
        int status = intent.getIntExtra(
            PackageInstaller.EXTRA_STATUS,
            PackageInstaller.STATUS_FAILURE
        );
        String detail = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE);
        Log.i(TAG, "PackageInstaller status=" + status + " detail=" + detail);

        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            Intent confirmation = intent.getParcelableExtra(Intent.EXTRA_INTENT);
            if (confirmation != null) {
                Log.i(TAG, "Launching install confirmation");
                confirmation.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                context.startActivity(confirmation);
            } else {
                Log.w(TAG, "Pending user action without confirmation intent");
            }
            return;
        }

        String message;
        if (status == PackageInstaller.STATUS_SUCCESS) {
            message = "Zoho Assist instalado correctamente";
            launchZohoAssist(context);
        } else {
            message = "Error instalando Zoho Assist"
                + (detail != null ? ": " + detail : "");
        }
        Toast.makeText(context, message, Toast.LENGTH_LONG).show();
    }

    private void launchZohoAssist(Context context) {
        Intent launch = context.getPackageManager()
            .getLaunchIntentForPackage("com.zoho.assist.agent");
        if (launch != null) {
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(launch);
        }
    }
}
