"""Serve solo i file selezionati del backup Android al connettore iOS sulla LAN."""
import argparse
import datetime as dt
import hashlib
import http.server
import ipaddress
import json
import secrets
import socket
import sys
from pathlib import Path
from urllib.parse import urlsplit

FILE_CATEGORIES = {"foto", "video", "documenti", "musica"}


def selected_files(backup, categories):
    backup = Path(backup).resolve()
    data = json.loads((backup / "manifest.json").read_text(encoding="utf-8"))
    root = (backup / "files").resolve()
    items = []
    for category in categories:
        if category not in FILE_CATEGORIES:
            raise ValueError(f"Categoria file non supportata dal bridge: {category}")
        for source_name in data.get("categorie", {}).get(category, {}).get("file", []):
            if not str(source_name).startswith("/sdcard/"):
                raise ValueError("Il backup contiene un percorso file inatteso")
            relative = Path(*Path(source_name).parts[2:])
            source = (root / relative).resolve()
            if not source.is_relative_to(root) or not source.is_file():
                raise ValueError("File sorgente mancante o esterno al backup")
            digest = hashlib.sha256()
            with source.open("rb") as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(block)
            stat = source.stat()
            items.append({
                "id": secrets.token_hex(12),
                "category": category,
                "filename": source.name,
                "bytes": stat.st_size,
                "sha256": digest.hexdigest(),
                "url": "",
                "createdAt": dt.datetime.fromtimestamp(stat.st_mtime, dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
                "_path": str(source),
            })
    return data, items


class BridgeHandler(http.server.BaseHTTPRequestHandler):
    server_version = "MatisseBridge/1"

    def do_GET(self):
        route = urlsplit(self.path).path.strip("/").split("/")
        if len(route) < 2 or not secrets.compare_digest(route[0], self.server.token):
            self.send_error(404)
            return
        if route[1] == "manifest" and len(route) == 2:
            body = json.dumps(self.server.manifest, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if route[1] == "files" and len(route) == 3:
            item = self.server.files.get(route[2])
            if item is None:
                self.send_error(404)
                return
            source = Path(item["_path"])
            try:
                with source.open("rb") as stream:
                    self.send_response(200)
                    self.send_header("Content-Type", "application/octet-stream")
                    self.send_header("Content-Length", str(item["bytes"]))
                    self.send_header("Content-Disposition", "attachment")
                    self.end_headers()
                    for block in iter(lambda: stream.read(1024 * 1024), b""):
                        self.wfile.write(block)
            except (ConnectionError, BrokenPipeError):
                pass
            return
        self.send_error(404)

    def log_message(self, fmt, *args):
        print("Matisse bridge: " + fmt % args, file=sys.stderr)


def lan_addresses():
    addresses = set()
    for result in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET, socket.SOCK_STREAM):
        address = result[4][0]
        parsed = ipaddress.ip_address(address)
        if parsed.is_private or parsed.is_link_local:
            addresses.add(address)
    return sorted(addresses)


def create_server(backup, categories, host="0.0.0.0", port=8765):
    source, items = selected_files(backup, categories)
    token = secrets.token_urlsafe(24)
    for item in items:
        item["url"] = f"/files/{item['id']}"
    manifest = {"version": 1, "items": [{k: v for k, v in item.items() if not k.startswith("_")}
                                          for item in items]}
    server = http.server.ThreadingHTTPServer((host, port), BridgeHandler)
    server.token = token
    server.manifest = manifest
    server.files = {item["id"]: item for item in items}
    addresses = lan_addresses()
    details = {"source": source.get("modello"), "count": len(items),
               "bytes": sum(item["bytes"] for item in items),
               "urls": [f"http://{address}:{server.server_port}/{token}" for address in addresses]}
    return server, details


def serve(backup, categories, host="0.0.0.0", port=8765):
    server, details = create_server(backup, categories, host, port)
    print(f"Backup: {details['source']} · {details['count']} file selezionati")
    if not details["count"]:
        print("Nessun file per le categorie scelte.")
        server.server_close()
        return
    for url in details["urls"]:
        print(f"Sul connettore iPhone inserisci: {url}")
    if not details["urls"]:
        print(f"Indirizzo host non determinato; porta bridge: {server.server_port}")
    print("Il server espone solo questi file e resta attivo fino a Ctrl+C.")
    try:
        server.serve_forever(poll_interval=0.25)
    except KeyboardInterrupt:
        print("Trasferimento locale terminato.")
    finally:
        server.server_close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backup", type=Path, required=True)
    parser.add_argument("--only", required=True, help="foto,video,documenti,musica")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    categories = [item.strip() for item in args.only.split(",") if item.strip()]
    if not categories or len(categories) != len(set(categories)):
        parser.error("Seleziona almeno una categoria senza ripetizioni")
    serve(args.backup, categories, args.host, args.port)
