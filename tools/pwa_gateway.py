#!/usr/bin/env python3
"""HTTPS-compatible companion for Godot's existing mobile UDP/TCP protocol.

Run on the DESKTOP machine; the browser cannot open raw UDP/TCP sockets.
No private creature data is uploaded, and this bridge never receives it.
Use Tailscale Serve for TLS; listen on loopback by default.
"""
from __future__ import annotations

import argparse
import hmac
import http.server
import ipaddress
import json
import os
from pathlib import Path
import secrets
import socket
import ssl
import struct
import sys
import uuid

ROOT = Path(__file__).resolve().parent.parent / "pwa"
ICON = Path(__file__).resolve().parent.parent / "icon.svg"
MAGIC = "VTT_TACTICAL_READ_V1"
ACTIONS = frozenset(("place_token", "claim_free_token", "snapshot", "move_token",
    "set_condition", "begin_spell", "target_spell", "cancel_spell", "finish_spell",
    "target_attack", "preview_spell", "set_appearance", "chat_send", "chat_poll"))
MAX_ACTION = 2 * 1024 * 1024
MAX_MAP = 60000
STATIC = {"/": ("index.html", "text/html; charset=utf-8"),
    "/index.html": ("index.html", "text/html; charset=utf-8"),
    "/app.js": ("app.js", "text/javascript; charset=utf-8"),
    "/network.js": ("network.js", "text/javascript; charset=utf-8"),
    "/storage.js": ("storage.js", "text/javascript; charset=utf-8"),
    "/sw.js": ("sw.js", "text/javascript; charset=utf-8"),
    "/manifest.webmanifest": ("manifest.webmanifest", "application/manifest+json")}


class BridgeError(Exception):
    pass


def _encode(message):
    return json.dumps(message, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def _receive_exact(sock, count):
    chunks = []
    while count:
        part = sock.recv(min(count, 65536))
        if not part:
            raise BridgeError("Desktop closed the TCP connection")
        chunks.append(part)
        count -= len(part)
    return b"".join(chunks)


def _session(value):
    if str(value) not in ("1", "2", "3", "4", "5"):
        raise ValueError("Session must be between 1 and 5")
    return str(value)


def valid_public_map(value):
    if not isinstance(value, dict) or value.get("version") != 1:
        return False
    tokens, combat = value.get("tokens"), value.get("combat")
    if not isinstance(tokens, list) or len(tokens) > 512 or not isinstance(combat, dict):
        return False
    if not isinstance(combat.get("active"), bool) or not isinstance(combat.get("entries"), list):
        return False
    if len(combat["entries"]) > 512:
        return False
    round_number, active_index = combat.get("round"), combat.get("active_index")
    if type(round_number) is not int or round_number < 1 or type(active_index) is not int:
        return False
    if not -1 <= active_index < len(combat["entries"]):
        return False
    ids = set()
    for token in tokens:
        if not isinstance(token, dict):
            return False
        token_id, name, conditions = token.get("id"), token.get("name"), token.get("conditions")
        if not isinstance(token_id, str) or not 0 < len(token_id) <= 120 or token_id in ids:
            return False
        if not isinstance(name, str) or len(name) > 256 or not isinstance(conditions, list):
            return False
        if len(conditions) > 64 or any(not isinstance(c, str) or len(c) > 256 for c in conditions):
            return False
        ids.add(token_id)
    for entry in combat["entries"]:
        if not isinstance(entry, dict) or not isinstance(entry.get("name"), str):
            return False
        if not isinstance(entry.get("token_id"), str) or type(entry.get("initiative")) not in (int, float):
            return False
    return True


def public_projection(value):
    """Defense in depth: only Android's public map fields reach a browser."""
    if not valid_public_map(value):
        raise BridgeError("Desktop returned invalid public map")
    fields = ("id", "name", "conditions", "free", "active_spell_ids",
              "current_miniature_id", "default_miniature_id")
    return {
        "version": 1,
        "mobile_protocol": value.get("mobile_protocol", 0),
        "tokens": [{k: row[k] for k in fields if k in row} for row in value["tokens"]],
        "combat": {"active": value["combat"]["active"],
                   "round": value["combat"]["round"],
                   "active_index": value["combat"]["active_index"],
                   "entries": [{k: row[k] for k in ("name", "token_id", "initiative") if k in row}
                               for row in value["combat"]["entries"]]},
    }


class GodotClient:
    def __init__(self, host="127.0.0.1", port=45457, timeout=3.5):
        self.host, self.port, self.timeout = host, port, timeout

    def map(self, session):
        session = _session(session)
        request_id = uuid.uuid4().hex
        message = _encode({"magic": MAGIC, "session": session,
                           "kind": "request", "request_id": request_id})
        # The response must come from the configured desktop, not another peer.
        target_ip = socket.gethostbyname(self.host)
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
            udp.settimeout(self.timeout)
            udp.sendto(message, (target_ip, self.port))
            while True:
                data, sender = udp.recvfrom(65535)
                if sender != (target_ip, self.port) or len(data) > MAX_MAP:
                    continue
                try:
                    response = json.loads(data)
                except (ValueError, UnicodeDecodeError):
                    continue
                if (isinstance(response, dict) and response.get("magic") == MAGIC
                    and response.get("session") == session and response.get("kind") == "response"
                    and response.get("request_id") == request_id):
                    return public_projection(response.get("data"))

    def action(self, session, action, payload):
        session = _session(session)
        if action not in ACTIONS or not isinstance(payload, dict):
            raise ValueError("Unsupported action or payload")
        request_id = uuid.uuid4().hex
        body = _encode({"magic": MAGIC, "session": session,
                        "request_id": request_id, "action": action, "payload": payload})
        if len(body) > MAX_ACTION:
            raise ValueError("Action payload too large")
        with socket.create_connection((self.host, self.port + 1), timeout=self.timeout) as tcp:
            tcp.settimeout(16)
            tcp.sendall(struct.pack("<I", len(body)) + body)  # PackedByteArray.encode_u32
            size = struct.unpack("<I", _receive_exact(tcp, 4))[0]
            if size <= 0 or size > MAX_ACTION:
                raise BridgeError("Invalid framed desktop response")
            try:
                response = json.loads(_receive_exact(tcp, size))
            except (ValueError, UnicodeDecodeError) as error:
                raise BridgeError("Invalid desktop JSON") from error
            if (not isinstance(response, dict) or response.get("magic") != MAGIC
                or response.get("session") != session
                or response.get("request_id") != request_id
                or not isinstance(response.get("result"), dict)):
                raise BridgeError("Desktop reply did not match the request")
            try:
                tcp.sendall(b"\x01")  # Godot expects client ACK after a complete image.
            except OSError:
                pass
            return response["result"]


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "VTTPWAGateway/1"
    def log_message(self, format, *args):
        sys.stderr.write("%s %s\n" % (self.address_string(), format % args))

    def reply(self, code, content, mime="application/json; charset=utf-8"):
        if isinstance(content, dict):
            content = _encode(content)
        self.send_response(code)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Cache-Control", "no-store" if self.path.startswith("/api/") else "no-cache")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Frame-Options", "DENY")
        self.end_headers()
        self.wfile.write(content)

    def do_GET(self):
        if self.path == "/icon.svg":
            return self.reply(200, ICON.read_bytes(), "image/svg+xml")
        if self.path not in STATIC:
            return self.reply(404, {"error": "Not found"})
        file_name, mime = STATIC[self.path]
        return self.reply(200, (ROOT / file_name).read_bytes(), mime)

    def do_POST(self):
        if self.path not in ("/api/v1/map", "/api/v1/action"):
            return self.reply(404, {"error": "Not found"})
        origin = self.headers.get("Origin")
        # No CORS support: direct requests from a different website are rejected.
        if origin:
            from urllib.parse import urlsplit
            o = urlsplit(origin)
            if o.netloc != self.headers.get("Host") or o.scheme not in ("http", "https"):
                return self.reply(403, {"error": "Cross-origin request rejected"})
        header = self.headers.get("Authorization", "")
        if not hmac.compare_digest(header, "Bearer " + self.server.token):
            return self.reply(401, {"error": "Pairing token required"})
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if not 1 <= size <= MAX_ACTION:
                return self.reply(413, {"error": "Invalid request size"})
            body = json.loads(self.rfile.read(size))
            if not isinstance(body, dict):
                raise ValueError("Expected object")
            session = _session(body.get("session"))
            if self.path.endswith("/map"):
                data = self.server.client.map(session)
                return self.reply(200, {"data": data})
            result = self.server.client.action(session, body.get("action"), body.get("payload"))
            return self.reply(200, {"result": result})
        except (ValueError, TypeError) as error:
            return self.reply(400, {"error": str(error)})
        except (OSError, TimeoutError, BridgeError) as error:
            return self.reply(502, {"error": str(error)})


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1", help="Gateway bind IP; default loopback")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--board-host", default="127.0.0.1", help="Desktop Godot IPv4")
    parser.add_argument("--board-port", type=int, default=45457)
    parser.add_argument("--cert", help="Trusted TLS certificate, for direct LAN use")
    parser.add_argument("--key", help="TLS private key")
    args = parser.parse_args(argv)
    if bool(args.cert) != bool(args.key):
        parser.error("--cert and --key must be supplied together")
    if not ipaddress.ip_address(args.host).is_loopback and not args.cert:
        parser.error("Non-loopback binds require TLS; use Tailscale Serve with loopback instead")
    token = os.environ.get("VTT_PWA_TOKEN") or secrets.token_urlsafe(32)
    if len(token) < 16:
        parser.error("VTT_PWA_TOKEN must contain at least 16 characters")
    server = http.server.ThreadingHTTPServer((args.host, args.port), Handler)
    server.token = token
    server.client = GodotClient(args.board_host, args.board_port)
    if args.cert:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(args.cert, args.key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
    print("VTT PWA gateway at %s://%s:%s" % ("https" if args.cert else "http", args.host, args.port), flush=True)
    print("Pairing token (keep private): " + token, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
