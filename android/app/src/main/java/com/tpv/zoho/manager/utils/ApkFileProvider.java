package com.tpv.zoho.manager.utils;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.webkit.MimeTypeMap;
import java.io.File;
import java.io.FileNotFoundException;

/**
 * ContentProvider propio para compartir archivos APK sin FileProvider de AndroidX.
 * Alternativa ligera a androidx.core.content.FileProvider.
 */
public class ApkFileProvider extends ContentProvider {

    private static final String AUTHORITY_SUFFIX = ".apkprovider";

    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        String path = uri.getPath();
        if (path == null) throw new FileNotFoundException("URI sin path: " + uri);

        // El path viene como /nombre_autoridad/ruta_real
        // Extraemos la ruta real después del authority
        String authority = getContext().getPackageName() + AUTHORITY_SUFFIX;
        int idx = path.indexOf(authority);
        if (idx >= 0) {
            path = path.substring(idx + authority.length());
        }

        File file = new File(path);
        if (!file.exists()) {
            throw new FileNotFoundException("Archivo no encontrado: " + path);
        }

        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY);
    }

    @Override
    public String getType(Uri uri) {
        String ext = MimeTypeMap.getFileExtensionFromUrl(uri.toString());
        String mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext);
        return mime != null ? mime : "application/octet-stream";
    }

    @Override public Cursor query(Uri u, String[] p, String s, String[] a, String o) { return null; }
    @Override public Uri insert(Uri u, ContentValues v) { return null; }
    @Override public int delete(Uri u, String s, String[] a) { return 0; }
    @Override public int update(Uri u, ContentValues v, String s, String[] a) { return 0; }

    /**
     * Construye un content:// URI para un archivo.
     */
    public static Uri getUriForFile(android.content.Context ctx, File file) {
        String authority = ctx.getPackageName() + AUTHORITY_SUFFIX;
        return new Uri.Builder()
            .scheme("content")
            .authority(authority)
            .path(file.getAbsolutePath())
            .build();
    }
}
