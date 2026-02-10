# DOJO - CTF Training Platform

Production-ready, self-hosted CTF training platform with per-user isolated Linux environments.

## Features

- **Per-user isolated containers** with resource limits (CPU, memory, PIDs)
- **Browser terminal** via xterm.js + WebSocket proxy
- **SSH access** with public key authentication
- **10 beginner challenges** covering Linux basics, permissions, scripting, reversing, web, and debugging
- **Security hardening**: dropped capabilities, seccomp profiles, network isolation, non-root execution
- **REST API** for instance management, flag submission, and progress tracking

## Quick Start

```bash
cd ctf-platform
chmod +x challenges/build_all.sh
./challenges/build_all.sh
docker compose up --build -d
```

Access the platform at http://localhost:8080

## Documentation

See [ctf-platform/README.md](ctf-platform/README.md) for complete setup, deployment, and challenge authoring instructions.

## Architecture

- **Backend**: FastAPI (Python) - auth, API, flag validation
- **Orchestrator**: FastAPI + Docker SDK - container lifecycle
- **Frontend**: Static HTML/JS with xterm.js
- **Database**: SQLite
- **Containers**: Ubuntu 24.04 base with OpenSSH, dev tools

## Security Model

- Seccomp profile blocks dangerous syscalls (mount, ptrace, kexec_load)
- Capabilities dropped, only essential ones added (SETUID, SETGID, CHOWN, NET_BIND_SERVICE)
- Per-instance isolated networks (no internet access)
- Flags protected by setuid binaries
- SSH password auth disabled
- Automatic garbage collection of long-running instances

