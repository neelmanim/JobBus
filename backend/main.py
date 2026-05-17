"""
JobBus Backend — FastAPI Application.

Entry point for the backend API server.
"""

from __future__ import annotations

from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from config import get_settings
from routers import auth, admin, resume, campaigns, opportunities, settings as settings_router, contacts
from services.followup_scheduler import start_followup_scheduler, process_due_followups


@asynccontextmanager
async def lifespan(app: FastAPI):
    """App startup/shutdown lifecycle."""
    # Start follow-up auto-sender (checks every hour for due follow-ups)
    start_followup_scheduler(interval_seconds=3600)
    yield
    # Shutdown: daemon thread dies with process — nothing extra needed


def create_app() -> FastAPI:
    """Create and configure the FastAPI application."""
    cfg = get_settings()

    app = FastAPI(
        title="JobBus API",
        description="Intelligent Career Outreach System — API",
        version="1.0.0",
        lifespan=lifespan,
        docs_url="/docs" if cfg.environment != "production" else None,
        redoc_url="/redoc" if cfg.environment != "production" else None,
    )

    # CORS — allow frontend origins (supports comma-separated FRONTEND_URLS)
    origins = [
        "http://localhost:5173",    # Vite dev
        "http://localhost:3000",    # Next.js dev
        "https://jobbus-frontend.vercel.app",
        "https://jobbus.neelmanimishra.com",
    ]
    if cfg.frontend_url:
        for url in cfg.frontend_url.split(","):
            url = url.strip()
            if url and url not in origins:
                origins.append(url)

    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Register routers
    app.include_router(auth.router)
    app.include_router(admin.router)
    app.include_router(resume.router)
    app.include_router(campaigns.router)
    app.include_router(opportunities.router)
    app.include_router(settings_router.router)
    app.include_router(contacts.router)

    # Health check
    @app.get("/health")
    async def health_check():
        return {
            "status": "ok",
            "version": "1.0.0",
            "environment": cfg.environment,
        }

    # Manual trigger: process due follow-ups immediately
    # Useful for testing and for Railway cron if added later
    @app.post("/api/followups/process")
    async def trigger_followup_processing():
        """Manually trigger follow-up processing (admin/debug use)."""
        result = await process_due_followups()
        return result

    return app


app = create_app()


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
