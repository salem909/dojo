import asyncio
from typing import Any

import docker
from fastapi import WebSocket


async def attach_terminal(websocket: WebSocket, container: docker.models.containers.Container) -> None:
    api = docker.APIClient()
    exec_id = api.exec_create(
        container.id,
        cmd=["/bin/bash", "-l"],
        tty=True,
        stdin=True,
        user="ctf",
    )["Id"]

    sock = api.exec_start(exec_id, tty=True, stream=False, socket=True)

    async def recv_from_container():
        while True:
            data = await asyncio.to_thread(sock.recv, 4096)
            if not data:
                break
            await websocket.send_bytes(data)

    async def recv_from_client():
        while True:
            data = await websocket.receive_bytes()
            await asyncio.to_thread(sock.send, data)

    await asyncio.gather(recv_from_container(), recv_from_client())
