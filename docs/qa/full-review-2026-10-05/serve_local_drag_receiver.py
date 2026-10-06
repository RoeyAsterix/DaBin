#!/usr/bin/env python3
"""Explicit, bounded loopback-only server for the fixed fictional drag receiver.

Without --serve, prints the plan and creates no files/socket/process. With
--serve, copies only local_drag_receiver.html to a fresh /private/tmp directory,
serves its already-read bytes on one random route, and writes an owned receipt.
Never serves a directory, opens a browser, accepts uploads or contacts a server.
"""
import argparse
import datetime
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import signal
import tempfile
import time
import uuid

CSP = ("default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; "
       "connect-src 'none'; img-src 'none'; media-src 'none'; object-src 'none'; "
       "frame-src 'none'; frame-ancestors 'none'; form-action 'none'; base-uri 'none'")


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serve", action="store_true", help="Explicitly start after coordinated GUI/stress QA finishes")
    parser.add_argument("--port", type=int, default=0, help="Loopback port; default 0 chooses a fresh available port")
    parser.add_argument("--duration", type=int, default=900, help="Maximum serving seconds, 1–1800; default 900")
    args = parser.parse_args()
    if not 0 <= args.port <= 65535:
        parser.error("port must be 0–65535")
    if not 1 <= args.duration <= 1800:
        parser.error("duration must be 1–1800 seconds")
    if not args.serve:
        print(json.dumps({"status": "PREPARED_NOT_STARTED", "bindHost": "127.0.0.1",
                          "serves": "One exact random route with fixed fictional receiver HTML only",
                          "directoryListing": False, "uploads": False, "browserLaunch": False,
                          "workspaceServed": False, "networkConnectionsInitiated": False,
                          "nextStep": "Use --serve only after the coordinator releases the GUI/stress stage."}, indent=2))
        return

    source = Path(__file__).with_name("local_drag_receiver.html")
    body = source.read_bytes()
    if not 0 < len(body) <= 131072:
        raise SystemExit("Fixed fictional receiver must contain 1–131072 bytes.")
    stage = Path(tempfile.mkdtemp(prefix="DaBin-Drag-Receiver-", dir="/private/tmp"))
    staged_html = stage / "receiver.html"
    staged_html.write_bytes(body)
    receipt_path = stage / "server-receipt.json"
    route = "/" + uuid.uuid4().hex + "/receiver.html"
    request_counts = {"receiverGET": 0, "receiverHEAD": 0, "denied": 0}
    state = {"stopping": False, "reason": "duration_limit"}
    server = None

    class ReceiverHandler(BaseHTTPRequestHandler):
        server_version = "DaBinFictionalReceiver"
        sys_version = ""

        def setup(self):
            super().setup()
            self.connection.settimeout(3)

        def log_message(self, format, *values):
            # Do not log request bodies, arbitrary paths/queries or user data.
            pass

        def respond(self, head=False):
            own_host = "127.0.0.1:" + str(self.server.server_address[1])
            own_origin = "http://" + own_host
            allowed = (self.client_address[0] == "127.0.0.1"
                       and self.headers.get("Host") == own_host
                       and self.headers.get("Origin") in (None, own_origin)
                       and self.path == route)
            data = body if allowed else b"Not found.\n"
            request_counts[("receiverHEAD" if head else "receiverGET") if allowed else "denied"] += 1
            self.send_response(200 if allowed else 404)
            self.send_header("Content-Type", "text/html; charset=utf-8" if allowed else "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Content-Security-Policy", CSP)
            self.send_header("Cache-Control", "no-store")
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("X-Frame-Options", "DENY")
            self.send_header("Cross-Origin-Resource-Policy", "same-origin")
            self.send_header("Connection", "close")
            self.end_headers()
            if not head:
                self.wfile.write(data)
            self.close_connection = True

        def do_GET(self):
            self.respond()

        def do_HEAD(self):
            self.respond(head=True)

        def reject_write(self):
            request_counts["denied"] += 1
            self.send_response(405)
            self.send_header("Allow", "GET, HEAD")
            self.send_header("Content-Length", "0")
            self.send_header("Connection", "close")
            self.end_headers()
            self.close_connection = True

        do_POST = reject_write
        do_PUT = reject_write
        do_PATCH = reject_write
        do_DELETE = reject_write
        do_OPTIONS = reject_write

    def stop(signum, frame):
        state["stopping"] = True
        state["reason"] = signal.Signals(signum).name

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    receipt = {"status": "STARTING", "startedAtUTC": utc(), "ownedPID": os.getpid(), "ownedUID": os.getuid(),
               "script": str(Path(__file__).resolve()), "scriptSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
               "stage": str(stage), "stagedHTML": str(staged_html), "receipt": str(receipt_path),
               "receiverSHA256": hashlib.sha256(body).hexdigest(), "bindHost": "127.0.0.1",
               "durationLimitSeconds": args.duration, "browserLaunched": False,
               "scope": "One fixed fictional receiver route; no arbitrary directory/file serving, uploads, source archive/clipboard access, workspace/KARI data, outbound connections or GUI action. HTTP receipt alone is not drag acceptance."}
    try:
        server = HTTPServer(("127.0.0.1", args.port), ReceiverHandler)
        server.timeout = 0.5
        receipt.update(status="SERVING", port=server.server_address[1],
                       url="http://127.0.0.1:" + str(server.server_address[1]) + route)
        receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
        print(json.dumps(receipt, indent=2), flush=True)
        deadline = time.monotonic() + args.duration
        while not state["stopping"] and time.monotonic() < deadline:
            server.handle_request()
    except Exception as error:
        receipt["error"] = str(error)
        state["reason"] = "server_error"
        raise
    finally:
        if server is not None:
            server.server_close()
        receipt.update(status="STOPPED", stoppedAtUTC=utc(), stopReason=state["reason"], requestCounts=request_counts)
        receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
        print(json.dumps({"status": "STOPPED", "receipt": str(receipt_path), "reason": state["reason"]}), flush=True)


if __name__ == "__main__":
    main()
