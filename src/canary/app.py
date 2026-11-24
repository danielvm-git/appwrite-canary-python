# story: e02s01
from importlib.metadata import PackageNotFoundError, version
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

ROOT = Path(__file__).resolve().parents[2]
VERSION_FALLBACK = "dev"


def read_version() -> str:
    version_file = ROOT / "VERSION"
    if version_file.is_file():
        return version_file.read_text(encoding="utf-8").strip()
    try:
        return version("appwrite-canary-python")
    except PackageNotFoundError:
        return VERSION_FALLBACK


def create_app() -> FastAPI:
    app = FastAPI(title="appwrite-canary-python", version=read_version())
    templates = Jinja2Templates(directory=str(ROOT / "templates"))
    static_dir = ROOT / "static"
    if static_dir.is_dir():
        app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")

    @app.get("/health")
    def health() -> JSONResponse:
        return JSONResponse({"status": "ok", "version": read_version()})

    @app.get("/", response_class=HTMLResponse)
    def home(request: Request) -> HTMLResponse:
        return templates.TemplateResponse(
            request,
            "index.html",
            {"version": read_version()},
        )

    return app


app = create_app()