# CTF Platform

Self-hosted CTF training platform with per-user isolated challenge containers, web UI, browser terminal, and SSH access.

## Quick Start

1. Build challenge images:

```bash
cd ctf-platform
chmod +x challenges/build_all.sh
./challenges/build_all.sh
```

2. Start the platform:

```bash
docker compose up --build
```

3. Open the UI:

- Frontend: http://localhost:8080
- Backend API: http://localhost:8000
- Orchestrator: http://localhost:8001

## Deployment Steps (Single Host)

1. Install Docker Engine and Docker Compose on the host.
2. Clone the repository and enter the platform directory:

```bash
git clone https://github.com/salem909/dojo.git
cd dojo/ctf-platform
```

3. Build the challenge images:

```bash
chmod +x challenges/build_all.sh
./challenges/build_all.sh
```

4. Configure secrets and limits via environment variables (optional):

```bash
export SECRET_KEY="change-me"
export ORCHESTRATOR_TOKEN="change-me"
export CPU_LIMIT="0.5"
export MEM_LIMIT="256m"
export MAX_RUNTIME_SECONDS="3600"
```

5. Start the stack:

```bash
docker compose up --build -d
```

6. Verify:

```bash
docker compose ps
```

7. Access the UI at http://<host>:8080

## Security Notes

- Containers drop Linux capabilities and apply a custom seccomp profile.
- Per-instance network isolation is enabled via dedicated Docker networks.
- Challenge environments run as an unprivileged user for interactive shells.
- SSH access uses user-supplied public keys (no passwords).
- Flags are stored in /flag and read via a setuid helper.

## Challenge Structure

Each challenge lives in `challenges/challengeXX/` and includes:

- `Dockerfile`
- `instructions.txt`
- `challenge.json`
- Any challenge files (binaries/scripts/data)

The challenge registry is `challenges/challenges.json`.

## Adding a New Challenge

1. Copy an existing challenge directory and update its files.
2. Update `challenge.json` with a unique id, image, and flag.
3. Add the new entry to `challenges/challenges.json`.
4. Build the image:

```bash
docker build -t ctf/challenge11:latest ./challenges/challenge11
```

## SSH Access

- Upload your public key in the dashboard.
- Start an instance and use the provided `ssh -p PORT ctf@HOST` command.

## Generate an SSH Key

If you do not already have one, generate a key pair on your machine:

```bash
ssh-keygen -t ed25519 -C "ctf-user"
```

Then upload the contents of your public key file (usually `~/.ssh/id_ed25519.pub`) into the dashboard.

## Browser Terminal

- Use the “Browser Terminal” button on an instance card.
- The terminal uses xterm.js via a websocket proxy.
