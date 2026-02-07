from typing import List
from firebase_admin import firestore
from app.services.firebase_admin import get_db

class UnitService:
    @staticmethod
    def bulk_create_units(
        society_id: str,
        units: List[dict],
    ):
        db = get_db()

        if not units:
            raise ValueError("Units list cannot be empty")

        batch = db.batch()

        # ✅ FIX: write to PUBLIC directory (Find Society flow reads from here)
        units_ref = (
            db.collection("public_societies")
              .document(society_id)
              .collection("units")
        )

        for idx, u in enumerate(units, start=1):
            unit_id = u.get("unitId")
            if not unit_id:
                raise ValueError("Each unit must have unitId")

            doc_ref = units_ref.document(unit_id)

            # Optional: stable ordering if your Flutter query uses orderBy('sortKey')
            sort_key = u.get("sortKey")
            if sort_key is None:
                sort_key = idx

            batch.set(
                doc_ref,
                {
                    "unitId": unit_id,
                    "label": u.get("label", unit_id),
                    "block": u.get("block"),
                    "floor": u.get("floor"),
                    "type": u.get("type", "FLAT"),
                    "active": True,
                    "sortKey": int(sort_key),
                    "createdAt": firestore.SERVER_TIMESTAMP,
                    "updatedAt": firestore.SERVER_TIMESTAMP,
                },
                merge=True,  # ✅ safe if you re-run upload
            )

        batch.commit()

        return {
            "created": len(units),
            "societyId": society_id,
            "path": f"public_societies/{society_id}/units"
        }
