from __future__ import annotations

import logging
import os
import smtplib
from email.message import EmailMessage
from typing import Any

from fastapi import BackgroundTasks, FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

logger = logging.getLogger("rageshake_webhook")
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

app = FastAPI(title="Rageshake Webhook", version="0.1.0")

# Relax CORS so any Element Web domain can successfully submit POST / OPTIONS preflights
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# SMTP Config securely parsed from docker-compose.yml / .env
SMTP_SERVER = os.environ.get("SMTP_SERVER", "smtp.gmail.com")
SMTP_PORT = int(os.environ.get("SMTP_PORT", 587))
SMTP_USER = os.environ.get("SMTP_USER") or os.environ.get("GMAIL_ACCOUNT", "")
SMTP_PASS = os.environ.get("SMTP_PASS") or os.environ.get("GMAIL_APP_PASSWORD", "")
TO_EMAIL = (
    os.environ.get("RAGESHAKE_FORWARD_EMAIL")
    or os.environ.get("GMAIL_ACCOUNT", "rumpusroom.xyz@google.com")
)


def send_email(subject: str, body: str, attached_files: list[dict[str, Any]] | None = None) -> bool:
    logger.info("Preparing to send Rageshake email to %s...", TO_EMAIL)
    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = SMTP_USER if SMTP_USER else TO_EMAIL
    msg["To"] = TO_EMAIL
    msg.set_content(body)

    if attached_files:
        for file in attached_files:
            msg.add_attachment(
                file["content"],
                maintype="application",
                subtype="octet-stream",
                filename=file["filename"],
            )

    try:
        with smtplib.SMTP(SMTP_SERVER, SMTP_PORT, timeout=15) as server:
            server.starttls()
            if SMTP_USER and SMTP_PASS:
                server.login(SMTP_USER, SMTP_PASS)
            server.send_message(msg)
            logger.info("Successfully forwarded Rageshake logs to %s", TO_EMAIL)
            return True
    except Exception as e:
        logger.error("Failed to send email via SMTP: %s", e)
        return False


@app.get("/health")
async def health_check() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/submit")
@app.options("/submit")
async def submit_rageshake(request: Request, background_tasks: BackgroundTasks) -> dict[str, str]:
    content_type = request.headers.get("content-type", "")
    if "application/json" in content_type:
        try:
            data = await request.json()
            text = data.get("text", "No User Text Provided")
            app_name = data.get("app", "Element Web/Call")
            version = data.get("version", "Unknown Version")
            body = (
                f"Rageshake Bug Report Captured!\n\n"
                f"App: {app_name}\n"
                f"Version: {version}\n\n"
                f"User Notes:\n{text}\n"
            )
            background_tasks.add_task(
                send_email, f"[Rageshake] Bug Report from {app_name}", body, []
            )
            return {"report_url": "delivered"}
        except Exception as json_error:
            logger.error("Failed to parse JSON payload: %s", json_error)
            return {"error": "Failed to parse rageshake payload"}

    try:
        # Element gracefully sends Rageshake crash logs as multipart/form-data
        form = await request.form()
        text = form.get("text", "No User Text Provided")
        app_name = form.get("app", "Element Web/Call")
        version = form.get("version", "Unknown Version")

        body = (
            f"Rageshake Bug Report Captured!\n\n"
            f"App: {app_name}\n"
            f"Version: {version}\n\n"
            f"User Notes:\n{text}\n"
        )

        files_to_attach = []
        if "file" in form and form["file"]:
            upload_file = form["file"]  # This is typically a gzip or txt log output
            if hasattr(upload_file, "read"):
                content = await upload_file.read()
                filename = getattr(upload_file, "filename", None) or "crash_logs.gz"
                files_to_attach.append({
                    "filename": filename,
                    "content": content,
                })

        background_tasks.add_task(
            send_email, f"[Rageshake] Bug Report from {app_name}", body, files_to_attach
        )
        return {"report_url": "delivered"}
    except Exception as form_error:
        logger.error("Failed to parse form payload: %s", form_error)
        return {"error": "Failed to parse rageshake payload"}
