import os
import logging
import httpx
from typing import Optional

logger = logging.getLogger(__name__)

WHATSAPP_TOKEN = os.getenv("WHATSAPP_TOKEN")
PHONE_NUMBER_ID = os.getenv("WHATSAPP_PHONE_NUMBER_ID")
API_VERSION = os.getenv("WHATSAPP_API_VERSION", "v21.0")


class WhatsAppService:
    def __init__(self):
        if not WHATSAPP_TOKEN or not PHONE_NUMBER_ID:
            raise RuntimeError("Missing WHATSAPP_TOKEN or WHATSAPP_PHONE_NUMBER_ID in env")

        self.base_url = f"https://graph.facebook.com/{API_VERSION}/{PHONE_NUMBER_ID}/messages"

    async def send_text(self, to_phone_e164_no_plus: str, text: str) -> dict:
        """
        to_phone_e164_no_plus example: '919876543210'
        """
        payload = {
            "messaging_product": "whatsapp",
            "to": to_phone_e164_no_plus,
            "type": "text",
            "text": {"body": text},
        }

        headers = {
            "Authorization": f"Bearer {WHATSAPP_TOKEN}",
            "Content-Type": "application/json",
        }

        async with httpx.AsyncClient(timeout=20) as client:
            resp = await client.post(self.base_url, json=payload, headers=headers)

        try:
            data = resp.json()
        except Exception:
            data = {"raw": resp.text}

        if resp.status_code >= 400:
            logger.error(f"WHATSAPP_SEND_FAIL | status={resp.status_code} | data={data}")
            raise RuntimeError(f"WhatsApp send failed: {data}")

        logger.info(f"WHATSAPP_SEND_OK | to={to_phone_e164_no_plus} | data={data}")
        return data

    async def send_approval_template(
        self,
        to_phone_e164_no_plus: str,
        template_name: str,
        language_code: str,
        flat_no: str,
        visitor_type: str,
        visitor_phone: str,
        visitor_id: str,
    ) -> dict:
        """
        Sends an approved WhatsApp template with variables.
        This is business-initiated, so template must exist + be approved in Meta.
        """
        payload = {
            "messaging_product": "whatsapp",
            "to": to_phone_e164_no_plus,
            "type": "template",
            "template": {
                "name": template_name,
                "language": {"code": language_code},
                "components": [
                    {
                        "type": "body",
                        "parameters": [
                            {"type": "text", "text": flat_no},
                            {"type": "text", "text": visitor_type},
                            {"type": "text", "text": visitor_phone},
                            {"type": "text", "text": visitor_id},
                        ],
                    }
                ],
            },
        }

        headers = {
            "Authorization": f"Bearer {WHATSAPP_TOKEN}",
            "Content-Type": "application/json",
        }

        async with httpx.AsyncClient(timeout=20) as client:
            resp = await client.post(self.base_url, json=payload, headers=headers)

        try:
            data = resp.json()
        except Exception:
            data = {"raw": resp.text}

        if resp.status_code >= 400:
            logger.error(f"WHATSAPP_TEMPLATE_SEND_FAIL | status={resp.status_code} | data={data}")
            raise RuntimeError(f"WhatsApp template send failed: {data}")

        logger.info(f"WHATSAPP_TEMPLATE_SEND_OK | to={to_phone_e164_no_plus} | data={data}")
        return data


_whatsapp_service: Optional[WhatsAppService] = None


def get_whatsapp_service() -> WhatsAppService:
    global _whatsapp_service
    if _whatsapp_service is None:
        _whatsapp_service = WhatsAppService()
    return _whatsapp_service
