#!/usr/bin/env bash
set -euo pipefail

BACKEND_URL="${BACKEND_URL:-}"
FRONTEND_URL="${FRONTEND_URL:-}"
AGENT_URL="${AGENT_URL:-}"
SMOKE_TEST_EMAIL="${SMOKE_TEST_EMAIL:-}"
SMOKE_TEST_PASSWORD="${SMOKE_TEST_PASSWORD:-}"

if [ -z "$BACKEND_URL" ]; then
  echo "❌ ERROR: BACKEND_URL environment variable is required."
  exit 1
fi

echo "====================================================="
echo "🚀 Running RentFlow AI Deployment Smoke Tests"
echo "Backend URL:  $BACKEND_URL"
echo "Frontend URL: ${FRONTEND_URL:-(Skipped)}"
echo "Agent URL:    ${AGENT_URL:-(Internal VNet)}"
echo "====================================================="

# 1. Agent /health (if accessible)
if [ -n "$AGENT_URL" ]; then
  echo -n "⏳ [CHECK] FastAPI Agent /health... "
  AGENT_STATUS=$(curl -fsSL --max-time 10 "$AGENT_URL/health" || true)
  if echo "$AGENT_STATUS" | grep -q "healthy"; then
    echo "✅ PASSED"
  else
    echo "❌ FAILED: $AGENT_STATUS"
    exit 1
  fi
fi

# 2. Backend /liveness
echo -n "⏳ [CHECK] ASP.NET Core Backend /liveness... "
LIVENESS_STATUS=$(curl -fsSL --max-time 10 "$BACKEND_URL/liveness")
if echo "$LIVENESS_STATUS" | grep -q '"status":"ok"'; then
  echo "✅ PASSED"
else
  echo "❌ FAILED: $LIVENESS_STATUS"
  exit 1
fi

# 3. Backend /readiness
echo -n "⏳ [CHECK] ASP.NET Core Backend /readiness... "
READINESS_STATUS=$(curl -fsSL --max-time 15 "$BACKEND_URL/readiness")
if echo "$READINESS_STATUS" | grep -q '"status":"ready"'; then
  echo "✅ PASSED"
else
  echo "❌ FAILED: $READINESS_STATUS"
  exit 1
fi

# 4. Frontend loads
if [ -n "$FRONTEND_URL" ]; then
  echo -n "⏳ [CHECK] React Frontend Static Web App... "
  FRONTEND_HTML=$(curl -fsSL --max-time 10 "$FRONTEND_URL")
  if echo "$FRONTEND_HTML" | grep -q 'id="root"'; then
    echo "✅ PASSED"
  else
    echo "❌ FAILED: Frontend HTML does not contain root mount element"
    exit 1
  fi
fi

# 5. Auth Login and Protected Endpoint
if [ -n "$SMOKE_TEST_EMAIL" ] && [ -n "$SMOKE_TEST_PASSWORD" ]; then
  echo -n "⏳ [CHECK] Login API (/api/auth/login)... "
  LOGIN_PAYLOAD=$(printf '{"email":"%s","password":"%s"}' "$SMOKE_TEST_EMAIL" "$SMOKE_TEST_PASSWORD")
  LOGIN_RESP=$(curl -fsSL --max-time 10 -H "Content-Type: application/json" -d "$LOGIN_PAYLOAD" "$BACKEND_URL/api/auth/login")
  TOKEN=$(echo "$LOGIN_RESP" | grep -o '"token":"[^"]*' | cut -d'"' -f4 || echo "$LOGIN_RESP" | grep -o '"accessToken":"[^"]*' | cut -d'"' -f4)
  if [ -n "$TOKEN" ]; then
    echo "✅ PASSED"
    echo -n "⏳ [CHECK] Protected API (/api/auth/me)... "
    ME_RESP=$(curl -fsSL --max-time 10 -H "Authorization: Bearer $TOKEN" "$BACKEND_URL/api/auth/me")
    if echo "$ME_RESP" | grep -q '"email"'; then
      echo "✅ PASSED"
    else
      echo "❌ FAILED: Protected endpoint response invalid"
      exit 1
    fi
  else
    echo "❌ FAILED: Could not extract auth token from login response"
    exit 1
  fi
fi

echo "====================================================="
echo "🎉 All deployment smoke checks completed successfully!"
