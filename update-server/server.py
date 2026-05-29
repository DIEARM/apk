#!/usr/bin/env python3
"""
Zoho TPV Update Server - servidor ligero de actualizaciones para APK/XAPK.
Sirve manifest.json y paquetes con verificacion MD5.
Ejecutar: python server.py
"""
import hashlib
import json
import os
import time
from datetime import datetime, timezone
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from typing import Optional

ROOT = Path(__file__).resolve().parent
APK_DIR = ROOT / "apks"
MANIFEST_FILE = ROOT / "manifest.json"
HOST = os.environ.get("HOST", "0.0.0.0")
PORT = int(os.environ.get("PORT", "8080"))


def md5_file(path: Path) -> str:
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def latest_package() -> Optional[Path]:
    xapk = APK_DIR / "zoho_assist.xapk"
    if xapk.exists():
        return xapk
    apks = sorted(APK_DIR.glob("*.apk"), reverse=True)
    return apks[0] if apks else None


def build_manifest() -> dict:
    latest = latest_package()
    if latest is None:
        return {
            "version": "0.0.0",
            "version_code": 0,
            "release_date": "",
            "apk_url": "",
            "xapk_url": "",
            "md5": "",
            "min_sdk": 24,
            "changelog": "No hay paquetes disponibles",
            "error": "APK_DIR vacio",
        }

    is_xapk = latest.suffix.lower() == ".xapk"
    return {
        "version": "1.44.2" if is_xapk else "1.0.0",
        "version_code": 162 if is_xapk else 10000,
        "release_date": datetime.fromtimestamp(
            latest.stat().st_mtime, tz=timezone.utc
        ).strftime("%Y-%m-%d"),
        "apk_url": f"/zoho/stable/{latest.name}",
        "xapk_url": "/zoho/stable/zoho_assist.xapk" if is_xapk else "",
        "md5": md5_file(latest),
        "min_sdk": 22 if is_xapk else 24,
        "package_type": latest.suffix.lstrip("."),
        "package_name": latest.name,
        "changelog": "Zoho Assist Customer para despliegue TPV automatizado",
        "file_size": latest.stat().st_size,
    }


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{ts}] {self.address_string()} {fmt % args}")

    def _json(self, data: dict, status: int = 200):
        body = json.dumps(data, indent=2, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(body))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _file(self, path: Path, content_type: str):
        if not path.exists():
            self.send_error(404)
            return
        data = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", len(data))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = self.path.rstrip("/")

        if path == "/health":
            self._json({"status": "ok", "uptime": time.time() - START_TIME})
        elif path == "/zoho/stable/manifest.json":
            self._json(build_manifest())
        elif path == "/zoho/stable/zoho_assist.xapk":
            self._file(APK_DIR / "zoho_assist.xapk", "application/octet-stream")
        elif path == "/zoho/stable/zoho_assist.apk":
            direct_apk = APK_DIR / "zoho_assist_xapk" / "com.zoho.assist.agent.apk"
            if direct_apk.exists():
                self._file(direct_apk, "application/vnd.android.package-archive")
            else:
                self.send_error(404, "No APK disponible")
        elif path == "" or path == "/":
            self._json({
                "service": "Zoho TPV Update Server",
                "endpoints": {
                    "/health": "Health check",
                    "/zoho/stable/manifest.json": "Metadata version actual",
                    "/zoho/stable/zoho_assist.xapk": "Descarga XAPK",
                    "/zoho/stable/zoho_assist.apk": "Descarga APK base",
                    "/upload": "POST - subir nueva version",
                },
            })
        else:
            self.send_error(404)

    def do_POST(self):
        if self.path.rstrip("/") != "/upload":
            self.send_error(404)
            return

        content_type = self.headers.get("Content-Type", "")
        if "multipart/form-data" not in content_type:
            self._json({"error": "Usa multipart/form-data"}, 400)
            return

        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)
        boundary = content_type.split("boundary=")[1].encode() if "boundary=" in content_type else b""
        if not boundary:
            self._json({"error": "Falta boundary"}, 400)
            return

        parts = body.split(b"--" + boundary)
        for part in parts:
            if b"filename=" not in part:
                continue
            header_end = part.find(b"\r\n\r\n")
            if header_end == -1:
                continue
            content = part[header_end + 4:]
            if content.endswith(b"\r\n"):
                content = content[:-2]

            APK_DIR.mkdir(parents=True, exist_ok=True)
            filename = "zoho_assist.xapk" if b".xapk" in part.lower() else "zoho_assist.apk"
            filepath = APK_DIR / filename
            filepath.write_bytes(content)

            manifest = build_manifest()
            MANIFEST_FILE.write_text(json.dumps(manifest, indent=2, ensure_ascii=False))
            self._json({
                "ok": True,
                "file": filename,
                "md5": md5_file(filepath),
                "size": len(content),
                "manifest": manifest,
            }, 201)
            return

        self._json({"error": "No se encontro archivo en la peticion"}, 400)


START_TIME = time.time()

if __name__ == "__main__":
    APK_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Zoho TPV Update Server - http://{HOST}:{PORT}")
    print(f"  APK dir : {APK_DIR}")
    print(f"  Manifest: {MANIFEST_FILE}")
    HTTPServer((HOST, PORT), Handler).serve_forever()
