# Braintree Hosted Checkout (Vault‑Only) — MVP Spec

This document describes the MVP for a Lago‑hosted checkout experience for the **Braintree** payment provider, analogous to the existing Stripe `checkout_url` flow, but **vault‑only** (no charge/subscription yet).

## Goals

- Provide a Lago‑hosted checkout URL for customers using Braintree.
- Allow embedding a Lago Checkout JS SDK on any domain.
- Vault a payment method in Braintree and persist it as the customer’s default provider payment method in Lago.
- Reuse existing webhook/event patterns where possible.
- Preserve backward compatibility with current `checkout_url` APIs.

## Non‑Goals (MVP)

- Charging a one‑time transaction.
- Starting or modifying subscriptions.
- Supporting providers beyond Braintree.
- Advanced 3DS/SCA flows (only if already enabled by Drop‑in default; full control later).

## Existing Patterns to Reuse

- **Checkout URL generation** entrypoints:
  - REST: `POST /api/v1/customers/:external_id/checkout_url`.
  - GraphQL: `generateCheckoutUrl(customerId: …)`.
  - Both call `Customers::GenerateCheckoutUrlService`.
- **Public token** pattern used by customer portal:
  - Token: `ActiveSupport::MessageVerifier.new(ENV["SECRET_KEY_BASE"]).generate(id, expires_in: …)`.
  - Verification concern reads a header and resolves customer.

## Data Model

### `CheckoutSession`

New model representing a single hosted checkout intent.

**Columns**

- `id :uuid`
- `organization_id :uuid` (belongs_to)
- `customer_id :uuid` (belongs_to)
- `payment_provider_customer_id :uuid` (belongs_to `PaymentProviderCustomers::BaseCustomer`)
- `provider_type :string` (MVP only `"braintree"`)
- `purpose :string` (MVP only `"vault"`)
- `status :enum`:
  - `created`
  - `client_token_issued`
  - `completed`
  - `failed`
  - `expired`
- `expires_at :datetime`
- `completed_at :datetime`
- `metadata :jsonb` (optional)
- timestamps

**State rules**

- Created with `status=created`, `expires_at = now + TTL` (suggest 60 minutes).
- Any request after `expires_at` sets `expired` and is rejected.
- `completed` is terminal.

### Public token

- Opaque signed token containing `checkout_session.id`.
- Expiry equals session TTL.
- Token is bearer‑style; treat as secret.

Example generation:

```ruby
verifier = ActiveSupport::MessageVerifier.new(ENV["SECRET_KEY_BASE"])
token = verifier.generate(checkout_session.id, expires_in: 60.minutes)
```

## Services

All new services follow Lago’s service conventions (extend `BaseService`, single `call`, `Result = BaseResult[…]`).

### `Checkouts::CreateSessionService`

**Inputs**: `customer:`

**Behavior**

- Validate customer exists.
- Validate `customer.provider_customer` present.
- If provider customer type is Braintree, create `CheckoutSession`.
- Return `checkout_url` and `checkout_token`.

**Result**

`Result = BaseResult[:checkout_url, :checkout_token, :checkout_session]`

### `Checkouts::ResolveSessionService`

**Inputs**: `token:`

**Behavior**

- Verify token.
- Load session scoped to organization.
- Validate not expired/completed.

**Result**

`Result = BaseResult[:checkout_session]`

### `PaymentProviders::Braintree::GenerateClientTokenService`

**Inputs**: `checkout_session:`

**Behavior**

- Construct Braintree gateway from provider credentials.
- Call `client_token.generate(customer_id: provider_customer_id)` if present.
- Update session status to `client_token_issued`.

**Result**

`Result = BaseResult[:client_token]`

### `PaymentProviderCustomers::Braintree::VaultPaymentMethodService`

**Inputs**: `checkout_session:`, `nonce:`, `device_data: nil`

**Behavior**

- Validate session state.
- Call `gateway.payment_method.create` with nonce.
- Persist returned `payment_method.token` into
  `PaymentProviderCustomers::BraintreeCustomer#payment_method_id`.
- Mark session `completed` and set `completed_at`.
- Trigger existing post‑vault behavior (e.g., pending invoice reprocessing later if required).

**Result**

`Result = BaseResult[:payment_method_id]`

## API Changes

### Checkout URL generation

- Keep current REST and GraphQL behavior.
- Add Braintree support by branching in `Customers::GenerateCheckoutUrlService`:
  - For Braintree provider customer, call `Checkouts::CreateSessionService`.
  - For all others, keep `PaymentProviderCustomers::Factory…generate_checkout_url`.

**REST response extension**

- Continue returning `checkout_url`.
- Add optional `checkout_token` field for Braintree (nullable). No breaking change.

**GraphQL extension**

- Add nullable `checkoutToken` to the payload of `generateCheckoutUrl`.

### Public checkout session endpoints (no API key)

These endpoints are used by hosted UI and embeddable SDK.

- `GET /checkout_sessions/:token`
  - Resolves token → session.
  - Returns config required to render provider UI.

Response example:

```json
{
  "provider_type": "braintree",
  "purpose": "vault",
  "payment_method_types": ["credit_card", "paypal"],
  "organization_branding": {"logo_url": null, "primary_color": null},
  "status": "created",
  "expires_at": "…"
}
```

- `POST /checkout_sessions/:token/braintree_client_token`
  - Returns `{ "client_token": "…" }`.

- `POST /checkout_sessions/:token/confirm`
  - Body `{ "nonce": "…", "device_data": "…" }`.
  - Vaults payment method and marks session completed.

### CORS

- Enable CORS for `/checkout_sessions/*` so SDK can call from any origin.
- Limit methods to `GET, POST`.

## Webhooks

Reuse existing webhook events.

- On generation: `customer.checkout_url_generated` (already emitted for other providers).
- On successful vault: `customer.payment_provider_created`.
- On provider error: `customer.payment_provider_error` or `payment_provider.error` (depending on existing conventions).

## Hosted UI (Frontend)

- URL: `#{ENV["LAGO_FRONT_URL"]}/checkout/:token`.
- Flow:
  1. Fetch session config.
  2. Fetch Braintree client token.
  3. Render Drop‑in.
  4. Submit → call confirm.
  5. Redirect to provider success URL or show success state.

Frontend is out of scope for backend repo, but endpoints above are sufficient.

## Embeddable JS SDK

### Responsibilities

- Accept a `checkoutToken` and mount target.
- Fetch session config from Lago.
- Load the correct provider UI (MVP Braintree Drop‑in).
- Fetch provider client token.
- Render UI with Lago default theme + user overrides.
- Collect nonce and call confirm.
- Expose lifecycle events.

### Backend contract

SDK relies on:

- `GET /checkout_sessions/:token`.
- `POST /checkout_sessions/:token/braintree_client_token`.
- `POST /checkout_sessions/:token/confirm`.

### Proposed SDK API

```ts
import { createCheckout } from "@lago/checkout";

const checkout = await createCheckout({
  checkoutToken: "…",
  apiUrl: "https://api.lago.example", // optional, defaults from window
  mount: "#checkout",
  theme: {
    mode: "light" | "dark",
    variables: {
      primaryColor: "#…",
      fontFamily: "…"
    },
    cssUrl?: "https://…/custom.css"
  },
  providerOptions: {
    card: { cardholderName: true },
    paypal: { flow: "vault" }
  },
  onReady(session) {},
  onSuccess(result) {},
  onError(error) {},
  onCancel() {}
});

checkout.destroy();
```

### Braintree adapter details

- Dynamically load Drop‑in JS only when `provider_type === "braintree"`.
- CDN URL example:
  - `https://js.braintreegateway.com/web/dropin/1.39.0/js/dropin.min.js`
- Create Drop‑in after client token:

```js
braintree.dropin.create({
  authorization: clientToken,
  container,
  ...providerOptions
});
```

- On submit, call `instance.requestPaymentMethod()` to retrieve `nonce` (+ `deviceData`), then confirm.

### Styling

- Default CSS scoped to `.lago-checkout`.
- Theme via CSS variables on wrapper:
  - `--lago-primary`, `--lago-radius`, `--lago-font`.
- If `cssUrl` provided, load after default for overrides.

### Distribution

- npm package `@lago/checkout` (ESM + UMD build).
- Optional CDN bundle exposing `window.LagoCheckout.createCheckout`.
- Major versions aligned with API contract (`/checkout_sessions` v1).

### Security

- `checkoutToken` is a bearer secret.
- Do not log/store/reuse after completion.
- Token TTL and single‑use semantics reduce exposure.

## Open Questions (post‑MVP)

- Full 3DS/SCA configuration and liability‑shift handling.
- Multi‑merchant account routing by currency.
- Extending to charge/subscription purposes.
- Adding providers beyond Braintree.
