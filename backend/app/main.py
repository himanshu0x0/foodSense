"""FoodSense FastAPI backend entry point."""

from __future__ import annotations

from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import settings
from .routes.cloudinary import router as cloudinary_router
from .routes.delivery_routing import router as delivery_routing_router
from .routes.forecast import router as forecast_router
from .routes.place_search import router as place_search_router
from .routes.surplus import router as surplus_router
from .routes.waste import router as waste_router


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    yield


def create_app() -> FastAPI:
    app = FastAPI(
        title=settings.app_name,
        description=(
            "Backend services for FoodSense AI, Cloudinary media management, "
            "traffic-aware delivery routing, and pickup/drop-off place search."
        ),
        version=settings.app_version,
        debug=settings.debug,
        lifespan=lifespan,
    )

    allow_all_origins = settings.cors_allows_all

    app.add_middleware(
        CORSMiddleware,
        allow_origins=list(settings.allowed_origins),
        allow_credentials=not allow_all_origins,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.get("/", tags=["System"])
    async def root() -> dict[str, str]:
        return {
            "name": settings.app_name,
            "version": settings.app_version,
            "environment": settings.environment,
            "status": "running",
        }

    @app.get("/health", tags=["System"])
    async def health_check() -> dict[str, str]:
        return {
            "status": "healthy",
            "service": "foodsense-api",
        }

    app.include_router(forecast_router)
    app.include_router(surplus_router)
    app.include_router(waste_router)
    app.include_router(cloudinary_router)
    app.include_router(delivery_routing_router)
    app.include_router(place_search_router)

    return app


app = create_app()


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app.main:app",
        host=settings.host,
        port=settings.port,
        reload=settings.debug,
    )
