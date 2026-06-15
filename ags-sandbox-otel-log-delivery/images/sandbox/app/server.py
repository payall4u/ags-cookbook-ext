import asyncio
import logging
import os
import socket
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI


SERVICE_NAME = os.getenv("SERVICE_NAME", "ags-log-delivery-demo")
HOSTNAME = socket.gethostname()
LOG_DIR = Path(os.getenv("APP_LOG_DIR", "/app/logs"))
LOG_DIR.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s service=%(service_name)s host=%(host)s message=%(message)s",
)
logger = logging.getLogger("ags-log-delivery")
file_handler = logging.FileHandler(LOG_DIR / "app.log")
file_handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s service=%(service_name)s host=%(host)s message=%(message)s"))
logger.addHandler(file_handler)


def log_info(message: str, **fields: object) -> None:
    logger.info(
        "%s %s",
        message,
        " ".join(f"{key}={value}" for key, value in sorted(fields.items())),
        extra={"service_name": SERVICE_NAME, "host": HOSTNAME},
    )


async def heartbeat() -> None:
    index = 0
    while True:
        log_info("ags-log-delivery-demo heartbeat", tick=index)
        index += 1
        await asyncio.sleep(10)


@asynccontextmanager
async def lifespan(app: FastAPI):
    task = asyncio.create_task(heartbeat())
    log_info("ags-log-delivery-demo startup", port=os.getenv("APP_PORT", "8080"))
    try:
        yield
    finally:
        task.cancel()
        log_info("ags-log-delivery-demo shutdown")


app = FastAPI(lifespan=lifespan)


@app.get("/health")
async def health() -> dict[str, str]:
    log_info("ags-log-delivery-demo health check")
    return {"status": "ok", "service": SERVICE_NAME}


@app.get("/")
async def root() -> dict[str, str]:
    log_info("ags-log-delivery-demo request", path="/")
    return {"message": "hello from ags log delivery demo"}
