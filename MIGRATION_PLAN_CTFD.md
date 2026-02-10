# Migration Plan: FastAPI → CTFd + dojo_plugin

## Overview

Complete architectural migration from custom FastAPI backend to official pwn.college DOJO architecture using CTFd platform.

**Estimated Timeline:** 3-4 weeks  
**Risk Level:** High (complete system replacement)  
**Reversibility:** Low (will need git branch to preserve current implementation)

---

## Phase 1: Foundation Setup (Week 1)

### Day 1-2: CTFd Base Installation

**Tasks:**
1. Create new directory structure alongside current platform
2. Clone/install CTFd 3.7.x
3. Configure CTFd base settings
4. Set up PostgreSQL/MySQL database
5. Test basic CTFd functionality

**Deliverables:**
- `/workspaces/dojo/ctfd-dojo/` directory
- Working CTFd instance on port 8000
- Database schema initialized
- Admin user created

**Files to Create:**
```
ctfd-dojo/
├── docker-compose.yml        # CTFd + Redis + DB + orchestration
├── CTFd/                      # CTFd submodule or clone
├── dojo_plugin/              # Official dojo_plugin
├── workspace/                # Nix workspace definition
└── config.env                # Environment configuration
```

### Day 3: Official dojo_plugin Integration

**Tasks:**
1. Clone official pwncollege/dojo repository
2. Extract dojo_plugin, dojo_theme components
3. Install plugin in CTFd
4. Configure plugin settings
5. Test plugin activation

**Key Plugin Components:**
- `dojo_plugin/` - Core plugin logic
- `dojo_theme/` - Custom UI theme
- `dojo_plugin/api/` - REST API endpoints
- `dojo_plugin/models.py` - Database models
- `dojo_plugin/pages/` - Web routes

### Day 4-5: Database Migration

**Tasks:**
1. Export current user data from SQLite
2. Transform to CTFd user schema
3. Export challenge/solve data
4. Import into CTFd database
5. Verify data integrity

**Migration Script:**
```python
# scripts/migrate_to_ctfd.py
def migrate_users():
    # Export from: backend/database.db (Users table)
    # Import to: CTFd database (users table)
    
def migrate_challenges():
    # Export from: backend/database.db (Challenges table)
    # Import to: CTFd database via dojo_plugin models
    
def migrate_solves():
    # Export from: backend/database.db (Submissions table)
    # Import to: CTFd solves table
```

---

## Phase 2: Workspace Environment (Week 2)

### Day 6-7: Nix Workspace Setup

**Tasks:**
1. Set up Nix flake for workspace build
2. Configure core packages (init, exec-suid, sudo)
3. Add comprehensive toolset (ghidra, IDA, pwndbg, etc.)
4. Build workspace Docker image
5. Test workspace initialization

**Nix Flake Structure:**
```nix
workspace/
├── flake.nix                 # Main flake definition
├── flake.lock               # Locked dependencies
├── Dockerfile               # Alpine + Nix builder
├── core/
│   ├── init.nix            # dojo-init script
│   ├── sudo.nix            # Custom sudo for workspace
│   └── ssh-entrypoint.nix  # SSH entry configuration
├── services/
│   ├── code.nix            # code-server service
│   ├── desktop.nix         # XFCE + noVNC service
│   └── service.py          # Service management
└── additional/
    ├── additional.nix      # Main toolset
    ├── ghidra.nix         # Ghidra package
    └── burpsuite.nix      # Burpsuite package
```

### Day 8-9: Service Integration

**Tasks:**
1. Implement code-server service (port 8080)
2. Implement desktop service (XFCE + noVNC, port 6080)
3. Configure on-demand service startup
4. Add service management endpoints
5. Test service lifecycle

**Service Architecture:**
```python
# dojo_plugin/utils/workspace.py
def start_on_demand_service(user, service_name):
    """Start code or desktop service if not running"""
    container = get_current_container(user)
    exec_run(f"dojo-service start {service_name}", container=container)

# Frontend integration
port_names = {
    "challenge": 80,
    "terminal": 7681,
    "code": 8080,
    "desktop": 6080,
}
```

### Day 10: Container Orchestration

**Tasks:**
1. Refactor to per-user persistent containers
2. Implement container naming: `user_{user_id}`
3. Create container lifecycle management
4. Implement challenge file injection via docker cp
5. Update flag delivery mechanism

**Container Model Changes:**
```python
# OLD: Per-challenge containers
container_name = f"challenge_{challenge_id}_{user_id}"
# Each challenge gets new container

# NEW: Per-user persistent containers  
container_name = f"user_{user_id}"
# Same container, swap challenge files
```

---

## Phase 3: Frontend & API (Week 3)

### Day 11-12: API Endpoints

**Tasks:**
1. Migrate Docker API to Flask-RestX
2. Implement Dojos API (list, modules, challenges)
3. Implement Scoreboard API
4. Implement Workspace API (services, reset)
5. Test all endpoints

**API Namespace Structure:**
```python
/pwncollege_api/v1/
├── /docker          # Container management
├── /dojos           # Dojo/module/challenge listing
├── /scoreboard      # Rankings and stats
├── /workspace       # Service URLs and management
├── /user            # User info and tokens
└── /belts           # Achievement system
```

### Day 13-14: Frontend Migration

**Tasks:**
1. Integrate dojo_theme with CTFd
2. Update frontend to use CTFd routes
3. Migrate terminal connection logic
4. Add workspace service tabs (Terminal | Code | Desktop)
5. Update challenge interface

**Key Frontend Changes:**
```javascript
// OLD: Custom FastAPI endpoints
fetch('/api/challenges')

// NEW: CTFd + dojo_plugin endpoints  
fetch('/pwncollege_api/v1/dojos')
fetch('/pwncollege_api/v1/docker')
```

### Day 15: Container CLI

**Tasks:**
1. Create `dojo` CLI script in workspace
2. Implement `dojo whoami` command
3. Implement `dojo submit <flag>` command
4. Implement `dojo start <challenge>` command
5. Implement `dojo restart` with mode flags

**CLI Implementation:**
```python
# workspace/core/dojo-cli.py
#!/usr/bin/env python3

def whoami():
    response = requests.get(
        f"{DOJO_API}/users/me",
        headers={"Authorization": f"Bearer {DOJO_AUTH_TOKEN}"}
    )
    print(f"You are {response.json()['name']}")

def submit_flag(flag):
    challenge = get_current_challenge()
    response = requests.post(
        f"{DOJO_API}/dojos/{challenge['dojo']}/challenges/solve",
        json={"submission": flag}
    )
    # Handle response
```

---

## Phase 4: Testing & Migration (Week 4)

### Day 16-17: Integration Testing

**Tasks:**
1. Test complete user flow (register → join dojo → start challenge → solve)
2. Test workspace services (code-server, desktop)
3. Test container CLI commands
4. Test multi-user scenarios
5. Load testing

**Test Scenarios:**
- [ ] User registration and login
- [ ] Starting multiple challenges
- [ ] Flag submission (web + CLI)
- [ ] Service switching (terminal → code → desktop)
- [ ] Home directory persistence
- [ ] SSH access
- [ ] Container resource limits
- [ ] Challenge switching speed
- [ ] Concurrent user load

### Day 18-19: Challenge Migration

**Tasks:**
1. Update challenge structure to match DOJO format
2. Rebuild all 10 challenge images with Nix workspace
3. Test each challenge individually
4. Update challenge metadata
5. Verify flag generation

**Challenge YAML Format:**
```yaml
# challenges/module01/challenge01.yml
id: challenge01
name: Introduction to Linux
description: Learn basic Linux commands
image: workspace:default
```

### Day 20-21: Deployment & Cutover

**Tasks:**
1. Create deployment documentation
2. Set up production docker-compose stack
3. Perform data migration from old system
4. Switch DNS/routing to new CTFd instance
5. Monitor for issues

**Cutover Checklist:**
- [ ] Database backup created
- [ ] User data migrated
- [ ] Challenge data migrated
- [ ] Solve history preserved
- [ ] Old system accessible for rollback
- [ ] Monitoring in place
- [ ] Support documentation updated

---

## Risk Mitigation

### Technical Risks

**Risk 1: Data Loss During Migration**
- **Mitigation:** Full database backups before each migration step
- **Rollback:** Keep old system running in parallel for 1 week

**Risk 2: Performance Regression**
- **Mitigation:** Load testing before cutover
- **Rollback:** DNS switch back to old system

**Risk 3: Plugin Incompatibility**
- **Mitigation:** Test with official dojo_plugin from pwncollege/dojo repo
- **Rollback:** Document all plugin modifications

**Risk 4: Nix Build Failures**
- **Mitigation:** Use official workspace flake from pwncollege/dojo
- **Rollback:** Fall back to Dockerfile-based builds

### Organizational Risks

**Risk 5: Extended Downtime**
- **Mitigation:** Parallel deployment, quick cutover
- **Timeline:** <30 minutes downtime for DNS switch

**Risk 6: User Confusion**
- **Mitigation:** Migration guide for users
- **Communication:** Email/announcement before cutover

---

## Comparison: Before & After

### Architecture

**Before (FastAPI):**
```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  Frontend   │────▶│   Backend    │────▶│  SQLite DB  │
│  (Vue.js)   │     │  (FastAPI)   │     └─────────────┘
└─────────────┘     └──────────────┘
                           │
                           ▼
                    ┌──────────────┐
                    │ Orchestrator │
                    │  (FastAPI)   │
                    └──────────────┘
                           │
                           ▼
                    ┌──────────────┐
                    │   Docker     │
                    │  Containers  │
                    └──────────────┘
```

**After (CTFd + dojo_plugin):**
```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│ dojo_theme  │────▶│     CTFd     │────▶│ PostgreSQL  │
│  Frontend   │     │   (Flask)    │     │     DB      │
└─────────────┘     └──────────────┘     └─────────────┘
                           │
                           ▼
                    ┌──────────────┐
                    │ dojo_plugin  │
                    │  (Integrated)│
                    └──────────────┘
                           │
                           ▼
                    ┌──────────────┐
                    │ Per-User     │
                    │ Containers   │
                    │ (Persistent) │
                    └──────────────┘
```

### Container Lifecycle

**Before:**
```
User starts challenge → New container created
User switches challenge → Old container destroyed, new container created
User home directory → Mounted per-container
```

**After:**
```
User starts challenge → Container created (if not exists) OR reused
User switches challenge → Same container, challenge files injected
User home directory → Always mounted to same container
```

### User Experience

**Before:**
- Terminal access only
- SSH on port 2222
- Basic toolset (~10 tools)
- Flag submission via web UI

**After:**
- Terminal + Code Editor + Desktop GUI
- SSH on port 22
- Comprehensive toolset (50+ tools)
- Flag submission via web UI + CLI

---

## Directory Structure After Migration

```
/workspaces/dojo/
├── ARCHITECTURE_COMPARISON.md       # This comparison doc
├── MIGRATION_PLAN_CTFD.md          # This migration plan
├── MIGRATION_COMPLETE.md           # Final report (after migration)
│
├── ctf-platform-legacy/            # OLD SYSTEM (archived)
│   ├── backend/
│   ├── frontend/
│   ├── orchestrator/
│   └── challenges/
│
└── ctfd-dojo/                      # NEW SYSTEM
    ├── docker-compose.yml
    ├── CTFd/                       # CTFd core (submodule)
    ├── dojo_plugin/               # Official plugin
    │   ├── api/
    │   ├── models.py
    │   ├── pages/
    │   └── utils/
    ├── dojo_theme/                # Custom UI theme
    ├── workspace/                 # Nix workspace definition
    │   ├── flake.nix
    │   ├── Dockerfile
    │   ├── core/
    │   ├── services/
    │   └── additional/
    ├── challenges/                # Challenge definitions
    │   ├── module01/
    │   ├── module02/
    │   └── ...
    ├── data/                      # Persistent data
    │   ├── CTFd/
    │   ├── homes/
    │   └── dojos/
    └── scripts/
        ├── migrate_to_ctfd.py    # Data migration
        └── deploy.sh             # Deployment script
```

---

## Success Criteria

The migration is considered successful when:

1. ✅ All current users can log in to CTFd
2. ✅ All 10 challenges are accessible and functional
3. ✅ Solve history is preserved
4. ✅ Terminal access works
5. ✅ SSH access works
6. ✅ Code-server (browser IDE) works
7. ✅ Desktop environment (noVNC) works
8. ✅ Container CLI (`dojo` command) works
9. ✅ Flag submission works (web + CLI)
10. ✅ Home directories persist across challenges
11. ✅ Performance is equal or better than old system
12. ✅ Resource usage is equal or lower than old system

---

## Rollback Plan

If critical issues arise:

**Immediate Rollback (<24 hours):**
1. Switch DNS back to old FastAPI system
2. Disable CTFd instance
3. Communicate issue to users

**Partial Rollback (24-72 hours):**
1. Identify specific broken functionality
2. Fix in CTFd implementation
3. Re-test and re-deploy

**Full Rollback (>72 hours):**
1. Restore old system permanently
2. Extract lessons learned
3. Plan alternative migration approach

---

## Next Steps

**Immediate Actions:**

1. **Create git branch:** Preserve current implementation
   ```bash
   git checkout -b legacy-fastapi-platform
   git push origin legacy-fastapi-platform
   ```

2. **Create parallel directory:** Don't overwrite current system
   ```bash
   mkdir ctfd-dojo
   cd ctfd-dojo
   ```

3. **Clone CTFd:** Get official CTFd 3.7.x
   ```bash
   git clone --branch 3.7.x https://github.com/CTFd/CTFd.git
   ```

4. **Clone dojo_plugin:** Get official pwncollege plugin
   ```bash
   git clone https://github.com/pwncollege/dojo.git pwncollege-reference
   ```

5. **Start Day 1 tasks:** CTFd base installation

---

## Estimated Effort Breakdown

| Phase | Days | Effort | Risk |
|-------|------|--------|------|
| Phase 1: Foundation | 5 days | High | Medium |
| Phase 2: Workspace | 5 days | Very High | High |
| Phase 3: Frontend/API | 5 days | High | Medium |
| Phase 4: Testing/Deploy | 6 days | Medium | High |
| **Total** | **21 days** | | |

**Assumes:** 1 full-time developer, 8 hours/day

---

## Questions Before Starting

1. **Confirmation:** Are you certain you want to replace the entire backend? Current system works.
2. **Timeline:** Is 3-4 weeks acceptable downtime for development?
3. **Data:** Do we need to preserve all user data, or can we start fresh?
4. **Resources:** Do we have staging environment for testing?
5. **Access:** Do we have official pwncollege/dojo repository access for reference?

**Please confirm before I proceed with Phase 1, Day 1 tasks.**
