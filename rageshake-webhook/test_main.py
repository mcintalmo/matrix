from unittest.mock import patch

from fastapi.testclient import TestClient
import pytest

from main import app

client = TestClient(app)


def test_health_endpoint():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_options_cors_preflight():
    response = client.options(
        "/submit",
        headers={
            "Origin": "https://element-web.rumpusroom.xyz",
            "Access-Control-Request-Method": "POST",
        },
    )
    assert response.status_code == 200
    assert response.headers.get("access-control-allow-origin") == "*"


@patch("main.send_email")
def test_submit_multipart_form(mock_send_email):
    mock_send_email.return_value = True
    payload = {
        "text": "Call dropped after 30 seconds",
        "app": "Element Web",
        "version": "1.11.0",
    }
    files = {
        "file": ("rageshake.log.gz", b"simulated-compressed-log-data", "application/gzip"),
    }
    response = client.post("/submit", data=payload, files=files)
    assert response.status_code == 200
    assert response.json() == {"report_url": "delivered"}
    assert mock_send_email.called
    args, _ = mock_send_email.call_args
    assert "[Rageshake] Bug Report from Element Web" in args[0]
    assert "Call dropped after 30 seconds" in args[1]
    assert len(args[2]) == 1
    assert args[2][0]["filename"] == "rageshake.log.gz"
    assert args[2][0]["content"] == b"simulated-compressed-log-data"


@patch("main.send_email")
def test_submit_json_fallback(mock_send_email):
    mock_send_email.return_value = True
    payload = {
        "text": "WebRTC negotiation failed",
        "app": "Element Call",
        "version": "0.5.0",
    }
    response = client.post("/submit", json=payload)
    assert response.status_code == 200
    assert response.json() == {"report_url": "delivered"}
    assert mock_send_email.called
    args, _ = mock_send_email.call_args
    assert "[Rageshake] Bug Report from Element Call" in args[0]
    assert "WebRTC negotiation failed" in args[1]
    assert args[2] == []
