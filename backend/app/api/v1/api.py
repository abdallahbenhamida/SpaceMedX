# app/api/v1/api.py
from fastapi import APIRouter
from app.api.v1.endpoints import auth, users, medical, environment, emergency, telemetry_ws, organizations, missions

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(medical.router)
api_router.include_router(environment.router)
api_router.include_router(emergency.router)
api_router.include_router(telemetry_ws.router)
api_router.include_router(organizations.router)
api_router.include_router(missions.router)
