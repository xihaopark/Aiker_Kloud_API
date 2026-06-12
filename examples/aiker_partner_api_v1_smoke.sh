#!/usr/bin/env bash
set -u

API_BASE="${AIKER_API_BASE:-https://aiker-kloud.web.app/api/v1}"
PORTAL_BASE="${AIKER_PORTAL_BASE:-https://aiker-kloud.web.app}"
PARTNER_KEY="${AIKER_PARTNER_API_KEY:-}"
KEEP_TENANT="${KEEP_TENANT:-0}"
RUN_EXTENSION_RUNTIME="${RUN_EXTENSION_RUNTIME:-0}"

if [[ -z "$PARTNER_KEY" ]]; then
  echo "ERROR: AIKER_PARTNER_API_KEY is required." >&2
  echo "Usage: AIKER_PARTNER_API_KEY='<key>' $0" >&2
  exit 2
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required." >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required." >&2
  exit 2
fi

RUN_ID="$(date +%s)"
TENANT_ID="kloud-smoke-${RUN_ID}"
TENANT_NAME="Kloud Smoke ${RUN_ID}"
EXTENSION_PRIMARY="101"
USER_EMAIL="kloud-smoke-${RUN_ID}@example.com"
TMP_DIR="$(mktemp -d)"
CREATED_TENANT=0
CLEANUP_DONE=0
PASSED=0
FAILED=0
CREATED_USER_ID=""
GENERATED_PASSWORD=""

cleanup_files() {
  rm -rf "$TMP_DIR"
}

cleanup_tenant() {
  if [[ "$CLEANUP_DONE" == "1" ]]; then
    return
  fi
  CLEANUP_DONE=1
  if [[ "$CREATED_TENANT" == "1" && "$KEEP_TENANT" != "1" ]]; then
    request DELETE "/tenants/${TENANT_ID}" "" "${TMP_DIR}/cleanup.json" >/dev/null
    if [[ "$HTTP_STATUS" == "204" ]]; then
      pass "Cleanup soft-delete smoke tenant" "HTTP ${HTTP_STATUS}"
    else
      fail "Cleanup soft-delete smoke tenant" "HTTP ${HTTP_STATUS}; response saved to ${TMP_DIR}/cleanup.json"
    fi
  elif [[ "$CREATED_TENANT" == "1" ]]; then
    echo "INFO: KEEP_TENANT=1 set; tenant kept for debugging: ${TENANT_ID}"
  fi
}

finish_cleanup() {
  cleanup_tenant
  cleanup_files
}

trap finish_cleanup EXIT

pass() {
  PASSED=$((PASSED + 1))
  echo "PASS $1${2:+: $2}"
}

fail() {
  FAILED=$((FAILED + 1))
  echo "FAIL $1${2:+: $2}"
}

request() {
  local method="$1"
  local path="$2"
  local payload="${3:-}"
  local out_file="$4"
  local url="${API_BASE}${path}"

  if [[ -n "$payload" ]]; then
    HTTP_STATUS="$(
      curl -sS -o "$out_file" -w "%{http_code}" \
        --path-as-is \
        -X "$method" "$url" \
        -H "Authorization: Bearer ${PARTNER_KEY}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        --data-binary "$payload"
    )"
  else
    HTTP_STATUS="$(
      curl -sS -o "$out_file" -w "%{http_code}" \
        --path-as-is \
        -X "$method" "$url" \
        -H "Authorization: Bearer ${PARTNER_KEY}" \
        -H "Accept: application/json"
    )"
  fi
}

enduser_request() {
  local method="$1"
  local path="$2"
  local payload="${3:-}"
  local out_file="$4"
  local url="${PORTAL_BASE}/api/enduser${path}"

  HTTP_STATUS="$(
    curl -sS -o "$out_file" -w "%{http_code}" \
      --path-as-is \
      -X "$method" "$url" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json" \
      --data-binary "$payload"
  )"
}

json_get() {
  local file="$1"
  local expr="$2"
  python3 - "$file" "$expr" <<'PY'
import json
import sys

path, expr = sys.argv[1], sys.argv[2]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    print("")
    sys.exit(0)

cur = data
for part in expr.split("."):
    if not part:
        continue
    if isinstance(cur, list):
        try:
            cur = cur[int(part)]
        except Exception:
            print("")
            sys.exit(0)
    elif isinstance(cur, dict):
        cur = cur.get(part)
    else:
        print("")
        sys.exit(0)

if cur is None:
    print("")
elif isinstance(cur, (dict, list)):
    print(json.dumps(cur, separators=(",", ":")))
else:
    print(cur)
PY
}

json_len() {
  local file="$1"
  python3 - "$file" <<'PY'
import json
import sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        data = json.load(f)
    print(len(data) if isinstance(data, list) else len(data.get("items", [])))
except Exception:
    print("0")
PY
}

url_query_param() {
  local value="$1"
  local name="$2"
  python3 - "$value" "$name" <<'PY'
import sys
from urllib.parse import parse_qs, urlparse

url, name = sys.argv[1], sys.argv[2]
print((parse_qs(urlparse(url).query).get(name) or [""])[0])
PY
}

assert_http() {
  local name="$1"
  local expected="$2"
  local response_file="$3"
  if [[ "$HTTP_STATUS" == "$expected" ]]; then
    pass "$name" "HTTP ${HTTP_STATUS}"
    return 0
  fi
  fail "$name" "expected HTTP ${expected}, got ${HTTP_STATUS}; response saved to ${response_file}"
  return 1
}

echo "Aiker Partner API v1 smoke"
echo "API base: ${API_BASE}"
echo "Portal base: ${PORTAL_BASE}"
echo "Tenant id: ${TENANT_ID}"
echo

AUTH_RESPONSE="${TMP_DIR}/auth.json"
request GET "/tenants/?page=1&page_size=5" "" "$AUTH_RESPONSE"
assert_http "Auth check: list tenants" "200" "$AUTH_RESPONSE"

CREATE_PAYLOAD="$(cat <<JSON
{
  "id": "${TENANT_ID}",
  "timezone": "America/Los_Angeles",
  "language": "en-US",
  "timezone_mode": "single",
  "company": {
    "name": "${TENANT_NAME}",
    "phone": "+12135550100",
    "address": "100 Sandbox Way, Los Angeles, CA"
  },
  "ai_settings": {
    "welcome_message": "Thank you for calling ${TENANT_NAME}. How may I help you?",
    "voice": "default",
    "speech_rate": "normal"
  },
  "feature_flags": {
    "qa": true,
    "booking": false,
    "products": false,
    "sms": false
  },
  "extensions": [
    {
      "agent_id": "frontdesk-${RUN_ID}",
      "extension_number": "${EXTENSION_PRIMARY}",
      "sip_domain": "sip.onesuite.example",
      "sip_username": "${EXTENSION_PRIMARY}",
      "sip_server": "core1-us-lax.myippbx.com",
      "sip_password": "example-sip-password-change-me",
      "skill": "receptionist_qa"
    }
  ],
  "contacts": [
    {
      "first_name": "Sales",
      "last_name": "Department",
      "extension": "${EXTENSION_PRIMARY}",
      "department": "Sales",
      "contact_type": "department",
      "supports_consultation_transfer": false,
      "can_receive_client_transfer": true,
      "can_receive_visitor_transfer": true
    }
  ],
  "kbqa": [
    {
      "question": "What are your business hours?",
      "answer": "We are open Monday through Friday, 9 AM to 5 PM Pacific time."
    }
  ],
  "locations": [],
  "appointments": []
}
JSON
)"

CREATE_RESPONSE="${TMP_DIR}/tenant_create.json"
request POST "/tenants" "$CREATE_PAYLOAD" "$CREATE_RESPONSE"
if assert_http "Create tenant with permissions, SIP extension, contact, and Q&A" "201" "$CREATE_RESPONSE"; then
  CREATED_TENANT=1
fi

TENANT_RESPONSE="${TMP_DIR}/tenant_get.json"
request GET "/tenants/${TENANT_ID}" "" "$TENANT_RESPONSE"
if assert_http "Read tenant detail" "200" "$TENANT_RESPONSE"; then
  TENANT_STATUS="$(json_get "$TENANT_RESPONSE" "status")"
  QA_FLAG="$(json_get "$TENANT_RESPONSE" "feature_flags.qa")"
  if [[ "$TENANT_STATUS" == "active" && "$QA_FLAG" == "True" || "$TENANT_STATUS" == "active" && "$QA_FLAG" == "true" ]]; then
    pass "Verify tenant status active and qa feature enabled"
  else
    fail "Verify tenant status active and qa feature enabled" "status=${TENANT_STATUS}, qa=${QA_FLAG}"
  fi
fi

EXT_LIST_RESPONSE="${TMP_DIR}/extensions_list.json"
request GET "/tenants/${TENANT_ID}/extensions" "" "$EXT_LIST_RESPONSE"
if assert_http "List SIP extensions" "200" "$EXT_LIST_RESPONSE"; then
  EXT_COUNT="$(json_len "$EXT_LIST_RESPONSE")"
  [[ "$EXT_COUNT" -ge 1 ]] && pass "Verify extension list contains data" "count=${EXT_COUNT}" || fail "Verify extension list contains data" "count=${EXT_COUNT}"
  LISTED_SIP_USERNAME="$(json_get "$EXT_LIST_RESPONSE" "0.sip_username")"
  [[ "$LISTED_SIP_USERNAME" == "$EXTENSION_PRIMARY" ]] && pass "Verify extension sip_username returned" "sip_username=${LISTED_SIP_USERNAME}" || fail "Verify extension sip_username returned" "sip_username=${LISTED_SIP_USERNAME}"
fi

EXT_STATUS_RESPONSE="${TMP_DIR}/extension_runtime_status.json"
request GET "/tenants/${TENANT_ID}/extensions/${EXTENSION_PRIMARY}/runtime/status" "" "$EXT_STATUS_RESPONSE"
if assert_http "Read extension runtime status" "200" "$EXT_STATUS_RESPONSE"; then
  RUNTIME_STATE="$(json_get "$EXT_STATUS_RESPONSE" "state")"
  [[ -n "$RUNTIME_STATE" ]] && pass "Verify runtime status has state" "state=${RUNTIME_STATE}" || fail "Verify runtime status has state"
fi

if [[ "$RUN_EXTENSION_RUNTIME" == "1" ]]; then
  EXT_START_RESPONSE="${TMP_DIR}/extension_runtime_start.json"
  request POST "/tenants/${TENANT_ID}/extensions/${EXTENSION_PRIMARY}/runtime/start" "" "$EXT_START_RESPONSE"
  assert_http "Start extension runtime" "200" "$EXT_START_RESPONSE"

  EXT_STOP_RESPONSE="${TMP_DIR}/extension_runtime_stop.json"
  request POST "/tenants/${TENANT_ID}/extensions/${EXTENSION_PRIMARY}/runtime/stop" "" "$EXT_STOP_RESPONSE"
  assert_http "Stop extension runtime" "200" "$EXT_STOP_RESPONSE"
else
  echo "INFO: Skipping extension runtime start/stop. Set RUN_EXTENSION_RUNTIME=1 to exercise those endpoints."
fi

EXT_UPDATE_PAYLOAD="$(cat <<JSON
{
  "agent_id": "frontdesk-${RUN_ID}",
  "extension_number": "${EXTENSION_PRIMARY}",
  "sip_domain": "sip.onesuite.example",
  "sip_username": "${EXTENSION_PRIMARY}",
  "sip_server": "core1-us-lax-edited.myippbx.com",
  "sip_password": "example-sip-password-change-me",
  "skill": "receptionist_only"
}
JSON
)"

EXT_UPDATE_RESPONSE="${TMP_DIR}/extension_update.json"
request PUT "/tenants/${TENANT_ID}/extensions/${EXTENSION_PRIMARY}" "$EXT_UPDATE_PAYLOAD" "$EXT_UPDATE_RESPONSE"
if assert_http "Update SIP extension skill to receptionist_only" "200" "$EXT_UPDATE_RESPONSE"; then
  UPDATED_SKILL="$(json_get "$EXT_UPDATE_RESPONSE" "skill")"
  [[ "$UPDATED_SKILL" == "receptionist_only" ]] && pass "Verify updated extension skill" || fail "Verify updated extension skill" "skill=${UPDATED_SKILL}"
fi

USER_CREATE_PAYLOAD="$(cat <<JSON
{
  "email": "${USER_EMAIL}",
  "role": "user",
  "display_name": "Kloud Smoke User",
  "seat_limit": 1,
  "extension_limit": 3
}
JSON
)"

USER_CREATE_RESPONSE="${TMP_DIR}/user_create.json"
request POST "/tenants/${TENANT_ID}/users" "$USER_CREATE_PAYLOAD" "$USER_CREATE_RESPONSE"
if assert_http "Create portal user with one-time password" "201" "$USER_CREATE_RESPONSE"; then
  CREATED_USER_ID="$(json_get "$USER_CREATE_RESPONSE" "user_id")"
  GENERATED_PASSWORD="$(json_get "$USER_CREATE_RESPONSE" "plaintext_password")"
  if [[ -n "$CREATED_USER_ID" && -n "$GENERATED_PASSWORD" ]]; then
    pass "Verify user id and generated password returned" "password hidden"
  else
    fail "Verify user id and generated password returned"
  fi
fi

USER_LIST_RESPONSE="${TMP_DIR}/users_list.json"
request GET "/tenants/${TENANT_ID}/users" "" "$USER_LIST_RESPONSE"
if assert_http "List tenant users" "200" "$USER_LIST_RESPONSE"; then
  USER_COUNT="$(json_len "$USER_LIST_RESPONSE")"
  [[ "$USER_COUNT" -ge 1 ]] && pass "Verify user list contains data" "count=${USER_COUNT}" || fail "Verify user list contains data" "count=${USER_COUNT}"
fi

if [[ -n "$CREATED_USER_ID" ]]; then
  USER_UPDATE_RESPONSE="${TMP_DIR}/user_update.json"
  request PATCH "/tenants/${TENANT_ID}/users/${CREATED_USER_ID}" '{"seat_limit":2,"extension_limit":4}' "$USER_UPDATE_RESPONSE"
  if assert_http "Update tenant user seat and extension limits" "200" "$USER_UPDATE_RESPONSE"; then
    SEAT_LIMIT="$(json_get "$USER_UPDATE_RESPONSE" "seat_limit")"
    EXT_LIMIT="$(json_get "$USER_UPDATE_RESPONSE" "extension_limit")"
    [[ "$SEAT_LIMIT" == "2" && "$EXT_LIMIT" == "4" ]] && pass "Verify user limits updated" || fail "Verify user limits updated" "seat=${SEAT_LIMIT}, extension=${EXT_LIMIT}"
  fi
else
  fail "Update tenant user seat and extension limits" "skipped because user creation did not return user_id"
fi

LOGIN_LINK_PAYLOAD="$(cat <<JSON
{
  "tenant_id": "${TENANT_ID}",
  "user": {
    "email": "${USER_EMAIL}",
    "name": "Kloud Smoke User"
  },
  "role": "user",
  "redirect_path": "/app/extensions"
}
JSON
)"

LOGIN_LINK_RESPONSE="${TMP_DIR}/login_link.json"
request POST "/sso/login-links" "$LOGIN_LINK_PAYLOAD" "$LOGIN_LINK_RESPONSE"
LOGIN_TOKEN=""
if assert_http "Create one-time automatic login link" "201" "$LOGIN_LINK_RESPONSE"; then
  LOGIN_URL="$(json_get "$LOGIN_LINK_RESPONSE" "login_url")"
  EXPIRES_IN="$(json_get "$LOGIN_LINK_RESPONSE" "expires_in_seconds")"
  LOGIN_TOKEN="$(url_query_param "$LOGIN_URL" "token")"
  if [[ -n "$LOGIN_TOKEN" && "$EXPIRES_IN" == "300" ]]; then
    pass "Verify login link contains hidden one-time token" "token hidden"
  else
    fail "Verify login link contains hidden one-time token" "expires_in=${EXPIRES_IN}"
  fi
fi

if [[ -n "$LOGIN_TOKEN" ]]; then
  LOGIN_EXCHANGE_RESPONSE="${TMP_DIR}/login_exchange.json"
  enduser_request POST "/partner-sso/exchange" "{\"token\":\"${LOGIN_TOKEN}\"}" "$LOGIN_EXCHANGE_RESPONSE"
  if assert_http "Exchange automatic login token for end-user session" "200" "$LOGIN_EXCHANGE_RESPONSE"; then
    SESSION_TOKEN="$(json_get "$LOGIN_EXCHANGE_RESPONSE" "token")"
    REDIRECT_PATH="$(json_get "$LOGIN_EXCHANGE_RESPONSE" "redirect_path")"
    [[ -n "$SESSION_TOKEN" && "$REDIRECT_PATH" == "/app/extensions" ]] && pass "Verify session returned and redirect path preserved" "session token hidden" || fail "Verify session returned and redirect path preserved" "redirect=${REDIRECT_PATH}"
  fi

  LOGIN_REUSE_RESPONSE="${TMP_DIR}/login_reuse.json"
  enduser_request POST "/partner-sso/exchange" "{\"token\":\"${LOGIN_TOKEN}\"}" "$LOGIN_REUSE_RESPONSE"
  [[ "$HTTP_STATUS" == "401" ]] && pass "Reject reused automatic login token" "HTTP ${HTTP_STATUS}" || fail "Reject reused automatic login token" "HTTP ${HTTP_STATUS}; response saved to ${LOGIN_REUSE_RESPONSE}"
fi

SUSPEND_LINK_RESPONSE="${TMP_DIR}/suspend_login_link.json"
request POST "/sso/login-links" "$LOGIN_LINK_PAYLOAD" "$SUSPEND_LINK_RESPONSE"
SUSPEND_LOGIN_TOKEN=""
if assert_http "Create login link before suspend check" "201" "$SUSPEND_LINK_RESPONSE"; then
  SUSPEND_LOGIN_URL="$(json_get "$SUSPEND_LINK_RESPONSE" "login_url")"
  SUSPEND_LOGIN_TOKEN="$(url_query_param "$SUSPEND_LOGIN_URL" "token")"
fi

BATCH_EXT_PAYLOAD="$(cat <<JSON
{
  "items": [
    {
      "agent_id": "batch-sales-${RUN_ID}",
      "extension_number": "201",
      "sip_domain": "sip.onesuite.example",
      "sip_username": "201",
      "sip_server": "core1-us-lax.myippbx.com",
      "sip_password": "example-sip-password-change-me",
      "skill": "receptionist_only"
    },
    {
      "agent_id": "batch-support-${RUN_ID}",
      "extension_number": "202",
      "sip_domain": "sip.onesuite.example",
      "sip_username": "202",
      "sip_server": "core1-us-lax.myippbx.com",
      "sip_password": "example-sip-password-change-me",
      "skill": "qa_only"
    },
    {
      "agent_id": "batch-invalid-${RUN_ID}",
      "extension_number": "203",
      "sip_domain": "sip.onesuite.example",
      "sip_username": "203",
      "sip_server": "core1-us-lax.myippbx.com",
      "sip_password": "example-sip-password-change-me",
      "skill": "appointment_scheduler"
    }
  ]
}
JSON
)"

BATCH_EXT_RESPONSE="${TMP_DIR}/batch_extensions.json"
request POST "/tenants/${TENANT_ID}/extensions:batch" "$BATCH_EXT_PAYLOAD" "$BATCH_EXT_RESPONSE"
if assert_http "Batch import extensions with partial success example" "200" "$BATCH_EXT_RESPONSE"; then
  OK_COUNT="$(json_get "$BATCH_EXT_RESPONSE" "ok")"
  FAILED_COUNT="$(json_get "$BATCH_EXT_RESPONSE" "failed")"
  [[ "$OK_COUNT" == "2" && "$FAILED_COUNT" == "1" ]] && pass "Verify extension batch partial success" "ok=${OK_COUNT}, failed=${FAILED_COUNT}" || fail "Verify extension batch partial success" "ok=${OK_COUNT}, failed=${FAILED_COUNT}"
fi

BATCH_CONTACTS_PAYLOAD="$(cat <<JSON
{
  "items": [
    {
      "first_name": "Sales",
      "last_name": "Team",
      "extension": "201",
      "department": "Sales",
      "contact_type": "department",
      "supports_consultation_transfer": false,
      "can_receive_client_transfer": true,
      "can_receive_visitor_transfer": true
    },
    {
      "first_name": "Support",
      "last_name": "Team",
      "extension": "202",
      "department": "Support",
      "contact_type": "department",
      "supports_consultation_transfer": true,
      "can_receive_client_transfer": true,
      "can_receive_visitor_transfer": true
    }
  ]
}
JSON
)"

BATCH_CONTACTS_RESPONSE="${TMP_DIR}/batch_contacts.json"
request POST "/tenants/${TENANT_ID}/contacts:batch" "$BATCH_CONTACTS_PAYLOAD" "$BATCH_CONTACTS_RESPONSE"
if assert_http "Batch import contacts" "200" "$BATCH_CONTACTS_RESPONSE"; then
  OK_COUNT="$(json_get "$BATCH_CONTACTS_RESPONSE" "ok")"
  [[ "$OK_COUNT" == "2" ]] && pass "Verify contacts batch success" "ok=${OK_COUNT}" || fail "Verify contacts batch success" "ok=${OK_COUNT}"
fi

BATCH_KBQA_PAYLOAD="$(cat <<JSON
{
  "items": [
    {
      "question": "What are your business hours?",
      "answer": "We are open Monday through Friday, 9 AM to 5 PM Pacific time."
    },
    {
      "question": "How do I reach support?",
      "answer": "Please contact the Support Department and provide your account details."
    }
  ]
}
JSON
)"

BATCH_KBQA_RESPONSE="${TMP_DIR}/batch_kbqa.json"
request POST "/tenants/${TENANT_ID}/kbqa:batch" "$BATCH_KBQA_PAYLOAD" "$BATCH_KBQA_RESPONSE"
if assert_http "Batch import Q&A" "200" "$BATCH_KBQA_RESPONSE"; then
  OK_COUNT="$(json_get "$BATCH_KBQA_RESPONSE" "ok")"
  [[ "$OK_COUNT" == "2" ]] && pass "Verify Q&A batch success" "ok=${OK_COUNT}" || fail "Verify Q&A batch success" "ok=${OK_COUNT}"
fi

SUSPEND_RESPONSE="${TMP_DIR}/suspend.json"
request PATCH "/tenants/${TENANT_ID}/status" '{"status":"suspended","reason":"Partner API v1 smoke test"}' "$SUSPEND_RESPONSE"
assert_http "Suspend tenant" "200" "$SUSPEND_RESPONSE"

SUSPENDED_DETAIL_RESPONSE="${TMP_DIR}/tenant_suspended_get.json"
request GET "/tenants/${TENANT_ID}" "" "$SUSPENDED_DETAIL_RESPONSE"
if assert_http "Read suspended tenant detail" "200" "$SUSPENDED_DETAIL_RESPONSE"; then
  TENANT_STATUS="$(json_get "$SUSPENDED_DETAIL_RESPONSE" "status")"
  [[ "$TENANT_STATUS" == "suspended" ]] && pass "Verify tenant status suspended" || fail "Verify tenant status suspended" "status=${TENANT_STATUS}"
fi

if [[ -n "$SUSPEND_LOGIN_TOKEN" ]]; then
  SUSPENDED_EXCHANGE_RESPONSE="${TMP_DIR}/suspended_exchange.json"
  enduser_request POST "/partner-sso/exchange" "{\"token\":\"${SUSPEND_LOGIN_TOKEN}\"}" "$SUSPENDED_EXCHANGE_RESPONSE"
  [[ "$HTTP_STATUS" == "403" ]] && pass "Reject automatic login for suspended tenant" "HTTP ${HTTP_STATUS}" || fail "Reject automatic login for suspended tenant" "HTTP ${HTTP_STATUS}; response saved to ${SUSPENDED_EXCHANGE_RESPONSE}"
fi

UNSUSPEND_RESPONSE="${TMP_DIR}/unsuspend.json"
request PATCH "/tenants/${TENANT_ID}/status" '{"status":"active","reason":"Partner API v1 smoke test complete"}' "$UNSUSPEND_RESPONSE"
assert_http "Unsuspend tenant" "200" "$UNSUSPEND_RESPONSE"

cleanup_tenant

echo
echo "SUMMARY"
echo "Tenant: ${TENANT_ID}"
echo "User email: ${USER_EMAIL}"
echo "Portal login URL: ${PORTAL_BASE}/login"
echo "Passed: ${PASSED}"
echo "Failed: ${FAILED}"
if [[ "$KEEP_TENANT" == "1" ]]; then
  echo "Cleanup: skipped by KEEP_TENANT=1"
elif [[ "$CLEANUP_DONE" == "1" ]]; then
  echo "Cleanup: completed"
else
  echo "Cleanup: scheduled on exit"
fi

if [[ "$FAILED" -gt 0 ]]; then
  echo "Some checks failed. Response files were stored temporarily during execution and are removed on exit unless the script is interrupted."
  exit 1
fi
