#!/bin/bash

echo "=== Testing CTF Platform Flow ==="

# Register
echo "1. Registering user..."
REGISTER_RESP=$(curl -s -X POST http://localhost:8000/api/register \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","password":"testpass"}')
echo "Response: $REGISTER_RESP"

TOKEN=$(echo $REGISTER_RESP | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
if [ -z "$TOKEN" ]; then
  echo "ERROR: No token received"
  exit 1
fi
echo "Token: ${TOKEN:0:20}..."

# Get challenges
echo ""
echo "2. Getting challenges..."
CHALLENGES=$(curl -s -X GET http://localhost:8000/api/challenges \
  -H "Authorization: Bearer $TOKEN")
echo "Challenges: $CHALLENGES"

# Start instance
echo ""
echo "3. Starting challenge01 instance..."
START_RESP=$(curl -s -X POST http://localhost:8000/api/instances/start \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"challenge_id":"challenge01"}')
echo "Start response: $START_RESP"

# List instances
echo ""
echo "4. Listing instances..."
INSTANCES=$(curl -s -X GET http://localhost:8000/api/instances \
  -H "Authorization: Bearer $TOKEN")
echo "Instances: $INSTANCES"

# Check docker containers
echo ""
echo "5. Checking Docker containers..."
docker ps --filter "label=ctf.instance_id" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "=== Test Complete ==="
