from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import settings

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

@app.get("/health", tags=["System"])
async def health_check():
    """System health check endpoint for proxy and container orchestration."""
    return {
        "status": "healthy",
        "system": "SpaceMedx Backend",
        "version": "0.0.1"
    }

# Future module routers will be included here:
# from app.modules.observations.router import router as observations_router
# app.include_router(observations_router, prefix=settings.API_V1_STR)