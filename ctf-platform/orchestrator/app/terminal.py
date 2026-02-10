import asyncio
from typing import Any

import docker
from fastapi import WebSocket


async def attach_terminal(websocket: WebSocket, container: docker.models.containers.Container) -> None:
    api = docker.APIClient()
    
    # Ensure container is running
    try:
        container.reload()
        if container.status != "running":
            await websocket.send_text(f"Error: Container is {container.status}\r\n")
            return
    except Exception as e:
        await websocket.send_text(f"Error: Cannot access container: {e}\r\n")
        return
    
    try:
        exec_id = api.exec_create(
            container.id,
            cmd=["/bin/bash", "-l"],
            tty=True,
            stdin=True,
            user="ctf",
        )["Id"]
    except Exception as e:
        await websocket.send_text(f"Error creating exec: {e}\r\n")
        return

    try:
        sock = api.exec_start(exec_id, tty=True, stream=False, socket=True)
    except Exception as e:
        await websocket.send_text(f"Error starting exec: {e}\r\n")
        return

    async def recv_from_container():
        try:
            while True:
                data = await asyncio.to_thread(sock.recv, 4096)
                if not data:
                    break
                await websocket.send_bytes(data)
        except Exception:
            pass

    async def recv_from_client():
        try:
            while True:
                message = await websocket.receive()
                data = message.get("bytes")
                if data is None:
                    text = message.get("text")
                    if text is None:
                        continue
                    data = text.encode("utf-8")
                await asyncio.to_thread(sock.send, data)
        except Exception:
            pass

    await asyncio.gather(recv_from_container(), recv_from_client(), return_exceptions=True)
