from datetime import datetime
from sqlalchemy import Column, Integer, String, DateTime, Boolean

from app.db import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(64), unique=True, index=True, nullable=False)
    password_hash = Column(String(255), nullable=False)
    public_key = Column(String(4096), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)


class Instance(Base):
    __tablename__ = "instances"

    id = Column(String(64), primary_key=True, index=True)
    user_id = Column(Integer, index=True, nullable=False)
    challenge_id = Column(String(64), nullable=False)
    container_id = Column(String(128), nullable=False)
    status = Column(String(32), default="starting", nullable=False)
    ssh_host = Column(String(255), nullable=True)
    ssh_port = Column(Integer, nullable=True)
    started_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    last_active = Column(DateTime, default=datetime.utcnow, nullable=False)


class Submission(Base):
    __tablename__ = "submissions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, index=True, nullable=False)
    challenge_id = Column(String(64), nullable=False)
    flag = Column(String(256), nullable=False)
    correct = Column(Boolean, default=False, nullable=False)
    submitted_at = Column(DateTime, default=datetime.utcnow, nullable=False)
