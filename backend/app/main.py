from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import settings
from .routes.forecast import router as forecast_router
from .routes.surplus import router as surplus_router
from .routes.waste import router as waste_router


app = FastAPI(
    title=settings.app_name,
    version=settings.app_version,
    description=(
        "FoodSense AI backend for demand forecasting, surplus prediction, "
        "and food waste analysis."
    ),
    debug=settings.debug,
)


# CORS configuration
allowed_origins = settings.allowed_origins
if allowed_origins == ["*"]:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )
else:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=allowed_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )


# Phase 2 AI routers
app.include_router(forecast_router)
app.include_router(surplus_router)
app.include_router(waste_router)


@app.get("/", tags=["system"])
def root() -> dict[str, str]:
    """Basic API information endpoint."""
    return {
        "name": settings.app_name,
        "version": settings.app_version,
        "environment": settings.environment,
        "status": "ok",
    }


@app.get("/health", tags=["system"])
def health() -> dict[str, str]:
    """Simple liveness check for the backend process."""
    return {
        "status": "healthy",
        "service": settings.app_name,
        "version": settings.app_version,
    }
