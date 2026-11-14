# app/api/v1/api.py
from fastapi import APIRouter
from app.api.v1.endpoints import auth, users, medical

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(medical.router)