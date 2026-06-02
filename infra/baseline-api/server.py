import json
import os
import re
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

DATA_DIR = Path(os.environ.get("BASELINE_DATA_DIR", "/data"))
SAFE_PROJECT = re.compile(r"^[a-z0-9][a-z0-9_-]{0,99}$")


def send_json(handler, status, payload):
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            send_json(self, 200, {"status": "ok"})
            return
        send_json(self, 404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/snapshot":
            send_json(self, 404, {"error": "not found"})
            return
        if self.headers.get("X-PJ-Baseline") != "snapshot":
            send_json(self, 403, {"error": "missing request marker"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > 2_000_000:
                raise ValueError("invalid payload size")
            request = json.loads(self.rfile.read(length))
            project = request["project"]
            label = str(request.get("label", "")).strip()
            note = str(request.get("note", "")).strip()
            payload = request["payload"]
            if not SAFE_PROJECT.fullmatch(project):
                raise ValueError("invalid project identifier")
            if not label or len(label) > 100 or len(note) > 500:
                raise ValueError("invalid label or note")
            if payload.get("project_identifier") != project:
                raise ValueError("project mismatch")
            if not isinstance(payload.get("work_packages"), list):
                raise ValueError("invalid work packages")

            output_dir = DATA_DIR / project
            output_dir.mkdir(parents=True, exist_ok=True)
            captured_at = datetime.now(timezone.utc).isoformat()
            payload["captured_at"] = captured_at
            timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
            filename = f"baseline-{timestamp}.json"

            (output_dir / "current.json").write_text(
                json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
            )
            (output_dir / filename).write_text(
                json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
            )

            index_file = output_dir / "index.json"
            if index_file.exists():
                index = json.loads(index_file.read_text(encoding="utf-8"))
            else:
                index = {
                    "project_identifier": project,
                    "project_name": payload.get("project_name", project),
                    "baselines": [],
                }
            index["baselines"].insert(
                0,
                {"file": filename, "label": label, "note": note, "captured_at": captured_at},
            )
            index_file.write_text(
                json.dumps(index, ensure_ascii=False, indent=2), encoding="utf-8"
            )
            send_json(self, 201, {"file": filename, "captured_at": captured_at})
        except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
            send_json(self, 400, {"error": str(error)})

    def log_message(self, message, *args):
        print(f"{self.address_string()} - {message % args}", flush=True)


ThreadingHTTPServer(("0.0.0.0", 8090), Handler).serve_forever()
