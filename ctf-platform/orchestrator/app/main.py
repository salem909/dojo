import asyncio
from fastapi import FastAPI, HTTPException, WebSocket, Header

from app.config import settings
from app.docker_client import (
    create_instance,
    stop_instance,
    list_instances,
    find_instance_container,
    garbage_collect,
)
from app.terminal import attach_terminal

app = FastAPI(title="CTF Orchestrator")


def _require_token(token: str | None):
    if token != settings.orch_token:
        raise HTTPException(status_code=401, detail="unauthorized")


@app.on_event("startup")
async def start_gc():
    async def gc_loop():
        while True:
            await asyncio.sleep(120)
            garbage_collect()

    asyncio.create_task(gc_loop())


@app.post("/instances/start")
def api_start_instance(payload: dict, x_orch_token: str | None = Header(default=None)):
    _require_token(x_orch_token)
    image = payload.get("image")
    user_id = payload.get("user_id")
    challenge_id = payload.get("challenge_id")
    public_key = payload.get("public_key")
    if not image or not user_id or not challenge_id:
        raise HTTPException(status_code=400, detail="missing fields")
    return create_instance(image, user_id, challenge_id, public_key)


@app.post("/instances/stop")
def api_stop_instance(payload: dict, x_orch_token: str | None = Header(default=None)):
    _require_token(x_orch_token)
    instance_id = payload.get("instance_id")
    if not instance_id:
        raise HTTPException(status_code=400, detail="missing instance_id")
    stop_instance(instance_id)
    return {"status": "stopped"}


@app.get("/instances")
def api_list_instances(user_id: int, x_orch_token: str | None = Header(default=None)):
    _require_token(x_orch_token)
    return list_instances(user_id)


@app.websocket("/ws/terminal/{instance_id}")
async def terminal_ws(websocket: WebSocket, instance_id: str):
    token = websocket.headers.get("x-orch-token")
    if token != settings.orch_token:
        await websocket.close(code=1008)
        return

    container = find_instance_container(instance_id)
    if not container:
        await websocket.close(code=1008)
        return

    await websocket.accept()
    await attach_terminal(websocket, container)
