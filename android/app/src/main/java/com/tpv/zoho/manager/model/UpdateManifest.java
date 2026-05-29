package com.tpv.zoho.manager.model;

import org.json.JSONObject;

public class UpdateManifest {
    public final String version;
    public final int versionCode;
    public final String apkUrl;
    public final String md5;
    public final int minSdk;
    public final long fileSize;
    public final String changelog;

    private UpdateManifest(
        String version,
        int versionCode,
        String apkUrl,
        String md5,
        int minSdk,
        long fileSize,
        String changelog
    ) {
        this.version = version;
        this.versionCode = versionCode;
        this.apkUrl = apkUrl;
        this.md5 = md5;
        this.minSdk = minSdk;
        this.fileSize = fileSize;
        this.changelog = changelog;
    }

    public static UpdateManifest fromJson(String json) throws Exception {
        JSONObject obj = new JSONObject(json);
        return new UpdateManifest(
            obj.optString("version", "0.0.0"),
            obj.optInt("version_code", 0),
            obj.optString("apk_url", ""),
            obj.optString("md5", ""),
            obj.optInt("min_sdk", 24),
            obj.optLong("file_size", 0),
            obj.optString("changelog", "")
        );
    }

    public boolean hasDownload() {
        return apkUrl != null && apkUrl.trim().length() > 0;
    }
}
