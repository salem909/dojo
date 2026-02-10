from datetime import datetime
from pydantic import BaseModel


class RegisterRequest(BaseModel):
    username: str
    password: str


class LoginRequest(BaseModel):
    username: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class Challenge(BaseModel):
    id: str
    name: str
    description: str
    categories: list[str]
    image: str


class InstanceStartRequest(BaseModel):
    challenge_id: str


class InstanceResponse(BaseModel):
    id: str
    challenge_id: str
    status: str
    ssh_host: str | None = None
    ssh_port: int | None = None


class SubmitFlagRequest(BaseModel):
    challenge_id: str
    flag: str


class SubmissionResponse(BaseModel):
    correct: bool
    submitted_at: datetime


class PublicKeyRequest(BaseModel):
    public_key: str
