# Architecture Comparison: Current Platform vs Official pwn.college DOJO

## Executive Summary

The current platform is a **simplified CTF training system inspired by pwn.college**, while the official DOJO is a **comprehensive cybersecurity education platform**. Both work correctly, but serve different scales and use cases.

---

## Core Architectural Differences

### 1. Container Model

| Aspect | Current Platform | Official DOJO |
|--------|-----------------|---------------|
| **Container Lifecycle** | Per-challenge instance | Per-user persistent container |
| **Container Naming** | `challenge_{challenge_id}_{user_id}` | `user_{user_id}` |
| **Challenge Switching** | New container for each challenge | Same container, challenge files injected |
| **Resource Efficiency** | Lower (multiple containers per user) | Higher (one container per user) |

**Official DOJO Approach:**
```python
# Container name pattern
container_name = f"user_{user_id}"

# When starting a challenge, it reuses the same container:
# 1. Remove old challenge files
# 2. Insert new challenge files via docker cp
# 3. Write new flag to /flag
# No container restart needed
```

### 2. Base Platform

| Aspect | Current Platform | Official DOJO |
|--------|-----------------|---------------|
| **Framework** | Custom FastAPI backend | CTFd (Flask-based) with dojo_plugin |
| **Plugin System** | N/A (monolithic) | CTFd plugin architecture |
| **API Structure** | Custom REST endpoints | Flask-RestX namespaces |
| **Database** | SQLite with custom models | CTFd's challenge/user models extended |

**Impact:** Official DOJO leverages CTFd's existing:
- User management
- Challenge tracking
- Scoreboard system
- Admin interface
- Theme engine

### 3. Workspace Environment

| Aspect | Current Platform | Official DOJO |
|--------|-----------------|---------------|
| **Build System** | Dockerfile with apt packages | Nix flakes for reproducibility |
| **Tool Installation** | Basic (gcc, gdb, strace, etc.) | Comprehensive cybersecurity suite |
| **Environment Management** | Docker layers | Nix profiles with overlays |
| **User** | `ctf` user | `hacker` user (UID 1000) |

**Official DOJO Toolset (via Nix):**
- **Reversing:** ghidra, IDA-free, radare2, cutter, angr-management, binaryninja-free
- **Debugging:** gdb, pwndbg, gef
- **Exploitation:** AFL++, pwntools, ropper, ropgadget
- **Binary Analysis:** checksec, file, strings
- **Network:** wireshark, termshark, burpsuite, nmap
- **Web:** firefox, geckodriver
- **Development:** VSCode, vim, neovim, emacs

### 4. Access Methods

| Method | Current Platform | Official DOJO |
|--------|-----------------|---------------|
| **Browser Terminal** | ✅ xterm.js via WebSocket | ✅ Multiple options |
| **SSH Access** | ✅ Port 2222 (random mapping) | ✅ Port 22 mapped |
| **Code Editor (Browser)** | ❌ Not implemented | ✅ code-server on port 8080 |
| **Desktop GUI** | ❌ Not implemented | ✅ XFCE + noVNC on port 6080 |

**Official DOJO Workspace Services:**
```python
port_names = {
    "challenge": 80,      # Challenge-specific web interface
    "terminal": 7681,     # ttyd terminal (alternative)
    "code": 8080,         # VSCode in browser
    "desktop": 6080,      # XFCE desktop via noVNC
    "desktop-windows": 6082  # Alternative desktop config
}
```

### 5. Challenge Delivery

| Aspect | Current Platform | Official DOJO |
|--------|-----------------|---------------|
| **Challenge Files** | Copied during container creation | Injected via `docker cp` to running container |
| **Flag Generation** | Per-challenge-instance via environment | Per-challenge via stdin to container init |
| **Challenge Switch** | Stop old container, start new | Keep container running, swap files |
| **Home Directory** | Mounted per-container | Persistent across challenges |

**Official DOJO Flag Insertion:**
```python
def insert_flag(container, flag):
    flag = f"pwn.college{{{flag}}}"
    socket = container.attach_socket(params=dict(stdin=1, stream=1))
    socket._sock.sendall(flag.encode() + b"\n")
    socket.close()
```

### 6. Service Management

| Aspect | Current Platform | Official DOJO |
|--------|-----------------|---------------|
| **On-Demand Services** | None | code-server, desktop, terminal |
| **Service Startup** | N/A | Via `dojo-service` command |
| **Service Persistence** | N/A | PID files in `/run/dojo/var/` |
| **Service Logs** | N/A | `/run/dojo/var/<service>.log` |

**Official DOJO Service Architecture:**
```python
# workspace/services/service.py
def daemonize(program, args, log_file, pid_file):
    """Start a service as a daemon process"""
    
def start_service(service_name):
    """Start an on-demand service like code or desktop"""
    
def stop_service(service_name):
    """Stop a running service"""
```

### 7. Authentication & CLI

| Aspect | Current Platform | Official DOJO |
|--------|-----------------|---------------|
| **Web Auth** | JWT tokens | CTFd session cookies |
| **Container Auth** | SSH keys | Workspace tokens + SSH keys |
| **CLI Tool** | None | `dojo` command in containers |
| **Flag Submission** | Web UI only | Web UI + CLI (`dojo submit`) |

**Official DOJO CLI Commands:**
```bash
dojo whoami              # Show current user
dojo submit <flag>       # Submit flag from container
dojo start <challenge>   # Switch to different challenge
dojo restart -N          # Restart in normal mode
dojo restart -P          # Restart in privileged mode
```

---

## Current Implementation Strengths

✅ **Working end-to-end flow** - All core functionality operational  
✅ **Simpler architecture** - Easier to understand and deploy  
✅ **Independent service** - No CTFd dependency  
✅ **Container isolation** - Per-challenge security boundaries  
✅ **Modern stack** - FastAPI, Vue.js potential  

---

## Missing Critical Features

### High Priority (Core DOJO Experience)

1. **❌ Browser Code Editor (code-server)**
   - Official DOJO provides VSCode in browser on port 8080
   - Students can edit exploit scripts, browse challenge files
   - Pre-configured with extensions (Python, C/C++)

2. **❌ Desktop Environment (XFCE + noVNC)**
   - Official DOJO provides full GUI on port 6080
   - Students can run graphical tools (ghidra, IDA, wireshark)
   - Essential for reverse engineering challenges

3. **❌ Per-User Persistent Containers**
   - Official DOJO keeps one container per user
   - Home directory persists across challenges
   - More resource-efficient

4. **❌ Container CLI Tool**
   - Official DOJO provides `dojo` command inside containers
   - Students can submit flags, switch challenges from terminal

5. **❌ Comprehensive Toolset**
   - Official DOJO has 50+ cybersecurity tools via Nix
   - Current platform has ~10 basic tools

### Medium Priority (Enhanced Functionality)

6. **❌ Nix-based Workspace**
   - Official DOJO uses Nix flakes for reproducibility
   - Easier to update tools across all challenges
   - Better version control

7. **❌ Service Management**
   - Official DOJO starts services on-demand
   - Saves resources when students don't use GUI/code editor

8. **❌ Advanced Networking**
   - Official DOJO supports custom network configs
   - Per-user Docker networks with isolation

9. **❌ Privileged Mode**
   - Official DOJO allows challenges to request elevated privileges
   - Needed for kernel exploitation, Docker-in-Docker

### Low Priority (Nice to Have)

10. **❌ MAC Hardware Support**
    - Official DOJO has mac_docker.py for Apple Silicon
    - Specialized challenge execution on physical hardware

11. **❌ Multiple Workspace Nodes**
    - Official DOJO distributes users across worker nodes
    - Load balancing for large deployments

12. **❌ User Federation**
    - Official DOJO integrates with Discord, OIDC
    - Social features for learning communities

---

## Recommended Actions

### Option 1: **Selective Feature Additions** (Recommended)
Keep current FastAPI architecture, add critical DOJO features:

**Phase 1: Workspace Services (2-3 days)**
1. Add code-server container sidecar on port 8080
2. Add XFCE desktop container sidecar on port 6080  
3. Update frontend to show service tabs (Terminal | Code | Desktop)

**Phase 2: Enhanced Toolset (1 day)**
4. Update challenge base image with comprehensive tools
5. Add Dockerfile with ghidra, pwndbg, gef, radare2, etc.

**Phase 3: Container CLI (1 day)**
6. Create `dojo` CLI script inside containers
7. Support `dojo submit`, `dojo whoami`, `dojo restart`

**Phase 4: Per-User Containers (2 days)**
8. Refactor to persistent user containers
9. Implement challenge file injection
10. Update home directory persistence

**Total Effort:** ~6-7 days of development

### Option 2: **Full DOJO Rewrite** (Not Recommended)
Rebuild entire platform using CTFd + dojo_plugin:

- Migrate to CTFd base (Flask)
- Install official dojo_plugin
- Adopt Nix workspace build system
- Replicate official DOJO architecture

**Total Effort:**  ~3-4 weeks (essentially starting over)

### Option 3: **Minimal Enhancements** (Quick Win)
Keep everything as-is, add only:

1. Comprehensive toolset to base image (1 day)
2. Container CLI for flag submission (1 day)  
3. Code-server as optional addon (1 day)

**Total Effort:** ~3 days

---

## Risk Assessment

### If We Don't Align:

**User Experience Gaps:**
- ❌ No GUI tools for reverse engineering
- ❌ No convenient code editor in browser
- ❌ Limited toolset compared to official DOJO
- ❌ Different workflow (students may be confused)

**Operational Issues:**
- ❌ Higher resource usage (multiple containers per user)
- ❌ Slower challenge switching (container restart overhead)
- ❌ Limited scalability

**Pedagogical Impact:**
- ❌ Students can't use ghidra, IDA, wireshark effectively
- ❌ Missing tools needed for advanced challenges
- ❌ Harder to follow official pwn.college courses

### If We Fully Rewrite:

**Development Risks:**
- ❌ 3-4 weeks of work to rebuild
- ❌ Current working system discarded
- ❌ Need to learn CTFd plugin system
- ❌ Dependency on CTFd project

---

## Concrete Next Steps

I recommend **Option 1: Selective Feature Additions** with this priority:

### Immediate (Today)
1. ✅ Document architecture differences (this file)
2. ⏳ Get user approval on approach

### Week 1: Core Services
3. Add code-server integration
4. Add desktop environment (XFCE + noVNC)
5. Update frontend with service tabs

### Week 2: Toolset & CLI
6. Enhance base image with comprehensive tools
7. Implement `dojo` CLI inside containers
8. Add in-container flag submission

### Week 3: Optimization
9. Refactor to per-user persistent containers
10. Implement challenge file injection
11. Performance testing

---

## Decision Required

**Question:** Which approach should we take?

- **A.** Selective additions (recommended) - add code-server, desktop, tools, CLI
- **B.** Full rewrite using CTFd + official dojo_plugin
- **C.** Minimal enhancements - just add tools and CLI
- **D.** Keep as-is - current implementation is "inspired by" not "clone of"

Please advise on your preferred direction.
