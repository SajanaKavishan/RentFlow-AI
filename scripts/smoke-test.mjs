#!/usr/bin/env node
/**
 * RentFlow AI Smoke Test Runner
 * Validates:
 * 1. Agent /health
 * 2. Backend /liveness
 * 3. Backend /readiness
 * 4. Frontend static web app loading
 * 5. Auth login and protected endpoint (/api/auth/me)
 */

const backendUrl = (process.env.BACKEND_URL || '').replace(/\/+$/, '')
const frontendUrl = (process.env.FRONTEND_URL || '').replace(/\/+$/, '')
const agentUrl = (process.env.AGENT_URL || '').replace(/\/+$/, '')
const smokeEmail = process.env.SMOKE_TEST_EMAIL || ''
const smokePassword = process.env.SMOKE_TEST_PASSWORD || ''

if (!backendUrl) {
  console.error('❌ ERROR: BACKEND_URL environment variable is required.')
  process.exit(1)
}

let hasFailures = false

async function runCheck(name, fn) {
  process.stdout.write(`⏳ [CHECK] ${name}... `)
  try {
    const result = await fn()
    console.log(`✅ PASSED (${result || 'OK'})`)
  } catch (err) {
    hasFailures = true
    console.log(`❌ FAILED: ${err.message}`)
  }
}

async function main() {
  console.log('=====================================================')
  console.log('🚀 Running RentFlow AI Deployment Smoke Tests')
  console.log(`Backend URL:  ${backendUrl}`)
  console.log(`Frontend URL: ${frontendUrl || '(Not specified, skipping frontend check)'}`)
  console.log(`Agent URL:    ${agentUrl || '(Private VNet / internal ingress)'}`)
  console.log('=====================================================\n')

  // Check 1: Agent /health (if agentUrl provided and reachable)
  if (agentUrl) {
    await runCheck('FastAPI Agent /health probe', async () => {
      const res = await fetch(`${agentUrl}/health`, { signal: AbortSignal.timeout(10000) })
      if (!res.ok) throw new Error(`HTTP ${res.status} ${res.statusText}`)
      const body = await res.json()
      if (body.status !== 'healthy') throw new Error(`Unexpected status: ${JSON.stringify(body)}`)
      return `HTTP ${res.status}`
    })
  } else {
    console.log('ℹ️ [CHECK] FastAPI Agent /health: Skipped (Agent operates under internal VNet ingress; verified via backend readiness)\n')
  }

  // Check 2: Backend /liveness
  await runCheck('ASP.NET Core Backend /liveness', async () => {
    const res = await fetch(`${backendUrl}/liveness`, { signal: AbortSignal.timeout(10000) })
    if (!res.ok) throw new Error(`HTTP ${res.status} ${res.statusText}`)
    const body = await res.json()
    if (body.status !== 'ok') throw new Error(`Unexpected body: ${JSON.stringify(body)}`)
    return `HTTP ${res.status} - status: ok`
  })

  // Check 3: Backend /readiness (checks DB connectivity & configuration)
  await runCheck('ASP.NET Core Backend /readiness', async () => {
    const res = await fetch(`${backendUrl}/readiness`, { signal: AbortSignal.timeout(15000) })
    if (!res.ok) {
      let details = ''
      try { details = JSON.stringify(await res.json()) } catch {}
      throw new Error(`HTTP ${res.status} ${res.statusText} ${details}`)
    }
    const body = await res.json()
    if (body.status !== 'ready') throw new Error(`Unexpected status: ${JSON.stringify(body)}`)
    return `HTTP ${res.status} - database connected & configured`
  })

  // Check 4: Frontend loads
  if (frontendUrl) {
    await runCheck('React Frontend Static Web App Root', async () => {
      const res = await fetch(frontendUrl, { signal: AbortSignal.timeout(10000) })
      if (!res.ok) throw new Error(`HTTP ${res.status} ${res.statusText}`)
      const html = await res.text()
      if (!html.includes('<div id="root">') && !html.includes('<html')) {
        throw new Error('Response did not contain valid index.html SPA structure')
      }
      return `HTTP ${res.status}`
    })
  }

  // Check 5: Login and protected API endpoint (/api/auth/me)
  if (smokeEmail && smokePassword) {
    let authToken = null
    await runCheck('Authentication Login API (/api/auth/login)', async () => {
      const res = await fetch(`${backendUrl}/api/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: smokeEmail, password: smokePassword }),
        signal: AbortSignal.timeout(10000),
      })
      if (!res.ok) {
        let details = ''
        try { details = JSON.stringify(await res.json()) } catch {}
        throw new Error(`HTTP ${res.status} ${res.statusText} ${details}`)
      }
      const data = await res.json()
      authToken = data.token || data.accessToken
      if (!authToken) throw new Error('Response did not contain an auth token')
      return `HTTP 200 - Token received for user ${data.user?.email || smokeEmail}`
    })

    if (authToken) {
      await runCheck('Protected API Endpoint (/api/auth/me)', async () => {
        const res = await fetch(`${backendUrl}/api/auth/me`, {
          headers: { Authorization: `Bearer ${authToken}` },
          signal: AbortSignal.timeout(10000),
        })
        if (!res.ok) throw new Error(`HTTP ${res.status} ${res.statusText}`)
        const profile = await res.json()
        return `HTTP 200 - Authenticated as ${profile.email || profile.id}`
      })
    }
  } else {
    console.log('ℹ️ [CHECK] Auth Login & Protected API: Skipped (SMOKE_TEST_EMAIL or SMOKE_TEST_PASSWORD not provided)\n')
  }

  console.log('\n=====================================================')
  if (hasFailures) {
    console.error('❌ Smoke tests failed!')
    process.exit(1)
  } else {
    console.log('🎉 All deployment smoke checks completed successfully!')
    process.exit(0)
  }
}

main().catch((err) => {
  console.error('Fatal smoke test runner error:', err)
  process.exit(1)
})
