JWT Migration Plan (No-DB, Redis-backed)

This document describes a focused plan to replace the legacy token system with JWT. No database schema changes. Redis is used for revocation and optional refresh sessions. No dual system during rollout; legacy will be removed.

Phase 0 — Preparation
- Dependencies
  - Ruby gem: jwt
  - Optional helpers: redis (Ruby client), rack-cors (if needed)
- Environment variables
  - JWT_ALG=HS256
  - JWT_SECRET (default: Rails.application.secret_key_base if unset)
  - JWT_ACCESS_TTL (seconds; e.g., 7200 for 2h or 172800 for 48h)
  - JWT_CLOCK_SKEW=60
  - REDIS_URL (already set in docker-compose)
- Dev note
  - Temporarily unlock Gemfile.lock to run bundle install, then re-lock

Phase 1 — Token Model (Stateless Access, Redis Revocation/Refresh)
- Access token (JWT)
  - alg: HS256
  - claims: sub (user UUID), email, role, iat, exp, jti (UUID)
- Revocation (logout/admin revoke)
  - Redis blacklist key: jwt:blacklist:<jti> → value 1, TTL = exp - iat
- Optional silent refresh (no DB)
  - Issue opaque refresh_token (UUID)
  - Redis session: jwt:refresh:<token> → { user_id, jti, exp } with TTL (e.g., 14d)
  - On refresh, rotate: delete old session, create new (new token values)

Phase 2 — Issuance & Verification
- Issue (POST /api/v1/auth/login)
  - Validate credentials
  - Build claims (sub, role, iat, exp, jti), sign JWT
  - Response: { success, message, data: { access_token, expires_in, user } }
  - If refresh enabled: include refresh_token
- Verify (middleware/concern)
  - Parse Authorization: Bearer <jwt>
  - JWT.decode with algorithm, secret, leeway (JWT_CLOCK_SKEW)
  - Ensure exp valid
  - Ensure jti not blacklisted in Redis
  - Load user by sub; set current_user
  - On failure: 401 (RFC 7807 problem+json)
- Logout (POST /api/v1/auth/logout)
  - Add jti to Redis blacklist with TTL=remaining lifetime
  - If refresh used: delete refresh session

Phase 3 — API Changes (Removal + Enforcement)
- Remove all legacy token generation/verification
- Add before_action :authenticate! to API controllers
- Keep role mapping minimal (user / moderator / admin)
- Ensure audio streaming endpoints require Bearer on each request (signed URLs optional later)

Phase 4 — Redis Integration
- Use existing REDIS_URL (Archive already connects via compose)
- Key namespaces
  - Blacklist: jwt:blacklist:<jti>
  - Refresh: jwt:refresh:<token>
- Persistence is not required across restarts per current requirements

Phase 5 — Security Defaults
- Access token TTL: start with 2h (or 48h to match current), adjust later
- Enforce HTTPS in production; configure CORS as needed
- Rate-limit login/refresh (rack-attack optional)
- Minimal claims; avoid unnecessary PII
- HS256 is fine (single-service). Consider RS256 and key rotation later

Phase 6 — Developer Workflow
- Update Gemfile; run bundle install; re-lock
- ENV fallbacks: use secret_key_base when JWT_SECRET missing
- Rake tasks (smoke tests)
  - jwt:issue[user_id] → prints token
  - jwt:verify[token] → prints claims/validity
  - jwt:blacklist[jti, ttl] → simulates logout

Phase 7 — Testing & Validation
- Unit tests
  - Issuance includes correct claims and TTL
  - Verification rejects tampered, expired, and blacklisted tokens
- Integration tests
  - Login → protected endpoint works
  - Logout → subsequent access fails
  - If refresh enabled → refresh yields new valid token; rotation enforced
- Manual checks
  - Curl Bearer auth to songs list and audio stream HEAD + Range

Phase 8 — Cutover
- Remove legacy token code
- Deploy JWT-only
- Monitor 401 rates and problem+json errors

Optional (Later)
- Refresh tokens endpoint: POST /api/v1/auth/refresh
- Signed URLs for streaming (CDN-ready)
- RS256 adoption and key rotation schedule

Implementation Sketches
- TokenService
  - issue_access_token(user_id:, email:, role:, ttl:) → { token, jti, exp }
  - verify(token) → { claims } or raise
  - blacklist!(jti, ttl_seconds)
  - (optional) issue_refresh_token(user_id:, jti:, ttl:) → { refresh_token }
  - (optional) rotate_refresh!(old_token) → { refresh_token }
- Controller/Concern
  - authenticate! parses Bearer, verifies token, sets current_user
  - On failure: 401 RFC 7807 JSON with title, status, detail
- Endpoints
  - POST /api/v1/auth/login → returns access token (+ optional refresh)
  - POST /api/v1/auth/logout → blacklists the presented JWT jti (+ deletes refresh if present)
  - GET /api/v1/auth/verify → verifies token and returns user context
  - (optional) POST /api/v1/auth/refresh → returns new access (+ rotated refresh)
- Error Responses (RFC 7807)
  - 401: Unauthorized (invalid/missing token)
  - 403: Forbidden (role/permission denied)
  - 422: Validation errors (for login payload)

This plan uses Redis for revocation and optional refresh sessions, requires no DB migrations, and fully replaces the legacy token system.

