import os


class Settings:
    def __init__(self) -> None:
        self.orch_token = os.environ.get("ORCH_TOKEN", "orch-dev-token")
        self.cpu_limit = float(os.environ.get("CPU_LIMIT", "0.5"))
        self.mem_limit = os.environ.get("MEM_LIMIT", "256m")
        self.max_runtime_seconds = int(os.environ.get("MAX_RUNTIME_SECONDS", "3600"))
        self.seccomp_profile_path = os.environ.get(
            "SECCOMP_PROFILE_PATH", "/app/seccomp.json"
        )


settings = Settings()
