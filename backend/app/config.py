from pydantic_settings import BaseSettings, SettingsConfigDict
from typing import List, Optional


class Settings(BaseSettings):
    PROJECT_NAME: str = "BLE Attendance Platform API"
    VERSION: str = "1.0.0"
    API_V1_STR: str = "/api/v1"
    
    # Database
    DATABASE_URL: str = "postgresql+asyncpg://postgres:postgrespassword@localhost:5432/attendance_db"
    SYNC_DATABASE_URL: str = "postgresql://postgres:postgrespassword@localhost:5432/attendance_db"
    
    # Firebase
    FIREBASE_PROJECT_ID: str = "attendance-ble-test"
    FIREBASE_SERVICE_ACCOUNT_PATH: Optional[str] = None
    
    # Security & CORS
    CORS_ORIGINS: List[str] = ["*"]
    ENVIRONMENT: str = "development"
    MAX_CSV_UPLOAD_SIZE_BYTES: int = 2 * 1024 * 1024  # 2 MB max

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore"
    )


settings = Settings()
