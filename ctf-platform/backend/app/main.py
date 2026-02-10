import asyncio
import json
from datetime import datetime
from pathlib import Path
from typing import Generator

import websockets
from fastapi import FastAPI, Depends, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from app import models, schemas
from app.auth import hash_password, verify_password, create_access_token, decode_token
from app.config import settings
from app.db import Base, engine, get_db
from app.orchestrator_client import OrchestratorClient

app = FastAPI(title="CTF Platform API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

Base.metadata.create_all(bind=engine)

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/login")
orchestrator = OrchestratorClient()


def load_challenges() -> list[dict]:
    data = Path(settings.challenges_path).read_text(encoding="utf-8")
    return json.loads(data)


def get_current_user(
    token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)
) -> models.User:
    username = decode_token(token)
    if not username:
        raise HTTPException(status_code=401, detail="invalid token")
    user = db.query(models.User).filter(models.User.username == username).first()
    if not user:
        raise HTTPException(status_code=401, detail="user not found")
    return user


def get_current_user_ws(websocket: WebSocket, db: Session) -> models.User:
    token = websocket.query_params.get("token")
    if not token:
        raise HTTPException(status_code=401, detail="token missing")
    username = decode_token(token)
    if not username:
        raise HTTPException(status_code=401, detail="invalid token")
    user = db.query(models.User).filter(models.User.username == username).first()
    if not user:
        raise HTTPException(status_code=401, detail="user not found")
    return user


@app.post("/api/register", response_model=schemas.TokenResponse)
def register(payload: schemas.RegisterRequest, db: Session = Depends(get_db)):
    existing = db.query(models.User).filter(models.User.username == payload.username).first()
    if existing:
        raise HTTPException(status_code=400, detail="username exists")
    user = models.User(
        username=payload.username, password_hash=hash_password(payload.password)
    )
    db.add(user)
    db.commit()
    token = create_access_token(user.username)
    return schemas.TokenResponse(access_token=token)


@app.post("/api/login", response_model=schemas.TokenResponse)
def login(payload: schemas.LoginRequest, db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.username == payload.username).first()
    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="invalid credentials")
    token = create_access_token(user.username)
    return schemas.TokenResponse(access_token=token)


@app.get("/api/challenges", response_model=list[schemas.Challenge])
def list_challenges(user: models.User = Depends(get_current_user)):
    challenges = load_challenges()
    return [schemas.Challenge(**c) for c in challenges]


@app.post("/api/profile/key")
def upload_key(
    payload: schemas.PublicKeyRequest,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    user.public_key = payload.public_key.strip()
    db.commit()
    return {"status": "ok"}


@app.get("/api/instances", response_model=list[schemas.InstanceResponse])
def list_instances(
    user: models.User = Depends(get_current_user), db: Session = Depends(get_db)
):
    rows = (
        db.query(models.Instance)
        .filter(models.Instance.user_id == user.id)
        .all()
    )
    return [
        schemas.InstanceResponse(
            id=row.id,
            challenge_id=row.challenge_id,
            status=row.status,
            ssh_host=row.ssh_host,
            ssh_port=row.ssh_port,
        )
        for row in rows
    ]


@app.post("/api/instances/start", response_model=schemas.InstanceResponse)
def start_instance(
    payload: schemas.InstanceStartRequest,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    challenges = load_challenges()
    challenge = next((c for c in challenges if c["id"] == payload.challenge_id), None)
    if not challenge:
        raise HTTPException(status_code=404, detail="challenge not found")

    orch_payload = {
        "user_id": user.id,
        "challenge_id": payload.challenge_id,
        "image": challenge["image"],
        "public_key": user.public_key,
    }
    orch_resp = orchestrator.start_instance(orch_payload)

    instance = models.Instance(
        id=orch_resp["instance_id"],
        user_id=user.id,
        challenge_id=payload.challenge_id,
        container_id=orch_resp["container_id"],
        status="running",
        ssh_host=orch_resp.get("ssh_host"),
        ssh_port=orch_resp.get("ssh_port"),
        started_at=datetime.utcnow(),
        last_active=datetime.utcnow(),
    )
    db.add(instance)
    db.commit()

    return schemas.InstanceResponse(
        id=instance.id,
        challenge_id=instance.challenge_id,
        status=instance.status,
        ssh_host=instance.ssh_host,
        ssh_port=instance.ssh_port,
    )


@app.post("/api/instances/stop")
def stop_instance(
    instance_id: str,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    instance = (
        db.query(models.Instance)
        .filter(models.Instance.id == instance_id, models.Instance.user_id == user.id)
        .first()
    )
    if not instance:
        raise HTTPException(status_code=404, detail="instance not found")
    orchestrator.stop_instance(instance.id)
    instance.status = "stopped"
    db.commit()
    return {"status": "stopped"}


@app.post("/api/submit", response_model=schemas.SubmissionResponse)
def submit_flag(
    payload: schemas.SubmitFlagRequest,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    challenges = load_challenges()
    challenge = next((c for c in challenges if c["id"] == payload.challenge_id), None)
    if not challenge:
        raise HTTPException(status_code=404, detail="challenge not found")

    correct = payload.flag.strip() == challenge.get("flag")
    submission = models.Submission(
        user_id=user.id,
        challenge_id=payload.challenge_id,
        flag=payload.flag.strip(),
        correct=correct,
        submitted_at=datetime.utcnow(),
    )
    db.add(submission)
    db.commit()
    return schemas.SubmissionResponse(correct=correct, submitted_at=submission.submitted_at)


@app.websocket("/ws/terminal/{instance_id}")
async def terminal_proxy(websocket: WebSocket, instance_id: str):
    db = next(get_db())
    try:
        user = get_current_user_ws(websocket, db)
        instance = (
            db.query(models.Instance)
            .filter(models.Instance.id == instance_id, models.Instance.user_id == user.id)
            .first()
        )
        if not instance or instance.status != "running":
            await websocket.close(code=1008)
            return

        await websocket.accept()
        orch_url = f"{settings.orchestrator_ws_url}/ws/terminal/{instance_id}"
        headers = [("X-ORCH-TOKEN", settings.orchestrator_token)]

        try:
            async with websockets.connect(orch_url, extra_headers=headers) as orch_ws:
                async def client_to_orch():
                    try:
                        while True:
                            message = await websocket.receive()
                            data = message.get("bytes")
                            if data is None:
                                text = message.get("text")
                                if text is None:
                                    continue
                                data = text.encode("utf-8")
                            await orch_ws.send(data)
                    except (WebSocketDisconnect, Exception):
                        pass

                async def orch_to_client():
                    try:
                        while True:
                            data = await orch_ws.recv()
                            if isinstance(data, str):
                                await websocket.send_text(data)
                            else:
                                await websocket.send_bytes(data)
                    except Exception:
                        pass

                await asyncio.gather(client_to_orch(), orch_to_client(), return_exceptions=True)
        except (WebSocketDisconnect, Exception):
            pass
    finally:
        db.close()
