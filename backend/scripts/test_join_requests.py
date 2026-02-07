# backend/scripts/test_join_requests.py
import argparse
from datetime import datetime
from app.services.firebase_admin import get_db

def main():
    parser = argparse.ArgumentParser()
    #parser.add_argument("--society", required=True, help="societyId, e.g. soc_amara")
    parser.add_argument("--society", required=True, help="societyId, e.g. soc_kediaamara")
    parser.add_argument("--limit", type=int, default=20)
    parser.add_argument("--filtered", action="store_true", help="run filtered query")
    args = parser.parse_args()

    db = get_db()
    ref = db.collection("public_societies").document(args.society).collection("join_requests")

    print(f"\n=== public_societies/{args.society}/join_requests ===")

    # 1) RAW dump (most useful)
    raw_docs = list(ref.limit(args.limit).stream())
    print(f"RAW count (first {args.limit}): {len(raw_docs)}")
    for d in raw_docs:
        data = d.to_dict() or {}
        print(f"\n- docId={d.id}")
        for k in sorted(data.keys()):
            print(f"  {k}: {data[k]}")

    # 2) Filtered query (your app query)
    if args.filtered:
        print("\n=== FILTERED (requestedRole='resident', status='PENDING') ===")
        q = (
            ref.where("requestedRole", "==", "resident")
               .where("status", "==", "PENDING")
               # comment order_by to avoid index issues while testing
               # .order_by("createdAt")
               .limit(args.limit)
        )
        docs = list(q.stream())
        print(f"Filtered count (first {args.limit}): {len(docs)}")
        for d in docs:
            print(f"- docId={d.id} => {d.to_dict()}")

if __name__ == "__main__":
    main()
