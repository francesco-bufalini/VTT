#!/usr/bin/env python3
"""Targeted protocol tests. No Godot process, browser or external network required."""
import importlib.util
import json
import pathlib
import socket
import struct
import threading
import unittest
from http.server import ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.request import Request, urlopen

MODULE = pathlib.Path(__file__).resolve().parents[1] / "tools" / "pwa_gateway.py"
spec = importlib.util.spec_from_file_location("vtt_pwa_gateway", MODULE)
gateway = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gateway)

PUBLIC_MAP = {
    "version": 1, "mobile_protocol": 2,
    "tokens": [{"id": "token-1", "name": "Hero", "conditions": [], "free": False,
                "secret_inventory": ["Do not share"]}],
    "combat": {"active": True, "round": 2, "active_index": 0,
               "entries": [{"name": "Hero", "token_id": "token-1", "initiative": 12.0}]},
    "private_creatures": [{"name": "Hidden"}],
}


class MockGodot:
    def __enter__(self):
        self.udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.udp.bind(("127.0.0.1", 0))
        self.udp.settimeout(4)
        self.port = self.udp.getsockname()[1]
        self.tcp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.tcp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.tcp.bind(("127.0.0.1", self.port + 1))
        self.tcp.listen(4)
        self.tcp.settimeout(4)
        self.stop = threading.Event()
        self.acked = threading.Event()
        self.udp_thread = threading.Thread(target=self.udp_loop, daemon=True)
        self.tcp_thread = threading.Thread(target=self.tcp_loop, daemon=True)
        self.udp_thread.start()
        self.tcp_thread.start()
        return self

    def udp_loop(self):
        while not self.stop.is_set():
            try:
                body, address = self.udp.recvfrom(65535)
            except OSError:
                return
            message = json.loads(body)
            if message.get("kind") != "request":
                continue
            # Send wrong-session response first to verify request matching.
            self.udp.sendto(gateway._encode({
                "magic": gateway.MAGIC, "kind": "response", "session": "invalid",
                "request_id": message["request_id"], "data": PUBLIC_MAP}), address)
            self.udp.sendto(gateway._encode({
                "magic": gateway.MAGIC, "kind": "response", "session": message["session"],
                "request_id": message["request_id"], "data": PUBLIC_MAP}), address)

    def tcp_loop(self):
        while not self.stop.is_set():
            try:
                connection, _ = self.tcp.accept()
            except OSError:
                return
            with connection:
                connection.settimeout(4)
                try:
                    size = struct.unpack("<I", gateway._receive_exact(connection, 4))[0]
                    message = json.loads(gateway._receive_exact(connection, size))
                    reply = {"magic": gateway.MAGIC, "session": message["session"],
                             "request_id": message["request_id"],
                             "result": {"ok": True, "action": message["action"],
                                        "payload": message["payload"]}}
                    encoded = gateway._encode(reply)
                    connection.sendall(struct.pack("<I", len(encoded)) + encoded)
                    if connection.recv(1) == b"\x01":
                        self.acked.set()
                except OSError:
                    continue

    def __exit__(self, *args):
        self.stop.set()
        self.udp.close()
        self.tcp.close()
        self.udp_thread.join(timeout=1)
        self.tcp_thread.join(timeout=1)


class ProtocolTests(unittest.TestCase):
    def test_native_udp_public_projection(self):
        with MockGodot() as server:
            data = gateway.GodotClient(port=server.port).map("1")
            self.assertEqual(data["tokens"][0]["name"], "Hero")
            self.assertEqual(data["mobile_protocol"], 2)
            self.assertNotIn("secret_inventory", data["tokens"][0])
            self.assertNotIn("private_creatures", data)

    def test_native_tcp_actions_and_ack(self):
        with MockGodot() as server:
            response = gateway.GodotClient(port=server.port).action(
                "2", "chat_poll", {"after": 3})
            self.assertEqual(response, {"ok": True, "action": "chat_poll",
                                        "payload": {"after": 3}})
            self.assertTrue(server.acked.wait(2))

    def test_invalid_sessions_and_actions(self):
        with self.assertRaises(ValueError):
            gateway.GodotClient().map("not-a-session")
        with self.assertRaises(ValueError):
            gateway.GodotClient().action("1", "arbitrary_file_read", {})

    def test_invalid_map_rejected(self):
        invalid = dict(PUBLIC_MAP)
        invalid["tokens"] = [{"id": "dup", "name": "A", "conditions": []},
                             {"id": "dup", "name": "B", "conditions": []}]
        with self.assertRaises(gateway.BridgeError):
            gateway.public_projection(invalid)

    def test_http_token_and_same_origin(self):
        with MockGodot() as game:
            web = ThreadingHTTPServer(("127.0.0.1", 0), gateway.Handler)
            web.client = gateway.GodotClient(port=game.port)
            web.token = "12345678901234567890123456789012"
            thread = threading.Thread(target=web.serve_forever, daemon=True)
            thread.start()
            try:
                url = "http://127.0.0.1:%d/api/v1/map" % web.server_address[1]
                body = b'{"session":"1"}'
                with self.assertRaises(HTTPError) as unauth:
                    urlopen(Request(url, data=body, headers={"Content-Type": "application/json"}))
                self.assertEqual(unauth.exception.code, 401)
                headers = {"Content-Type": "application/json",
                           "Authorization": "Bearer " + web.token,
                           "Origin": "https://evil.example"}
                with self.assertRaises(HTTPError) as cross_origin:
                    urlopen(Request(url, data=body, headers=headers))
                self.assertEqual(cross_origin.exception.code, 403)
                headers.pop("Origin")
                with urlopen(Request(url, data=body, headers=headers)) as response:
                    data = json.load(response)
                    self.assertEqual(data["data"]["tokens"][0]["id"], "token-1")
            finally:
                web.shutdown()
                web.server_close()
                thread.join(timeout=2)


if __name__ == "__main__":
    unittest.main()
