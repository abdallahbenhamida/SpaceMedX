# app/main.py
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import settings
from app.api.v1.api import api_router  # Import the aggregated v1 router

app = FastAPI(
    title=settings.PROJECT_NAME,
    version="0.0.1",
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url=f"{settings.API_V1_STR}/openapi.json"
)

# Configure CORS (adjust origins for production deployment)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register the centralized API v1 router (includes auth, users, and medical)
app.include_router(api_router, prefix=settings.API_V1_STR)

@app.get("/health", tags=["System"])
async def health_check():
    """System health check endpoint for proxy and container orchestration."""
    return {
        "status": "healthy",
        "system": "SpaceMedx Backend",
        "version": "0.0.1"
    }