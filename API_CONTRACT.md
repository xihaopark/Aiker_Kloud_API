# Aiker Partner API Contract

Version: v1

Base path:

```text
https://aiker-kloud.web.app/api/v1
```

The external product delivery described here is **Aiker Partner API v1**.

Authentication:

```http
Authorization: Bearer <partner_api_key>
```

All endpoints are partner-scoped. A partner can only access tenants that were
created for that partner. If a tenant does not exist or belongs to a different
partner, the API returns `404`.

## Common Error Shape

```json
{
  "error": {
    "code": "validation_error",
    "message": "Human-readable message",
    "details": [
      { "field": "field_name", "message": "What is wrong" }
    ]
  }
}
```

Common status codes:

| Code | Meaning |
|---|---|
| `400` | Invalid request |
| `401` | Missing or invalid API key |
| `403` | Authenticated but not allowed |
| `404` | Resource not found or not owned by this partner |
| `409` | Conflict, such as duplicate tenant ID or email |
| `422` | Validation error |
| `500` | Internal server error |

## Feature Flags

Core features are always enabled:

```text
company_info, extensions, contacts, call_history, callback, voicemail
```

Optional features can be enabled per tenant:

```text
sms, qa, booking, products
```

For partner-created tenants, optional features default to disabled unless
provided in `feature_flags`.

Example:

```json
{
  "feature_flags": {
    "qa": true,
    "booking": false,
    "products": false,
    "sms": false
  }
}
```

Unknown feature codes return `422`.

## Tenant Status

| Status | Meaning |
|---|---|
| `active` | Normal operation |
| `suspended` | Portal login blocked; backend extension start/restart blocked |
| `pending` | Reserved for internal Aiker review; partners cannot set it |

Partners may set only `active` or `suspended`.

## Tenant Endpoints

### Create Tenant

```http
POST /api/v1/tenants
Content-Type: application/json
Authorization: Bearer <partner_api_key>
```

Request:

```json
{
  "id": "optional-client-suggested-id",
  "timezone": "America/Los_Angeles",
  "language": "en-US",
  "timezone_mode": "single",
  "company": {
    "name": "Example Company",
    "phone": "+12135550100",
    "address": "123 Main St"
  },
  "ai_settings": {
    "welcome_message": "Thank you for calling Example Company.",
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
      "agent_id": "frontdesk",
      "extension_number": "101",
      "sip_domain": "example.sip.domain",
      "sip_username": "101",
      "sip_server": "core1-us-lax.myippbx.com",
      "sip_password": "secret",
      "skill": "receptionist_qa"
    }
  ],
  "contacts": [],
  "kbqa": [],
  "locations": [],
  "appointments": []
}
```

Notes:

- `extensions` must contain at least one item.
- If `id` is omitted, Aiker generates the tenant ID.
- If a suggested `id` already exists for this partner, the API returns `409`.

Response: `201` with the full tenant detail object.

### List Tenants

```http
GET /api/v1/tenants/?page=1&page_size=50&q=example
Authorization: Bearer <partner_api_key>
```

Response:

```json
{
  "items": [
    {
      "id": "tenant-id",
      "tenant_id": "tenant-id",
      "status": "active",
      "feature_flags": { "qa": true, "booking": false },
      "timezone": "America/Los_Angeles",
      "language": "en-US",
      "timezone_mode": "single",
      "company": {
        "name": "Example Company",
        "address": "123 Main St",
        "phone": "+12135550100"
      },
      "extension_count": 1,
      "created_at": "2026-06-11T00:00:00",
      "updated_at": "2026-06-11T00:00:00"
    }
  ],
  "page": 1,
  "page_size": 50,
  "total": 1
}
```

### Get Tenant

```http
GET /api/v1/tenants/{tenant_id}
Authorization: Bearer <partner_api_key>
```

Response includes company, AI settings, locations, contacts, appointments,
Q&A rows, extensions, `status`, and `feature_flags`.

### Replace Tenant

```http
PUT /api/v1/tenants/{tenant_id}
Content-Type: application/json
Authorization: Bearer <partner_api_key>
```

Uses the same payload shape as Create Tenant.

Behavior:

- Replaces mutable tenant fields atomically.
- Replaces nested contacts, Q&A, appointments, locations, and extensions.
- If `feature_flags` is provided, it replaces the existing optional feature map.
- If `feature_flags` is omitted, existing feature flags are preserved.

Response: `200` with updated tenant detail.

### Delete Tenant

```http
DELETE /api/v1/tenants/{tenant_id}
Authorization: Bearer <partner_api_key>
```

Soft-deletes / deactivates the tenant. Data is preserved.

Response: `204`.

### Update Tenant Status

```http
PATCH /api/v1/tenants/{tenant_id}/status
Content-Type: application/json
Authorization: Bearer <partner_api_key>
```

Request:

```json
{
  "status": "suspended",
  "reason": "Optional human-readable reason"
}
```

Valid partner-set values: `active`, `suspended`.

Response:

```json
{
  "tenant_id": "tenant-id",
  "status": "suspended",
  "previous_status": "active"
}
```

## Extension Endpoints

Extension object:

```json
{
  "agent_id": "frontdesk",
  "extension_number": "101",
  "sip_domain": "example.sip.domain",
  "sip_username": "101",
  "sip_server": "core1-us-lax.myippbx.com",
  "sip_password": "secret",
  "skill": "receptionist_qa"
}
```

`sip_username` is the SIP registration username required by the voice runtime.
For OneSuite tenants this may be the same value as the extension number, but it
must still be sent explicitly.

`sip_password` is accepted only through this trusted server-to-server Partner
API. The Aiker end-user portal does not reveal, export, or import SIP passwords.
Admin users can manage SIP passwords in the Aiker admin portal.

Creating or updating an extension only saves configuration. It does not start
the runtime. Use the runtime endpoints below when OSB wants an extension to go
online or offline.

Supported `skill` values:

| Skill | Meaning |
|---|---|
| `receptionist_only` | Transfer / receptionist behavior only |
| `qa_only` | Q&A behavior only |
| `receptionist_qa` | Receptionist plus Q&A |

Legacy values accepted for compatibility:

| Legacy value | Stored as |
|---|---|
| `call_routing` | `receptionist_only` |
| `knowledge_base` | `qa_only` |

Reserved value:

| Value | Behavior |
|---|---|
| `appointment_scheduler` | Not included in Partner API v1 |

### List Extensions

```http
GET /api/v1/tenants/{tenant_id}/extensions
Authorization: Bearer <partner_api_key>
```

### Create Extension

```http
POST /api/v1/tenants/{tenant_id}/extensions
Content-Type: application/json
Authorization: Bearer <partner_api_key>
```

### Get Extension

```http
GET /api/v1/tenants/{tenant_id}/extensions/{extension_number}
Authorization: Bearer <partner_api_key>
```

### Replace Extension

```http
PUT /api/v1/tenants/{tenant_id}/extensions/{extension_number}
Content-Type: application/json
Authorization: Bearer <partner_api_key>
```

### Delete Extension

```http
DELETE /api/v1/tenants/{tenant_id}/extensions/{extension_number}
Authorization: Bearer <partner_api_key>
```

Deleting the last active extension is rejected to keep the tenant minimally
operable.

### Extension Runtime Status / Start / Stop

```http
GET  /api/v1/tenants/{tenant_id}/extensions/{extension_number}/runtime/status
POST /api/v1/tenants/{tenant_id}/extensions/{extension_number}/runtime/start
POST /api/v1/tenants/{tenant_id}/extensions/{extension_number}/runtime/stop
Authorization: Bearer <partner_api_key>
```

Runtime endpoints are partner-scoped and only operate on tenants owned by the
API key's partner. `start` and `stop` are idempotent: if the extension is already
in the requested state, the API returns the current status. Starting an
extension for a suspended tenant returns `tenant_suspended`.

Example response:

```json
{
  "extension": "101",
  "state": "running",
  "pid": null,
  "last_seen": null,
  "log_file": null,
  "service_instances": [],
  "registered": true
}
```

## End-User Portal Accounts

Portal account email addresses are globally unique across Aiker, not
tenant-scoped. OSB may use a stable email-style login such as
`admin@07ptp.onesuite.com` or `admin+07ptp@onesuite.com` as long as it is unique
and OSB-controlled. It does not have to receive email unless OSB wants to use
email-based password reset or notifications.

### Portal User Fields

`role` is the tenant portal role:

- `user`: normal Aiker tenant portal user.
- `admin`: customer-side tenant manager or owner inside that tenant portal.

`admin` here does **not** mean Aiker platform admin. It does not grant access to
the Aiker internal admin portal. Aiker internal admin roles such as superadmin or
ops are separate.

Feature access is primarily tenant-level through `feature_flags`, not per-user.
For example, whether QA or Product Info is available is controlled by the
tenant's feature flags.

`seat_limit` and `extension_limit` are capacity/allocation fields:

- `seat_limit`: how many Aiker seats are allocated to the portal account/tenant
  relationship for display, accounting, and future enforcement.
- `extension_limit`: how many AI/SIP extensions are allocated for display,
  accounting, and future enforcement.

These fields do not create extensions automatically. SIP/AI extensions are
created and started through the extension endpoints.

For most OSB-created portal users, use:

```json
{
  "role": "user",
  "seat_limit": 1,
  "extension_limit": 3
}
```

Use `role: "admin"` only for the customer's primary manager/owner account.

### Simple Tenant Data Model

```text
tenant
  feature_flags        controls enabled portal features such as qa/products
  users[]              portal login accounts: email, role, limits
  extensions[]         SIP/AI extension configuration and runtime control
  contacts[]           receptionist transfer directory
  kbqa[]               generic Q&A knowledge base
```

### List Users

```http
GET /api/v1/tenants/{tenant_id}/users
Authorization: Bearer <partner_api_key>
```

Response:

```json
[
  {
    "user_id": "uuid",
    "email": "user@example.com",
    "role": "user",
    "tenant_id": "tenant-id",
    "seat_limit": 1,
    "extension_limit": 3,
    "is_active": true,
    "created_at": "2026-06-11T00:00:00",
    "updated_at": "2026-06-11T00:00:00"
  }
]
```

### Create User

```http
POST /api/v1/tenants/{tenant_id}/users
Content-Type: application/json
Authorization: Bearer <partner_api_key>
```

Request:

```json
{
  "email": "user@example.com",
  "role": "user",
  "display_name": "Jane Smith",
  "seat_limit": 1,
  "extension_limit": 3
}
```

Supported roles: `user`, `admin`.

Response:

```json
{
  "user_id": "uuid",
  "email": "user@example.com",
  "role": "user",
  "tenant_id": "tenant-id",
  "plaintext_password": "generated-password",
  "_notice": "Store this password securely. It will NOT be shown again."
}
```

Important:

- Aiker generates the password.
- Aiker stores only the bcrypt hash.
- The plaintext password is returned once and cannot be retrieved later.
- OSB / Kloud is responsible for securely delivering the password to the user.

### Update User

```http
PATCH /api/v1/tenants/{tenant_id}/users/{user_id}
Content-Type: application/json
Authorization: Bearer <partner_api_key>
```

Supported fields:

```json
{
  "email": "new-user@example.com",
  "role": "admin",
  "password": "new-password-at-least-8-chars",
  "seat_limit": 2,
  "extension_limit": 5,
  "is_active": true
}
```

Partners can only list or update users under tenants owned by that partner.

## Batch Import Endpoints

Batch endpoints process each item independently. One bad row does not abort the
whole batch.

### Batch Extensions

```http
POST /api/v1/tenants/{tenant_id}/extensions:batch
Content-Type: application/json
Authorization: Bearer <partner_api_key>
```

Request:

```json
{
  "items": [
    {
      "agent_id": "frontdesk-101",
      "extension_number": "101",
      "sip_domain": "example.sip.domain",
      "sip_username": "101",
      "sip_server": "core1-us-lax.myippbx.com",
      "sip_password": "secret",
      "skill": "receptionist_qa"
    }
  ]
}
```

### Batch Contacts

```http
POST /api/v1/tenants/{tenant_id}/contacts:batch
Content-Type: application/json
Authorization: Bearer <partner_api_key>
```

Request:

```json
{
  "items": [
    {
      "first_name": "Sales",
      "last_name": "Team",
      "extension": "101",
      "department": "Sales",
      "contact_type": "department",
      "supports_consultation_transfer": false,
      "can_receive_client_transfer": true,
      "can_receive_visitor_transfer": true
    }
  ]
}
```

### Batch Q&A

```http
POST /api/v1/tenants/{tenant_id}/kbqa:batch
Content-Type: application/json
Authorization: Bearer <partner_api_key>
```

Request:

```json
{
  "items": [
    {
      "question": "What are your business hours?",
      "answer": "We are open Monday through Friday, 9 AM to 5 PM."
    }
  ]
}
```

### Batch Response

```json
{
  "ok": 2,
  "failed": 1,
  "results": [
    { "index": 0, "status": "ok" },
    { "index": 1, "status": "error", "error": "validation message" },
    { "index": 2, "status": "ok" }
  ]
}
```

## Portal Login

End users log in through the normal Aiker portal with their provisioned email
and password.

```text
https://aiker-kloud.web.app/login
```

If the tenant is suspended, login returns a `tenant_suspended` error.

## SSO / Automatic Login

Partner API v1 includes one-time login links so OSB can redirect users into the
Aiker portal without asking for the Aiker password again.

Aiker does not support unsafe, forgeable login links such as:

```text
https://aiker-kloud.web.app/app?tenant_id=...&email=...
```

### Create One-Time Login Link

```http
POST /api/v1/sso/login-links
Content-Type: application/json
Authorization: Bearer <partner_api_key>
```

Request:

```json
{
  "tenant_id": "tenant-id",
  "user": {
    "email": "user@example.com",
    "name": "Jane Smith"
  },
  "role": "user",
  "redirect_path": "/app/extensions"
}
```

Supported roles: `user`, `admin`.

Response:

```json
{
  "login_url": "https://aiker-kloud.web.app/partner-login?token=one-time-token",
  "expires_at": "2026-06-12T00:00:00Z",
  "expires_in_seconds": 300
}
```

Important:

- The token is valid for 5 minutes.
- The token is single-use.
- The token is stored by Aiker only as a hash.
- The partner can create links only for tenants it owns.
- The user must already exist in the Aiker tenant.
- `redirect_path` must be an internal Aiker portal path beginning with `/app`.

### Browser Redirect

OSB redirects the user's browser to the returned `login_url`.

```text
https://aiker-kloud.web.app/partner-login?token=one-time-token
```

Aiker verifies the token, creates an end-user session, and redirects the browser
to `redirect_path`.

Failure cases:

- Expired or reused token returns `401`.
- Unknown user or tenant returns `404`.
- Suspended tenant returns `403` with `tenant_suspended`.
