from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .config import settings
from .database import open_pool, close_pool, get_connection
from .api.auth import router as auth_router
from .api.impact import router as impact_router

@asynccontextmanager
async def lifespan(app: FastAPI):
    open_pool()
    yield
    close_pool()

app = FastAPI(title=settings.app_name, version="0.1.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=[settings.frontend_origin], allow_credentials=True,
                   allow_methods=["GET","POST","PUT","PATCH","DELETE"], allow_headers=["Authorization","Content-Type"])
app.include_router(auth_router)
app.include_router(impact_router)

@app.get("/health", tags=["system"])
def health():
    with get_connection() as conn:
        conn.execute("SELECT 1")
    return {"status":"ok","service":"foodbridge-api","database":"connected"}
