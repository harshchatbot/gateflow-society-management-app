"""
Notification service for sending push notifications via FCM
"""

import os
import logging
from typing import List, Optional, Dict

logger = logging.getLogger(__name__)

# Firebase Admin SDK initialization
_firebase_initialized = False
_firebase_available = False

# Try to import Firebase Admin SDK
try:
    from firebase_admin import messaging, initialize_app, credentials
    from firebase_admin.exceptions import FirebaseError
    _firebase_available = True
except ImportError:
    logger.warning(
        "firebase-admin not installed. Push notifications will be disabled. "
        "Install with: pip install firebase-admin"
    )
    _firebase_available = False


def _initialize_firebase():
    """Initialize Firebase Admin SDK"""
    global _firebase_initialized
    
    if not _firebase_available:
        logger.warning("Firebase Admin SDK not available, skipping initialization")
        return
    
    if _firebase_initialized:
        return

    try:
        # Try to initialize with service account file.
        # Support both env vars used across this codebase.
        cred_path = (
            os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH")
            or os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
            or "firebase_service_account.json"
        )
        
        # Check if already initialized (Firebase Admin SDK doesn't allow re-initialization)
        try:
            from firebase_admin import get_app
            get_app()  # This will raise ValueError if not initialized
            _firebase_initialized = True
            logger.info("Firebase Admin SDK already initialized")
            return
        except ValueError:
            # Not initialized yet, continue
            pass
        
        if os.path.exists(cred_path):
            cred = credentials.Certificate(cred_path)
            initialize_app(credential=cred)
            _firebase_initialized = True
            logger.info(f"Firebase Admin SDK initialized successfully using: {cred_path}")
        else:
            logger.warning(
                f"Firebase service account file not found at {cred_path}. "
                "Push notifications will be disabled. "
                "Set FIREBASE_SERVICE_ACCOUNT_PATH or GOOGLE_APPLICATION_CREDENTIALS."
            )
    except ValueError as ve:
        # Firebase already initialized (this is fine)
        if "already exists" in str(ve).lower():
            _firebase_initialized = True
            logger.info("Firebase Admin SDK already initialized")
        else:
            logger.error(f"Firebase initialization error: {ve}")
            _firebase_initialized = False
    except Exception as e:
        logger.error(f"Failed to initialize Firebase Admin SDK: {e}", exc_info=True)
        _firebase_initialized = False


class NotificationService:
    """Service for sending push notifications"""

    def __init__(self):
        _initialize_firebase()

    def send_notification(
        self,
        fcm_tokens: List[str],
        title: str,
        body: str,
        data: Optional[Dict[str, str]] = None,
        sound: str = "notification_sound",
    ) -> bool:
        """
        Send push notification to multiple FCM tokens
        
        Args:
            fcm_tokens: List of FCM device tokens
            title: Notification title
            body: Notification body
            data: Optional data payload
            sound: Sound file name (default: notification_sound)
        
        Returns:
            True if sent successfully, False otherwise
        """
        if not _firebase_initialized:
            logger.warning("Firebase not initialized, skipping notification")
            return False

        if not fcm_tokens:
            logger.warning("No FCM tokens provided, skipping notification")
            return False

        try:
            # Android notification config with sound
            android_config = messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    sound=sound,
                    channel_id="sentinel_channel",
                ),
            )

            # iOS notification config with sound
            apns_config = messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(
                        sound=f"{sound}.caf",
                        badge=1,
                        alert=messaging.ApsAlert(
                            title=title,
                            body=body,
                        ),
                    ),
                ),
            )

            # Build message
            message = messaging.MulticastMessage(
                notification=messaging.Notification(
                    title=title,
                    body=body,
                ),
                data=data or {},
                android=android_config,
                apns=apns_config,
                tokens=fcm_tokens,
            )

            # Send notification
            response = messaging.send_multicast(message)
            
            logger.info(
                f"Notification sent | success={response.success_count} "
                f"failure={response.failure_count} total={len(fcm_tokens)}"
            )

            if response.failure_count > 0:
                for idx, resp in enumerate(response.responses):
                    if not resp.success:
                        logger.warning(
                            f"Failed to send to token {idx}: {resp.exception}"
                        )

            return response.success_count > 0

        except FirebaseError as e:
            logger.error(f"Firebase error sending notification: {e}")
            return False
        except Exception as e:
            logger.error(f"Error sending notification: {e}", exc_info=True)
            return False

    def send_to_topic(
        self,
        topic: str,
        title: str,
        body: str,
        data: Optional[Dict[str, str]] = None,
        sound: str = "notification_sound",
    ) -> bool:
        """
        Send push notification to a topic (e.g., all users in a society)
        
        Args:
            topic: FCM topic name (e.g., "society_soc_ajmer_01")
            title: Notification title
            body: Notification body
            data: Optional data payload
            sound: Sound file name
        
        Returns:
            True if sent successfully, False otherwise
        """
        if not _firebase_available:
            logger.warning("Firebase Admin SDK not available, skipping notification")
            return False

        if not _firebase_initialized:
            logger.warning("Firebase not initialized, skipping notification")
            return False

        try:
            # Android notification config with sound
            android_config = messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    sound=sound,
                    channel_id="sentinel_channel",
                ),
            )

            # iOS notification config with sound
            apns_config = messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(
                        sound=f"{sound}.caf",
                        badge=1,
                        alert=messaging.ApsAlert(
                            title=title,
                            body=body,
                        ),
                    ),
                ),
            )

            # Build message
            message = messaging.Message(
                notification=messaging.Notification(
                    title=title,
                    body=body,
                ),
                data=data or {},
                android=android_config,
                apns=apns_config,
                topic=topic,
            )

            # Send notification
            response = messaging.send(message)
            logger.info(f"Notification sent to topic '{topic}': {response}")
            return True

        except FirebaseError as e:
            logger.error(f"Firebase error sending notification to topic: {e}")
            return False
        except Exception as e:
            logger.error(f"Error sending notification to topic: {e}", exc_info=True)
            return False


def get_notification_service() -> NotificationService:
    """Get notification service instance"""
    return NotificationService()
