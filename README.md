# Aiker Partner API 1.0

Last updated: 2026-06-11

This repository is the external delivery package for Kloud / OneSuite Business
integration with the Aiker Partner API 1.0.

Production base URL:

```text
https://aiker-kloud.web.app/api/v1
```

Authentication:

```http
Authorization: Bearer <partner_api_key>
```

API keys are issued by Aiker through a secure channel. Do not send API keys in
plain email or commit them to source control.

## What Is Ready

Aiker Partner API 1.0 supports:

- Tenant create, list, detail, replace, soft-delete
- Tenant suspend and unsuspend
- Tenant feature flags / entitlements
- AI agent / SIP extension create, list, detail, update, delete
- Batch import for extensions, contacts, and Q&A
- End-user portal account provisioning
- End-user list and edit within a partner-owned tenant
- Portal login blocking for suspended tenants
- HTTP-layer guard for AI extension start/restart on suspended tenants

The full endpoint contract is in [API_CONTRACT.md](API_CONTRACT.md).

An executable curl-based example is available at:

```bash
examples/aiker_partner_api_1_0_smoke.sh
```

## Current Limitations

These items are not included in Partner API 1.0:

- Dedicated staging environment. Testing should use a production sandbox tenant.
- Automatic SSO / login-link redirect from OSB into Aiker. This must not be
  implemented with forgeable query parameters.
- Voice-engine spoken "account suspended" prompt before hang-up. Current suspend
  behavior is enforced at portal login and backend extension-control HTTP APIs.
- Direct product catalog management through this Partner API. Product Info is a
  separate Aiker portal feature, not part of the generic Q&A API.

## Public vs Internal Information Boundary

This repository is safe to share with Kloud / OSB. It contains:

- Public API base URL
- Authentication pattern using a placeholder API key
- Request and response examples
- Endpoint behavior and error semantics
- Current integration limitations

Do not put these internal Aiker details in this repository:

- Real API keys, bearer tokens, passwords, or SIP secrets
- Internal deployment revision names, image tags, or hosting version IDs
- Internal database schema migration execution notes
- Internal GitHub PR numbers or commit hashes unless Aiker explicitly wants them
- Internal smoke-test tenant IDs, test user emails, or generated passwords
- Aiker-only deployment commands or admin bearer token instructions

## Recommended Integration Order

1. Aiker issues a partner API key through a secure channel.
2. Kloud runs the smoke script against a production sandbox tenant:
   ```bash
   AIKER_PARTNER_API_KEY='<securely-provided-key>' \
     ./examples/aiker_partner_api_1_0_smoke.sh
   ```
3. Kloud lists the created tenant and extension to verify ownership scoping.
4. Kloud provisions one end-user account and stores the one-time password
   securely for delivery to the user.
5. Kloud tests batch imports with a small mixed-validity payload.
6. Kloud tests suspend / unsuspend on the sandbox tenant.
7. Kloud moves to real tenant provisioning.

To keep the script-created tenant for debugging:

```bash
KEEP_TENANT=1 AIKER_PARTNER_API_KEY='<securely-provided-key>' \
  ./examples/aiker_partner_api_1_0_smoke.sh
```

## Support Contact

For API contract questions, Kloud / OSB should coordinate directly with the
Aiker project contacts already introduced by Alice.
