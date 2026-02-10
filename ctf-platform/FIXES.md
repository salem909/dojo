# Platform Fixes & Improvements

## Critical Fixes

### 1. Seccomp Profile Issues
- **Problem**: Containers failed to start with "Decoding seccomp profile failed" and tini fork errors
- **Root Cause**: Profile passed as file path instead of JSON content; `clone` syscall blocked
- **Fix**: Load JSON content and pass inline; removed `clone` from blocked syscalls
- **Files**: `orchestrator/app/docker_client.py`, `orchestrator/seccomp.json`

### 2. Hardcoded Paths
- **Problem**: SECCOMP_PROFILE_PATH used dev container absolute path `/workspaces/dojo/...`
- **Root Cause**: Non-portable configuration
- **Fix**: Changed to container-relative `/app/seccomp.json` with proper volume mount
- **Files**: `docker-compose.yml`, `orchestrator/app/config.py`

### 3. CORS Blocking Frontend
- **Problem**: Browser preflight OPTIONS requests returned 405 Method Not Allowed
- **Root Cause**: Missing CORS middleware
- **Fix**: Added `CORSMiddleware` with wildcard origins for dev
- **Files**: `backend/app/main.py`

### 4. Password Hashing Crash
- **Problem**: bcrypt backend version detection failed, fork errors
- **Root Cause**: Incompatibility between passlib and bcrypt library versions
- **Fix**: Switched to argon2 for password hashing
- **Files**: `backend/requirements.txt`, `backend/app/auth.py`

### 5. Hardcoded API URLs
- **Problem**: Frontend used `http://localhost:8000` and `ws://localhost:8000`
- **Root Cause**: Non-portable for remote deployments
- **Fix**: Dynamic URL construction based on `window.location`
- **Files**: `frontend/app.js`

### 6. WebSocket Stability
- **Problem**: Terminal proxy crashed on unexpected disconnects
- **Root Cause**: Missing exception handling in bidirectional relay
- **Fix**: Added try/catch and `return_exceptions=True` in gather
- **Files**: `backend/app/main.py`

### 7. Container Cleanup Robustness
- **Problem**: Stop instance failed if container already gone
- **Root Cause**: No defensive checks before stop/remove
- **Fix**: Added reload(), status check, force=True, exception handling
- **Files**: `orchestrator/app/docker_client.py`

### 8. SSH Configuration
- **Problem**: No explicit sshd config, potential security gaps
- **Root Cause**: Relying on Ubuntu defaults
- **Fix**: Created minimal sshd_config disabling password auth, enforcing pubkey only
- **Files**: `challenges/base/sshd_config`, `challenges/base/Dockerfile`

### 9. SSH Daemon Startup
- **Problem**: sshd started with `-D` (no-daemonize) but also backgrounded
- **Root Cause**: Conflicting flags
- **Fix**: Removed `-D` flag since backgrounding with `&`
- **Files**: `challenges/base/start.sh`

## Improvements

### Frontend Error Handling
- Added try/catch to `startInstance`, `stopInstance`, `saveKey`
- WebSocket error/close event handlers in terminal
- Check `readyState` before sending data

### Docker Compose
- Removed deprecated `version: "3.9"` field
- Fixed volume mount paths to be portable

### Code Quality
- Consistent error messages
- Graceful degradation on connection loss
- Better user feedback (alerts for failures)

## Testing Recommendations

1. Test SSH access after uploading public key
2. Verify browser terminal works with long-running commands
3. Confirm containers are cleaned up after stop
4. Test flag submission flow
5. Verify GC cleans up instances after MAX_RUNTIME_SECONDS
6. Test from non-localhost client to verify dynamic URLs work

## Known Limitations

- Frontend still uses port-in-URL (8000, 8080) - consider reverse proxy for production
- CORS set to wildcard - restrict to specific origins in production
- SQLite used - migrate to PostgreSQL for multi-node deployments
- No TLS/HTTPS - add reverse proxy with Let's Encrypt certificates
