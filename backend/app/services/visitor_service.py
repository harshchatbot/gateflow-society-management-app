"""
Visitor service for visitor entry management
"""

from datetime import datetime, timezone, timedelta
from typing import List, Optional, Dict, Tuple
import uuid
import logging
import time

from fastapi import HTTPException

from app.sheets.client import get_sheets_client
from app.models.schemas import VisitorResponse
from app.models.enums import VisitorStatus

logger = logging.getLogger(__name__)


class VisitorService:
    """Service for visitor-related operations"""

    def __init__(self):
        self.sheets_client = get_sheets_client()

        # -----------------------------
        # Flat cache (society-scoped)
        # -----------------------------
        # society_id -> (expires_at_epoch, {flat_no_norm: flat_dict})
        self._flat_cache: Dict[str, Tuple[float, Dict[str, dict]]] = {}
        self._flat_cache_ttl_sec: int = 300  # 5 minutes

    # -----------------------------
    # Flat No Normalizer
    # -----------------------------
    def _norm_flat_no(self, flat_no: Optional[str]) -> str:
        return (flat_no or "").strip().upper()

    def clear_flat_cache(self, society_id: Optional[str] = None) -> None:
        """Utility to clear flat cache (useful for testing)."""
        if society_id:
            self._flat_cache.pop(society_id, None)
        else:
            self._flat_cache.clear()

    def _get_flat_map_cached(self, society_id: str) -> Dict[str, dict]:
        """
        Build/return cached map: flat_no_norm -> flat_dict for a society.
        Uses SheetsClient.get_flats(society_id=...) which already returns active flats only.
        """
        now = time.time()
        cached = self._flat_cache.get(society_id)

        if cached and cached[0] > now:
            return cached[1]

        # Cache miss/expired: fetch once and build map
        flats = self.sheets_client.get_flats(society_id=society_id)

        m: Dict[str, dict] = {}
        for f in flats:
            k = self._norm_flat_no(f.get("flat_no"))
            if k:
                m[k] = f

        self._flat_cache[society_id] = (now + self._flat_cache_ttl_sec, m)

        logger.info(
            f"FLAT_CACHE_REFRESHED | society_id={society_id} flats_cached={len(m)} ttl_sec={self._flat_cache_ttl_sec}"
        )
        return m

    # -----------------------------
    # Flat Resolver
    # -----------------------------
    def _resolve_flat(
        self,
        society_id: str,
        flat_id: Optional[str] = None,
        flat_no: Optional[str] = None,
    ) -> dict:
        """
        Resolve flat by flat_id OR by flat_no (A-101 style),
        always enforcing active_only=True.
        """

        logger.info(f"RESOLVE_FLAT | society_id={society_id} flat_id={flat_id} flat_no={flat_no}")

        # 1) Try flat_id if provided (no change)
        if flat_id:
            flat = self.sheets_client.get_flat_by_id(flat_id, active_only=True)
            if flat:
                return flat

        # 2) Try flat_no if provided (UPDATED: use cache-first, fallback to direct lookup)
        if flat_no:
            flat_no_norm = self._norm_flat_no(flat_no)

            # 2a) Cache-first resolution
            try:
                flat_map = self._get_flat_map_cached(society_id)
                flat = flat_map.get(flat_no_norm)
                if flat:
                    return flat
            except Exception as e:
                # Cache should never break functionality — fall back
                logger.warning(f"RESOLVE_FLAT_CACHE_FAIL | society_id={society_id} err={e}")

            # 2b) Fallback: direct sheet lookup (keeps existing behavior intact)
            flat = self.sheets_client.get_flat_by_no(
                society_id=society_id,
                flat_no=flat_no_norm,
                active_only=True,
            )
            if flat:
                # Optional: warm cache
                try:
                    flat_map = self._get_flat_map_cached(society_id)
                    flat_map[self._norm_flat_no(flat.get("flat_no"))] = flat
                except Exception:
                    pass
                return flat

        logger.warning(
            f"RESOLVE_FLAT_NOT_FOUND | society_id={society_id} flat_id={flat_id} flat_no={flat_no}"
        )

        raise HTTPException(
            status_code=400,
            detail="Flat not found. Please enter valid Flat No (e.g., A-101).",
        )

    def create_visitor(
        self,
        flat_id: Optional[str],
        visitor_type: str,
        visitor_phone: str,
        guard_id: str,
        photo_path: str = "",
        flat_no: Optional[str] = None,
    ) -> VisitorResponse:
        """
        Create a new visitor entry.
        Supports:
          - flat_id (optional)
          - flat_no (optional, like A-101)

        Stores BOTH flat_id and flat_no in Visitors sheet for MVP consistency.
        """

        # Validate guard exists FIRST (source of truth for society_id)
        guard = self.sheets_client.get_guard_by_id(guard_id)
        if not guard:
            raise HTTPException(status_code=400, detail=f"Guard with ID {guard_id} not found")

        society_id = guard.get("society_id")
        if not society_id:
            raise HTTPException(status_code=500, detail="Guard record missing society_id in sheet")

        # Resolve flat (active only)
        flat = self._resolve_flat(society_id=society_id, flat_id=flat_id, flat_no=flat_no)

        resolved_flat_id = flat.get("flat_id") or ""
        resolved_flat_no = (flat.get("flat_no") or flat_no or "").strip().upper()

        if not resolved_flat_id:
            raise HTTPException(status_code=500, detail="Flat record missing flat_id in sheet")
        if not resolved_flat_no:
            raise HTTPException(status_code=500, detail="Flat record missing flat_no in sheet")

        # Generate visitor_id
        visitor_id = str(uuid.uuid4())

        # Create visitor entry with ISO UTC timestamp
        created_at_utc = datetime.now(timezone.utc).isoformat()

        visitor_data = {
            "visitor_id": visitor_id,
            "society_id": society_id,

            # keep both
            "flat_id": resolved_flat_id,
            "flat_no": resolved_flat_no,

            "visitor_type": visitor_type,
            "visitor_phone": visitor_phone,
            "status": VisitorStatus.PENDING.value,
            "created_at": created_at_utc,
            "approved_at": "",
            "approved_by": "",
            "guard_id": guard_id,
            "photo_path": photo_path or "",
        }

        # Append to Visitors sheet
        self.sheets_client.create_visitor(visitor_data)

        # Log approval stub to resident phone
        self._log_approval_request(flat, visitor_data)

        return self._dict_to_visitor_response(visitor_data)



    def _pick_resident_phone(flat: dict) -> Optional[str]:
        """
        Flat dict coming from Google Sheets may have different key names
        depending on your mapping. Try all likely keys safely.
        """
        if not flat:
            return None

        candidates = [
            flat.get("resident_phone"),
            flat.get("residentPhone"),
            flat.get("Resident Phone"),
            flat.get("ResidentPhone"),
            flat.get("phone"),
            flat.get("Phone"),
            flat.get("mobile"),
            flat.get("Mobile"),
        ]

        for p in candidates:
            if isinstance(p, str) and p.strip():
                return p.strip()

        return None


    async def _best_effort_send_whatsapp_approval(
        visitor_service,
        society_id: str,
        flat_id: Optional[str],
        flat_no: Optional[str],
        visitor: VisitorResponse,
    ):
        """
        Best-effort WhatsApp notification to resident.

        - VisitorResponse doesn't contain resident_phone in your schema,
        so we resolve the flat again using existing _resolve_flat().
        - Does NOT raise errors; it will not break existing create flows.
        """
        try:
            # ✅ Resolve flat to get resident phone
            flat = visitor_service._resolve_flat(
                society_id=society_id,
                flat_id=flat_id,
                flat_no=flat_no,
            )

            resident_phone = _pick_resident_phone(flat)
            if not resident_phone:
                logger.warning(
                    f"WHATSAPP_SKIP | resident_phone not found in flat dict keys={list(flat.keys())}"
                )
                return

            resident_phone = _normalize_wa_phone(resident_phone)

            msg = (
                f"GateFlow: New entry request\n"
                f"Flat: {visitor.flat_no}\n"
                f"Type: {visitor.visitor_type}\n"
                f"Visitor: {visitor.visitor_phone}\n"
                f"Request ID: {visitor.visitor_id}\n\n"
                f"Reply YES to approve or NO to reject."
            )

            wa = get_whatsapp_service()
            await wa.send_text(to_phone_e164_no_plus=resident_phone, text=msg)
            logger.info(f"WHATSAPP_SENT | to={resident_phone} visitor_id={visitor.visitor_id}")

        except HTTPException as he:
            # Flat resolve can raise HTTPException; don't break create flow
            logger.warning(
                f"WHATSAPP_SKIP_HTTP | visitor_id={getattr(visitor,'visitor_id','UNKNOWN')} "
                f"status={he.status_code} detail={he.detail}"
            )
        except Exception as e:
            # Best effort only
            logger.warning(
                f"WHATSAPP_SEND_FAILED | visitor_id={getattr(visitor,'visitor_id','UNKNOWN')} err={str(e)}"
            )




    def create_visitor_with_photo(
        self,
        flat_id: Optional[str],
        visitor_type: str,
        visitor_phone: str,
        guard_id: str,
        photo_path: str,
        flat_no: Optional[str] = None,
    ) -> VisitorResponse:
        """Backward compatible: still accepts flat_id. New: can also accept flat_no."""
        return self.create_visitor(
            flat_id=flat_id,
            flat_no=flat_no,
            visitor_type=visitor_type,
            visitor_phone=visitor_phone,
            guard_id=guard_id,
            photo_path=photo_path,
        )

    def get_visitors_today(self, guard_id: str) -> List[VisitorResponse]:
        """
        MVP semantics: return visitors from the LAST 24 HOURS (rolling window),
        instead of calendar 'today'. This avoids timezone confusion.
        """
        now_utc = datetime.now(timezone.utc)
        cutoff = now_utc - timedelta(hours=24)

        logger.info(
            f"RECENT_VISITORS_24H | guard_id={guard_id} now_utc={now_utc.isoformat()} cutoff={cutoff.isoformat()}"
        )

        # Fetch by guard only (fast + minimal)
        visitors = self.sheets_client.get_visitors(guard_id=guard_id)

        filtered = []
        for v in visitors:
            created_at_str = (v.get("created_at") or "").strip()
            if not created_at_str:
                continue

            try:
                dt = datetime.fromisoformat(created_at_str.replace("Z", "+00:00"))
                if dt.tzinfo is None:
                    dt = dt.replace(tzinfo=timezone.utc)

                # keep only last 24 hours
                if dt >= cutoff:
                    filtered.append(v)

            except Exception as e:
                logger.warning(
                    f"RECENT_24H_PARSE_FAIL | guard_id={guard_id} created_at='{created_at_str}' err={e}"
                )
                continue

        # Sort newest first
        filtered.sort(key=lambda x: x.get("created_at", ""), reverse=True)

        logger.info(f"RECENT_VISITORS_24H_RESULT | guard_id={guard_id} count={len(filtered)}")
        return [self._dict_to_visitor_response(v) for v in filtered]

    def get_visitors_by_flat(self, flat_id: str) -> List[VisitorResponse]:
        """Legacy: Get all visitors for a flat by flat_id"""
        visitors = self.sheets_client.get_visitors(flat_id=flat_id)
        return [self._dict_to_visitor_response(v) for v in visitors]

    def get_visitors_by_flat_no(self, guard_id: str, flat_no: str) -> List[VisitorResponse]:
        """
        MVP approach:
        - Guard enters flat_no (A-101)
        - Validate guard and society_id
        - Ensure flat exists & active
        - Fetch visitors by flat_no (and society_id to prevent cross-society collisions)
        """

        flat_no_norm = self._norm_flat_no(flat_no)
        logger.info(f"GET_VISITORS_BY_FLAT_NO | guard_id={guard_id} flat_no={flat_no_norm}")

        if not flat_no_norm:
            raise HTTPException(status_code=400, detail="flat_no is required")

        # 1) Validate guard & derive society_id
        guard = self.sheets_client.get_guard_by_id(guard_id)
        if not guard:
            logger.warning(f"GET_VISITORS_BY_FLAT_NO_GUARD_NOT_FOUND | guard_id={guard_id}")
            raise HTTPException(status_code=400, detail=f"Guard with ID {guard_id} not found")

        society_id = guard.get("society_id")
        if not society_id:
            logger.error(
                f"GET_VISITORS_BY_FLAT_NO_GUARD_MISSING_SOCIETY | guard_id={guard_id} guard={guard}"
            )
            raise HTTPException(status_code=500, detail="Guard record missing society_id in sheet")

        # 2) Resolve flat to ensure active/valid (now cache-backed via _resolve_flat)
        _ = self._resolve_flat(society_id=society_id, flat_id=None, flat_no=flat_no_norm)

        # 3) Fetch visitors (prefer by flat_no + society_id)
        try:
            visitors = self.sheets_client.get_visitors(
                society_id=society_id,
                flat_no=flat_no_norm,
            )
        except TypeError:
            # Fallback for older sheets_client that doesn't support flat_no filter
            logger.warning(
                "Sheets client get_visitors does not support flat_no filter yet; falling back to flat_id resolution."
            )
            flat = self._resolve_flat(society_id=society_id, flat_no=flat_no_norm)
            resolved_flat_id = flat.get("flat_id")
            visitors = self.sheets_client.get_visitors(flat_id=resolved_flat_id)

        logger.info(f"GET_VISITORS_BY_FLAT_NO_RESULT | flat_no={flat_no_norm} count={len(visitors)}")
        return [self._dict_to_visitor_response(v) for v in visitors]

    def _dict_to_visitor_response(self, visitor_dict: dict) -> VisitorResponse:
        """Convert visitor dict to VisitorResponse"""

        created_at_str = visitor_dict.get("created_at", "")
        approved_at_str = visitor_dict.get("approved_at", "")

        # Parse created_at (ISO UTC format)
        try:
            if created_at_str:
                created_at = datetime.fromisoformat(created_at_str.replace("Z", "+00:00"))
                if created_at.tzinfo is None:
                    created_at = created_at.replace(tzinfo=timezone.utc)
            else:
                created_at = datetime.now(timezone.utc)
        except Exception as e:
            logger.warning(f"Failed to parse created_at '{created_at_str}': {e}")
            created_at = datetime.now(timezone.utc)

        # Parse approved_at (optional)
        approved_at = None
        if approved_at_str:
            try:
                approved_at = datetime.fromisoformat(approved_at_str.replace("Z", "+00:00"))
                if approved_at.tzinfo is None:
                    approved_at = approved_at.replace(tzinfo=timezone.utc)
            except Exception as e:
                logger.warning(f"Failed to parse approved_at '{approved_at_str}': {e}")
                approved_at = None

        photo_path = visitor_dict.get("photo_path") or None
        photo_url = None
        if photo_path:
            photo_url = f"/uploads/{photo_path}".replace("//", "/")

        return VisitorResponse(
            visitor_id=visitor_dict.get("visitor_id", ""),
            society_id=visitor_dict.get("society_id", ""),
            flat_id=visitor_dict.get("flat_id", ""),
            flat_no=visitor_dict.get("flat_no", "") or "",  # ✅ NEW
            visitor_type=visitor_dict.get("visitor_type", ""),
            visitor_phone=visitor_dict.get("visitor_phone", ""),
            status=visitor_dict.get("status", VisitorStatus.PENDING.value),
            created_at=created_at,
            approved_at=approved_at,
            approved_by=visitor_dict.get("approved_by"),
            guard_id=visitor_dict.get("guard_id", ""),
            photo_path=photo_path,
            photo_url=photo_url,
            note=visitor_dict.get("note") or None,
        )

    def _log_approval_request(self, flat: dict, visitor_data: dict):
        """Stub approval log (WhatsApp/SMS in future)"""
        resident_phone = flat.get("resident_phone", "")
        flat_no = flat.get("flat_no", "")
        resident_name = flat.get("resident_name", "")
        visitor_type = visitor_data.get("visitor_type", "")
        visitor_phone = visitor_data.get("visitor_phone", "")
        visitor_id = visitor_data.get("visitor_id", "")

        logger.info(
            f"APPROVAL_REQUEST_STUB | To: {resident_phone} | "
            f"Flat: {flat_no} ({resident_name}) | Visitor: {visitor_type} | "
            f"Phone: {visitor_phone} | VisitorID: {visitor_id}"
        )

        print(f"[APPROVAL_STUB] Would send to {resident_phone}:")
        print(f"  Flat: {flat_no} ({resident_name})")
        print(f"  Visitor: {visitor_type} - {visitor_phone}")
        print(f"  Visitor ID: {visitor_id}")
        print(f"  Message: Reply YES/NO to approve/reject")

    def update_visitor_status(
        self,
        visitor_id: str,
        status: str,
        approved_by: Optional[str] = None,
        note: Optional[str] = None,
    ) -> VisitorResponse:
        """
        Update visitor status in Visitors sheet.
        Also sets approved_at when approving/rejecting (UTC ISO).
        """
        status_norm = (status or "").strip().upper()
        if not status_norm:
            raise HTTPException(status_code=400, detail="status is required")

        # allowed statuses (MVP)
        allowed = {"APPROVED", "REJECTED", "LEAVE_AT_GATE", "PENDING"}
        if status_norm not in allowed:
            raise HTTPException(status_code=400, detail=f"Invalid status '{status_norm}'")

        approved_at = ""
        if status_norm in {"APPROVED", "REJECTED", "LEAVE_AT_GATE"}:
            approved_at = datetime.now(timezone.utc).isoformat()

        logger.info(
            f"UPDATE_STATUS | visitor_id={visitor_id} status={status_norm} approved_by={approved_by} note={note}"
        )

        updated = self.sheets_client.update_visitor_status(
            visitor_id=visitor_id,
            status=status_norm,
            approved_at=approved_at,
            approved_by=approved_by or "",
            note=note or "",
        )

        if not updated:
            raise HTTPException(status_code=404, detail="Visitor not found")

        return self._dict_to_visitor_response(updated)


# Singleton instance
_visitor_service: Optional[VisitorService] = None


def get_visitor_service() -> VisitorService:
    """Get singleton VisitorService instance"""
    global _visitor_service
    if _visitor_service is None:
        _visitor_service = VisitorService()
    return _visitor_service
