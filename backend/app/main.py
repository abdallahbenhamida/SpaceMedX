# app/main.py
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import settings
from app.api.v1.api import api_router
from app.api.v1.endpoints import mobile_sync

app = FastAPI(
    title=settings.PROJECT_NAME,
    version="0.0.1",
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url=f"{settings.API_V1_STR}/openapi.json"
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 1. Register standard versioned API v1 router (/api/v1/...)
app.include_router(api_router, prefix=settings.API_V1_STR)

# 2. Register mobile HUB synchronization router at root level (/measurement/save/...)
app.include_router(mobile_sync.router)

@app.get("/health", tags=["System"])
async def health_check():
    """System health check endpoint for proxy and container orchestration."""
    return {
        "status": "healthy",
        "system": "SpaceMedx Backend",
        "version": "0.0.1"
    }