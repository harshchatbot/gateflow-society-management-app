from app.services.firebase_admin import get_firestore

db = get_firestore()

db.collection("debug").document("ping").set({
    "ok": True
})

print("Firestore admin write OK")
