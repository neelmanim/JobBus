"""
JobBus Backend — FastAPI Application.

Entry point for the backend API server.
"""

from __future__ import annotations


from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from config import get_settings
from routers import auth, admin, resume, campaigns, opportunities, settings as settings_router


def create_app() -> FastAPI:
    """Create and configure the FastAPI application."""
    cfg = get_settings()

    app = FastAPI(
        title="JobBus API",
        description="Intelligent Career Outreach System — API",
        version="1.0.0",
        docs_url="/docs" if cfg.environment != "production" else None,
        redoc_url="/redoc" if cfg.environment != "production" else None,
    )

    # CORS — allow frontend origins
    origins = [
        "http://localhost:5173",    # Vite dev
        "http://localhost:3000",    # Next.js dev
    ]
    if cfg.frontend_url:
        origins.append(cfg.frontend_url)

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

    # Health check
    @app.get("/health")
    async def health_check():
        return {
            "status": "ok",
            "version": "1.0.0",
            "environment": cfg.environment,
        }

    return app


app = create_app()


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
