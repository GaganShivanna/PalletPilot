"""Settings loaded from environment variables and backend/.env (never committed)."""

from functools import lru_cache
from pathlib import Path
from typing import Annotated

from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict

BACKEND_DIR = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=BACKEND_DIR / ".env", env_file_encoding="utf-8", extra="ignore"
    )

    # API keys: optional so the stub pipeline runs without them.
    muse_api_key: SecretStr | None = None
    llm_api_key: SecretStr | None = None

    # Provider selection: mock | sam | muse_spark | muse_image | real.
    # Real adapters raise ProviderUnavailable until integrated — never silent mock.
    ai_provider: str = "mock"

    # External model-call guardrails.
    provider_timeout_s: float = Field(default=60.0, gt=0)
    provider_max_retries: int = Field(default=2, ge=0)
    provider_max_concurrency: int = Field(default=4, gt=0)

    muse_base_url: str = "https://api.meta.ai/v1"
    muse_spark_model: str = "muse-spark-1.3"

    sam_model: str = "sam-3.1"
    sam_concepts: str = ""
    sam_timeout_s: float = Field(default=180.0, gt=0)   

    # Financial estimates (labeled as estimates in API responses).
    fee_rate: float = Field(default=0.13, ge=0.0, le=1.0)

    data_dir: Path = BACKEND_DIR / "data"
    sample_fps: float = Field(default=3.0, ge=2.0, le=5.0)
    max_frames: int = Field(default=300, gt=0)
    max_upload_mb: int = Field(default=500, gt=0)
    cors_origins: Annotated[list[str], NoDecode] = ["http://localhost:3000", "http://localhost:5173"]

    @field_validator("data_dir")
    @classmethod
    def _resolve_data_dir(cls, v: Path) -> Path:
        return v if v.is_absolute() else BACKEND_DIR / v

    @field_validator("cors_origins", mode="before")
    @classmethod
    def _split_origins(cls, v: object) -> object:
        if isinstance(v, str):
            return [o.strip() for o in v.split(",") if o.strip()]
        return v


@lru_cache
def get_settings() -> Settings:
    return Settings()
