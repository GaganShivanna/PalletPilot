from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import Settings, get_settings
from app.routes import health, items, jobs, pallets
from app.services.jobs import JobQueue, JobStore


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        settings.data_dir.mkdir(parents=True, exist_ok=True)
        app.state.settings = settings
        app.state.job_store = JobStore(settings.data_dir)
        app.state.job_queue = JobQueue(app.state.job_store, settings)
        app.state.job_queue.start()
        yield
        await app.state.job_queue.stop()

    app = FastAPI(title="PalletPilot API", version="0.1.0", lifespan=lifespan)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.include_router(health.router)
    app.include_router(jobs.router)
    app.include_router(pallets.router)
    app.include_router(items.router)
    return app


app = create_app()
