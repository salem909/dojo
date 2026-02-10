import requests

from app.config import settings


class OrchestratorClient:
    def __init__(self) -> None:
        self.base_url = settings.orchestrator_url
        self.token = settings.orchestrator_token

    def start_instance(self, payload: dict) -> dict:
        resp = requests.post(
            f"{self.base_url}/instances/start",
            json=payload,
            headers={"X-ORCH-TOKEN": self.token},
            timeout=20,
        )
        resp.raise_for_status()
        return resp.json()

    def stop_instance(self, instance_id: str) -> None:
        resp = requests.post(
            f"{self.base_url}/instances/stop",
            json={"instance_id": instance_id},
            headers={"X-ORCH-TOKEN": self.token},
            timeout=20,
        )
        resp.raise_for_status()

    def list_instances(self, user_id: int) -> list[dict]:
        resp = requests.get(
            f"{self.base_url}/instances",
            params={"user_id": user_id},
            headers={"X-ORCH-TOKEN": self.token},
            timeout=20,
        )
        resp.raise_for_status()
        return resp.json()
