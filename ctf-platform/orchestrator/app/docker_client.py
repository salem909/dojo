import datetime
import uuid
from typing import Any

import docker

from app.config import settings


def _nano_cpus(cpu_limit: float) -> int:
    return int(cpu_limit * 1_000_000_000)


def docker_client() -> docker.DockerClient:
    return docker.from_env()


def create_instance(image: str, user_id: int, challenge_id: str, public_key: str | None) -> dict:
    client = docker_client()
    instance_id = str(uuid.uuid4())
    network_name = f"ctf-net-{instance_id[:12]}"
    volume_name = f"ctf-home-{user_id}-{challenge_id}"

    network = client.networks.create(name=network_name, internal=True)

    labels = {
        "ctf.instance_id": instance_id,
        "ctf.user_id": str(user_id),
        "ctf.challenge_id": challenge_id,
        "ctf.started_at": datetime.datetime.utcnow().isoformat(),
    }

    container = client.containers.run(
        image=image,
        detach=True,
        name=f"ctf-{instance_id[:12]}",
        environment={"PUBLIC_KEY": public_key or ""},
        labels=labels,
        ports={"2222/tcp": None},
        volumes={volume_name: {"bind": "/home/ctf", "mode": "rw"}},
        network=network.name,
        mem_limit=settings.mem_limit,
        nano_cpus=_nano_cpus(settings.cpu_limit),
        pids_limit=128,
        security_opt=[f"seccomp={settings.seccomp_profile_path}"],
        cap_drop=["ALL"],
        cap_add=["CHOWN", "SETUID", "SETGID", "NET_BIND_SERVICE"],
    )

    container.reload()
    port_info = container.attrs["NetworkSettings"]["Ports"].get("2222/tcp")
    host_port = int(port_info[0]["HostPort"]) if port_info else None

    return {
        "instance_id": instance_id,
        "container_id": container.id,
        "ssh_host": "127.0.0.1",
        "ssh_port": host_port,
    }


def find_instance_container(instance_id: str) -> docker.models.containers.Container | None:
    client = docker_client()
    containers = client.containers.list(
        all=True, filters={"label": f"ctf.instance_id={instance_id}"}
    )
    return containers[0] if containers else None


def stop_instance(instance_id: str) -> None:
    container = find_instance_container(instance_id)
    if not container:
        return
    network_name = None
    for net_name, net_data in container.attrs.get("NetworkSettings", {}).get("Networks", {}).items():
        if net_name.startswith("ctf-net-"):
            network_name = net_name
            break
    container.stop(timeout=10)
    container.remove(v=True)
    if network_name:
        try:
            client = docker_client()
            net = client.networks.get(network_name)
            net.remove()
        except docker.errors.NotFound:
            pass


def list_instances(user_id: int) -> list[dict[str, Any]]:
    client = docker_client()
    containers = client.containers.list(
        all=True, filters={"label": f"ctf.user_id={user_id}"}
    )
    items: list[dict[str, Any]] = []
    for container in containers:
        labels = container.labels
        items.append(
            {
                "instance_id": labels.get("ctf.instance_id"),
                "challenge_id": labels.get("ctf.challenge_id"),
                "status": container.status,
            }
        )
    return items


def garbage_collect() -> list[str]:
    client = docker_client()
    now = datetime.datetime.utcnow()
    stopped: list[str] = []
    containers = client.containers.list(all=True, filters={"label": "ctf.instance_id"})
    for container in containers:
        labels = container.labels
        started = labels.get("ctf.started_at")
        if not started:
            continue
        started_at = datetime.datetime.fromisoformat(started)
        age = (now - started_at).total_seconds()
        if age > settings.max_runtime_seconds:
            instance_id = labels.get("ctf.instance_id")
            if instance_id:
                stop_instance(instance_id)
                stopped.append(instance_id)
    return stopped
