# Lago-owned Stripe Shared Payment Tokens

The customer supplies an SPT to Lago. Lago stores it on its Stripe provider-customer connection and uses it directly in a Stripe PaymentIntent. No Stripe Customer `invoice_settings.default_shared_payment_token` update is required.

## Configure a customer

Send this body to `POST /api/v1/customers`, authenticated with the organization's Lago API key:

```json
{
  "customer": {
    "external_id": "your-agent-id",
    "currency": "USD",
    "billing_configuration": {
      "payment_provider": "stripe",
      "payment_provider_code": "your-stripe-integration",
      "sync_with_provider": true,
      "provider_payment_methods": ["card"],
      "default_shared_payment_token": "spt_REPLACE"
    }
  }
}
```

Wait for Lago to create/link the Stripe customer before collection. For an existing customer, submit its external ID and the billing configuration with the token. Omission preserves the token; explicit `null` clears it. Customer responses show `has_shared_payment_token`, not the credential. Storage uses the Stripe provider-customer's existing `settings` JSON; no database migration is required. The token is not separately encrypted by this patch.

Issue invoices normally. Do not use `skip_psp` or manual reconciliation. The collector sets:

```ruby
payment_method_data: {shared_payment_granted_token: token}
payment_method_types: ["card"]
```

It removes `off_session` and `return_url` for SPT payments and sends `Stripe-Version: 2026-04-22.preview`. Normal payment idempotency, Stripe response handling and invoice reconciliation remain in Lago.

## Selection and scope

- An explicitly configured Lago token takes priority over saved cards. A rejected token fails collection; there is no fallback to a card and no automatic token removal.
- Clearing the token restores normal payment-method selection.
- Explicit manual-payment choices are preserved. Automatic collection also works for customers whose only payment credential is an SPT.
- Existing main's feature-flagged Stripe-Customer token lookup remains available when no Lago token is configured. It retains its existing fallback priority.
- This implements Orb's billing-side customer storage and token-first selection. Per-invoice token overrides and Orb's no-dunning policy are not implemented; Lago's existing retries remain.
- The verified test-helper token was single-use. Obtain a fresh eligible token before another payment; recurring mandate behavior was not tested.
- API support only; no token input has been added to Lago's dashboard UI.

## Validation scope

The request spec exercises API storage and redaction, omission and explicit clearing, format/card validation, native invoice collection, token priority over a saved card, and failure without card fallback.

The equivalent local integration has also been exercised with a buyer-issued token, a Lago credit invoice and settled wallet credits. Stripe inbound webhook delivery was not part of that check; invoice reconciliation used the PaymentIntent response.
