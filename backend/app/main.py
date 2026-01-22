"""
GateFlow Backend - FastAPI Application
Guard-first visitor management system
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers import guards, visitors , residents, admins

import logging

from app.routers import whatsapp_webhook



logger = logging.getLogger() 

logging.basicConfig(
    level=logging.INFO,  # 👈 THIS IS THE KEY
    format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
)


app = FastAPI(
    title="GateFlow API",
    description="Guard-first visitor management system",
    version="1.0.0"
)

# CORS middleware for Flutter app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # TODO: Restrict to Flutter app in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(guards.router, prefix="/api/guards", tags=["guards"])
app.include_router(visitors.router, prefix="/api/visitors", tags=["visitors"])
app.include_router(whatsapp_webhook.router )
app.include_router(residents.router )
app.include_router(admins.router )

@app.get("/")
async def root():
    return {"message": "GateFlow API", "status": "running"}


@app.get("/health")
async def health():
    return {"status": "healthy"}


import time
import logging
from fastapi import Request

logger = logging.getLogger("http")

@app.middleware("http")
async def log_requests(request: Request, call_next):
    start = time.time()

    body = await request.body()
    logger.info(
        f"➡️ REQUEST {request.method} {request.url}\n"
        f"Headers: {dict(request.headers)}\n"
        f"Body: {body.decode('utf-8', errors='ignore')}"
    )

    response = await call_next(request)

    duration = (time.time() - start) * 1000
    logger.info(
        f"✅ RESPONSE {request.method} {request.url}\n"
        f"Status: {response.status_code}\n"
        f"Time: {duration:.2f}ms"
    )

    return response
