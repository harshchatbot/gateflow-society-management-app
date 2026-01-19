"""
Enums for GateFlow
"""

from enum import Enum


class VisitorType(str, Enum):
    """Visitor type enumeration"""
    GUEST = "Guest"
    DELIVERY = "Delivery"
    CAB = "Cab"


class VisitorStatus(str, Enum):
    """Visitor status enumeration"""
    PENDING = "PENDING"
    APPROVED = "APPROVED"
    REJECTED = "REJECTED"


class ResidentRole(str, Enum):
    """Resident role enumeration"""
    OWNER = "Owner"
    TENANT = "Tenant"
    COMMITTEE = "Committee"
