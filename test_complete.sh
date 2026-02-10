#!/bin/bash
set -e

echo "=== Full Platform Test ==="
echo ""

# Clean up old test user
echo "0. Cleaning database..."
docker exec ctf-platform-backend-1 rm -f /app/backend.db 2>/dev/null || true

# Wait for services
echo "Waiting for services to be ready..."
sleep 3

# Register
echo ""
echo "1. Registering new user..."
REGISTER_RESP=$(curl -s -X POST http://localhost:8000/api/register \
  -H "Content-Type: application/json" \
  -d '{"username":"student1","password":"password123"}')
echo "✓ Registered"

TOKEN=$(echo $REGISTER_RESP | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
if [ -z "$TOKEN" ]; then
  echo "❌ ERROR: No token received"
  exit 1
fi

# Start instance
echo ""
echo "2. Starting challenge01 instance..."
START_RESP=$(curl -s -X POST http://localhost:8000/api/instances/start \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"challenge_id":"challenge01"}')
echo "$START_RESP"

INSTANCE_ID=$(echo $START_RESP | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
SSH_PORT=$(echo $START_RESP | grep -o '"ssh_port":[0-9]*' | cut -d':' -f2)

if [ -z "$INSTANCE_ID" ]; then
  echo "❌ ERROR: No instance ID received"
  exit 1
fi

echo "✓ Instance created: $INSTANCE_ID"
echo "✓ SSH port: ${SSH_PORT:-[not mapped yet]}"

# Wait for container to start
echo ""
echo "3. Waiting for container to be ready..."
sleep 2

# Check docker
echo ""
echo "4. Checking Docker container..."
docker ps --filter "label=ctf.instance_id=$INSTANCE_ID" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Test container exec (terminal simulation)
echo ""
echo "5. Testing terminal connection (exec into container)..."
CONTAINER_NAME=$(docker ps --filter "label=ctf.instance_id=$INSTANCE_ID" --format "{{.Names}}" | head -1)
if [ -z "$CONTAINER_NAME" ]; then
  echo "❌ ERROR: Container not found"
  exit 1
fi

echo "Container: $CONTAINER_NAME"
echo "Testing bash command..."
docker exec -u ctf "$CONTAINER_NAME" bash -c "echo 'Hello from container!' && cat /challenge/instructions.txt | head -3"

# Test if SSH port is mapped
if [ -n "$SSH_PORT" ] && [ "$SSH_PORT" != "null" ]; then
  echo ""
  echo "6. Testing SSH port (netstat on host)..."
  netstat -tln | grep ":$SSH_PORT" || echo "SSH port not listening yet (may take a moment)"
fi

echo ""
echo "7. Instance Details for UI Testing:"
echo "   - Instance ID: $INSTANCE_ID"
echo "   - Token: ${TOKEN:0:30}..."
echo "   - Browser Terminal URL: http://localhost:8080/terminal.html?instance=$INSTANCE_ID"
echo ""
echo "✅ Test Complete!"
echo ""
echo "You can now:"
echo "  1. Open http://localhost:8080 in your browser"
echo "  2. Login as student1/password123"
echo "  3. Click 'Browser Terminal' on the instance"
