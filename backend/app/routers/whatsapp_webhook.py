import os
import logging
from fastapi import APIRouter, Request, HTTPException

from app.services.visitor_service import get_visitor_service
from app.models.enums import VisitorStatus  # adjust if your enum is elsewhere

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/webhooks/whatsapp", tags=["WhatsApp Webhooks"])

VERIFY_TOKEN = os.getenv("WHATSAPP_VERIFY_TOKEN", "")

@router.get("")
async def verify_webhook(request: Request):
    """
    Meta webhook verification:
    GET ?hub.mode=subscribe&hub.verify_token=...&hub.challenge=...
    """
    params = request.query_params
    mode = params.get("hub.mode")
    token = params.get("hub.verify_token")
    challenge = params.get("hub.challenge")

    if mode == "subscribe" and token == VERIFY_TOKEN:
        return int(challenge)
    raise HTTPException(status_code=403, detail="Webhook verification failed")


@router.post("")
async def receive_webhook(request: Request):
    """
    Receives inbound messages & button clicks.
    """
    body = await request.json()
    logger.info(f"WA_WEBHOOK_IN | {body}")

    # Typical structure:
    # entry[0].changes[0].value.messages[0]
    entry = (body.get("entry") or [])
    if not entry:
        return {"ok": True}

    changes = (entry[0].get("changes") or [])
    if not changes:
        return {"ok": True}

    value = changes[0].get("value") or {}
    messages = value.get("messages") or []
    if not messages:
        return {"ok": True}

    msg = messages[0]
    sender_wa = msg.get("from")  # resident phone (no +)
    msg_type = msg.get("type")

    # ✅ For interactive button replies, type often appears as "button"
    if msg_type == "button":
        button = msg.get("button") or {}
        button_text = (button.get("text") or "").upper().strip()

        # For MVP: use text only (APPROVE/REJECT)
        if button_text == "APPROVE":
            new_status = "APPROVED"
        elif button_text == "REJECT":
            new_status = "REJECTED"
        else:
            return {"ok": True}

        # IMPORTANT: We must map this click back to visitor_id
        # Best MVP trick: ask resident to click + we fetch latest PENDING for this resident
        visitor_service = get_visitor_service()
        updated = visitor_service.update_latest_pending_for_resident(
            resident_phone=sender_wa,
            status=new_status,
            approved_by=sender_wa,
        )
        return {"ok": True, "updated": updated}

    return {"ok": True}
