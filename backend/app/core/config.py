# app/core/config.py
import sys
import os
from pathlib import Path
from pydantic import ValidationError
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    PROJECT_NAME: str = "SpaceMedx"
    ENVIRONMENT: str = "development"
    API_V1_STR: str = "/api/v1"
    DATABASE_URL: str
    POSTGRES_USER: str = "spacemedx_user"
    POSTGRES_PASSWORD: str
    POSTGRES_DB: str = "spacemedx"
    SECRET_KEY: str
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30

    model_config = SettingsConfigDict(
        # If running locally without Docker env injection, look for .env in parent/current dirs
        env_file=".env" if os.path.exists(".env") else None,
        env_file_encoding="utf-8",
        extra="ignore"
    )

def get_validated_settings() -> Settings:
    # Only enforce physical .env file check if we are running outside Docker 
    # (i.e., DATABASE_URL or SECRET_KEY aren't already injected in the environment)
    if not os.getenv("DATABASE_URL") and not os.getenv("SECRET_KEY"):
        env_path = Path(".env")
        if not env_path.is_file():
            print("CRITICAL ERROR: env cannot be found!")
            print("➡️ Action required: Copy 'env.example' to '.env' in your deployment directory.")
            sys.exit(1)

    try:
        # Attempt to load and validate environment variables
        return Settings()
        
    except ValidationError as e:
        print("CRITICAL ERROR: env contains incorrect syntax or missing fields!")
        print("Details:")
        print(e)
        print("➡️ Action required: Fix syntax formatting (e.g., missing quotes, invalid types) in your .env file.")
        sys.exit(1)
        
    except Exception as e:
        print(f"CRITICAL ERROR: can't start server!")
        print(f"Reason: {e}")
        sys.exit(1)

# Initialize settings globally for the application
settings = get_validated_settings()