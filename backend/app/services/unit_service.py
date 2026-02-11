from typing import List, Dict, Any
from firebase_admin import firestore
from app.services.firebase_admin import get_db

class UnitService:
    @staticmethod
    def bulk_create_units(
        society_id: str,
        units: List[Dict[str, Any]],
    ):
        db = get_db()
        society_id = (society_id or "").strip()
        if not society_id:
            raise ValueError("societyId is required")

        if not units:
            raise ValueError("Units list cannot be empty")

        # ✅ FIX: write to PUBLIC directory (Find Society flow reads from here)
        units_ref = (
            db.collection("public_societies")
              .document(society_id)
              .collection("units")
        )

        batch = db.batch()
        writes_in_batch = 0
        processed = 0
        seen_ids = set()

        def _flush():
            nonlocal batch, writes_in_batch
            if writes_in_batch == 0:
                return
            batch.commit()
            batch = db.batch()
            writes_in_batch = 0

        for idx, u in enumerate(units, start=1):
            unit_id = str(u.get("unitId") or "").strip()
            if not unit_id:
                raise ValueError("Each unit must have unitId")
            if "/" in unit_id:
                raise ValueError(f"unitId cannot contain '/': {unit_id}")
            if unit_id in seen_ids:
                raise ValueError(f"Duplicate unitId in payload: {unit_id}")
            seen_ids.add(unit_id)

            doc_ref = units_ref.document(unit_id)

            # Optional: stable ordering if your Flutter query uses orderBy('sortKey')
            sort_key = u.get("sortKey")
            if sort_key is None:
                sort_key = idx
            try:
                sort_key = int(sort_key)
            except (TypeError, ValueError):
                sort_key = idx

            label = str(u.get("label") or unit_id).strip()
            if not label:
                label = unit_id

            unit_type = str(u.get("type") or "FLAT").strip().upper()
            if not unit_type:
                unit_type = "FLAT"

            active_raw = u.get("active", True)
            if isinstance(active_raw, bool):
                active = active_raw
            else:
                active = str(active_raw).strip().lower() == "true"

            batch.set(
                doc_ref,
                {
                    "unitId": unit_id,
                    "label": label,
                    "block": u.get("block"),
                    "floor": u.get("floor"),
                    "type": unit_type,
                    "active": active,
                    "sortKey": sort_key,
                    "createdAt": firestore.SERVER_TIMESTAMP,
                    "updatedAt": firestore.SERVER_TIMESTAMP,
                },
                merge=True,  # ✅ safe if you re-run upload
            )
            writes_in_batch += 1
            processed += 1
            # Firestore batched writes limit is 500 operations.
            if writes_in_batch >= 450:
                _flush()

        _flush()

        return {
            "created": processed,
            "societyId": society_id,
            "path": f"public_societies/{society_id}/units"
        }
