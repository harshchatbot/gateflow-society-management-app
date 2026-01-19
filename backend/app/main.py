"""
GateFlow Backend - FastAPI Application
Guard-first visitor management system
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers import guards, visitors

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


@app.get("/")
async def root():
    return {"message": "GateFlow API", "status": "running"}


@app.get("/health")
async def health():
    return {"status": "healthy"}
