#!/usr/bin/env python3
"""Expose a small OpenAI-compatible chat endpoint backed by Hermes oneshot.

This adapter is for the Dolibarr dashboard's read-only business Q&A. It does
not expose the Hermes gateway, does not write Dolibarr data, and requires a
Bearer token. The dashboard supplies the current AI snapshot as context.
"""

from __future__ import annotations

import json
import os
import subprocess
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any


HOST = os.environ.get("HERMES_HTTP_HOST", "127.0.0.1")
PORT = int(os.environ.get("HERMES_HTTP_PORT", "8646"))
TOKEN = os.environ.get("HERMES_HTTP_TOKEN", "")
TIMEOUT = int(os.environ.get("HERMES_HTTP_TIMEOUT", "180"))
HERMES_PYTHON = os.environ.get("HERMES_PYTHON", "/usr/local/lib/hermes-agent/venv/bin/python")
HERMES_CWD = os.environ.get("HERMES_CWD", "/root/.hermes/skills/dolibarr-database")


def response_payload(request: dict[str, Any], content: str) -> dict[str, Any]:
    return {
        "id": "hermes-" + uuid.uuid4().hex,
        "object": "chat.completion",
        "created": int(time.time()),
        "model": request.get("model") or "hermes",
        "choices": [{
            "index": 0,
            "message": {"role": "assistant", "content": content},
            "finish_reason": "stop",
        }],
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "HermesOpenAIBridge/1.0"

    def log_message(self, format: str, *args: Any) -> None:
        print("hermes-http: " + (format % args), flush=True)

    def send_json(self, status: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        if self.path in ("/health", "/v1/health"):
            self.send_json(200, {"ok": True, "service": "hermes-openai-bridge"})
            return
        self.send_json(404, {"error": {"message": "Not found", "type": "not_found"}})

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/v1/chat/completions":
            self.send_json(404, {"error": {"message": "Not found", "type": "not_found"}})
            return
        if not TOKEN or self.headers.get("Authorization", "") != "Bearer " + TOKEN:
            self.send_json(401, {"error": {"message": "Unauthorized", "type": "authentication_error"}})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            request = json.loads(self.rfile.read(length).decode("utf-8"))
            messages = request.get("messages", [])
            if not isinstance(messages, list) or not messages:
                raise ValueError("messages must be a non-empty array")
            prompt_lines = [
                "你正在通过 Dolibarr AI 看板回答经营问题。",
                "只依据下面 messages 中提供的业务数据回答，不要修改数据库，不要编造数据。",
                "如果数据不足，请明确说明。请使用简洁中文回答。",
                "",
            ]
            for message in messages:
                role = str(message.get("role", "user"))
                content = message.get("content", "")
                if isinstance(content, list):
                    content = " ".join(str(item.get("text", "")) for item in content if isinstance(item, dict))
                prompt_lines.append(f"[{role}]\n{content}")
            completed = subprocess.run(
                [HERMES_PYTHON, "-m", "hermes_cli.main", "--oneshot", "\n\n".join(prompt_lines)],
                cwd=HERMES_CWD,
                capture_output=True,
                text=True,
                timeout=TIMEOUT,
                check=False,
            )
            answer = completed.stdout.strip()
            if completed.returncode != 0 or not answer:
                error = completed.stderr.strip()[-1000:] or "Hermes returned no answer"
                self.send_json(502, {"error": {"message": error, "type": "upstream_error"}})
                return
            self.send_json(200, response_payload(request, answer))
        except subprocess.TimeoutExpired:
            self.send_json(504, {"error": {"message": "Hermes request timed out", "type": "timeout"}})
        except (ValueError, json.JSONDecodeError) as exc:
            self.send_json(400, {"error": {"message": str(exc), "type": "invalid_request_error"}})
        except Exception as exc:  # pragma: no cover - service boundary
            self.send_json(500, {"error": {"message": str(exc), "type": "server_error"}})


if __name__ == "__main__":
    if not TOKEN:
        raise SystemExit("HERMES_HTTP_TOKEN is required")
    print(f"Hermes OpenAI bridge listening on {HOST}:{PORT}", flush=True)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
