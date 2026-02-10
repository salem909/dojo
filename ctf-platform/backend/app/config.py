import os


class Settings:
    def __init__(self) -> None:
        self.secret_key = os.environ.get("SECRET_KEY", "dev-secret")
        self.jwt_alg = "HS256"
        self.access_token_exp_minutes = int(
            os.environ.get("ACCESS_TOKEN_EXP_MINUTES", "1440")
        )
        self.database_url = os.environ.get("DATABASE_URL", "sqlite:///./data/app.db")
        self.orchestrator_url = os.environ.get(
            "ORCHESTRATOR_URL", "http://orchestrator:8001"
        )
        self.orchestrator_ws_url = os.environ.get(
            "ORCHESTRATOR_WS_URL", "ws://orchestrator:8001"
        )
        self.orchestrator_token = os.environ.get("ORCHESTRATOR_TOKEN", "orch-dev-token")
        self.challenges_path = os.environ.get("CHALLENGES_PATH", "/data/challenges.json")


settings = Settings()
