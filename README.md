# Aiker Partner API v1

Last updated: 2026-06-13

This repository is the external delivery package for Kloud / OneSuite Business
integration with the Aiker Partner API v1.

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

Aiker Partner API v1 supports:

- Tenant create, list, detail, replace, soft-delete
- Tenant suspend and unsuspend
- Tenant feature flags / entitlements
- AI agent / SIP extension create, list, detail, update, delete
- SIP extension runtime status, start, and stop
- Batch import for extensions, contacts, and Q&A
- End-user portal account provisioning
- End-user list and edit within a partner-owned tenant
- Tenant portal roles: `user` and `admin` currently have the same end-user
  portal permissions in v1. `admin` is only a label for the customer's primary
  portal account and is not an Aiker internal admin role.
- `extension_limit` means the number of purchased Aiker AI SIP extensions. This
  is not the customer's total OneSuite phone extension count.
- `seat_limit` is kept as purchased AI-seat/account capacity metadata. In v1,
  the practical AI seat is the provisioned AI SIP extension.
- One-time automatic login links from OSB into the Aiker portal
- Portal login blocking for suspended tenants
- HTTP-layer guard for AI extension start/restart on suspended tenants
- SIP extensions require `sip_username` in the Partner API payload; extension
  creation saves configuration and does not auto-start runtime
- End-user portal hides SIP passwords; SIP credentials are managed by the
  trusted partner API and Aiker admin portal only

The full endpoint contract is in [API_CONTRACT.md](API_CONTRACT.md).

An executable curl-based example is available at:

```bash
examples/aiker_partner_api_v1_smoke.sh
```

## Current Limitations

These items are not included in Partner API v1:

- Dedicated staging environment. Testing should use a production sandbox tenant.
- Voice-engine spoken "account suspended" prompt before hang-up. Current suspend
  behavior is enforced at portal login and backend extension-control HTTP APIs.
- Direct product catalog management through this Partner API. Product Info is a
  separate Aiker portal feature, not part of the generic Q&A API.
- iframe embedding of the Aiker portal inside OneSuite Business. Partner API v1
  uses one-time redirect login links instead.

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
     ./examples/aiker_partner_api_v1_smoke.sh
   ```
3. Kloud lists the created tenant and extension to verify ownership scoping.
4. Kloud reads extension runtime status and optionally starts/stops the sandbox
   extension when testing SIP runtime control.
5. Kloud provisions one end-user account and stores the one-time password
   securely for delivery to the user.
6. Kloud tests batch imports with a small mixed-validity payload.
7. Kloud creates and opens a one-time automatic login link for the sandbox user.
8. Kloud tests suspend / unsuspend on the sandbox tenant.
9. Kloud moves to real tenant provisioning.

To keep the script-created tenant for debugging:

```bash
KEEP_TENANT=1 AIKER_PARTNER_API_KEY='<securely-provided-key>' \
  ./examples/aiker_partner_api_v1_smoke.sh
```

To also exercise extension runtime start/stop on the sandbox extension:

```bash
RUN_EXTENSION_RUNTIME=1 AIKER_PARTNER_API_KEY='<securely-provided-key>' \
  ./examples/aiker_partner_api_v1_smoke.sh
```

## Support Contact

For API contract questions, Kloud / OSB should coordinate directly with the
Aiker project contacts already introduced by Alice.
