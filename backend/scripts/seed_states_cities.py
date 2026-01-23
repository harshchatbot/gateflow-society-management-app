import json
import os

import firebase_admin
from firebase_admin import credentials, firestore

# Adjust path if your service account is elsewhere
SERVICE_ACCOUNT_PATH = os.environ.get(
    "FIREBASE_SERVICE_ACCOUNT_PATH",
    "firebase_service_account.json",  # or whatever you use already
)

def init_firebase():
    if not firebase_admin._apps:
        cred = credentials.Certificate(SERVICE_ACCOUNT_PATH)
        firebase_admin.initialize_app(cred)
    return firestore.client()

def seed_states_cities(json_path: str):
    db = init_firebase()

    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    for state_id, state_info in data.items():
        name = state_info.get("name", state_id)
        cities = state_info.get("cities", [])

        # states/{stateId}
        state_ref = db.collection("states").document(state_id)
        state_ref.set({"name": name}, merge=True)
        print(f"✅ Upserted state: {state_id} - {name}")

        # states/{stateId}/cities/{cityId}
        for idx, city_name in enumerate(cities):
            city_id = f"C{idx+1:03d}"  # simple generated id; you can change
            city_ref = state_ref.collection("cities").document(city_id)
            city_ref.set({"name": city_name}, merge=True)
            print(f"   ↳ city: {city_name}")

if __name__ == "__main__":
    # Run:  python backend/scripts/seed_states_cities.py
    JSON_PATH = "states_india.json"  # update path if needed
    seed_states_cities(JSON_PATH)
    print("🎉 Done seeding states and cities.")