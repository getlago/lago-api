# Design: Subscription Activation Rules Engine

## 1. Current Flow Analysis

### 1.1 Subscription Creation (today)

There are **four entry points** where a subscription becomes active and billing is triggered. All four share duplicated "should I bill?" logic:

**Entry Point A — `Subscriptions::CreateService#create_subscription` (line 112-179)**
```
subscription_at <= now?
  YES -> mark_as_active!
        -> EmitFixedChargeEventsService
        -> if fixed_charges.pay_in_advance -> CreatePayInAdvanceFixedChargesJob
        -> if plan.pay_in_advance && !trial -> BillSubscriptionJob(:subscription_starting)
        -> SendWebhookJob("subscription.started")
  NO  -> pending!
```

**Entry Point B — `Subscriptions::ActivateService#activate_all_pending` (line 11-43)**
Clock job runs for pending subscriptions whose `subscription_at` has arrived:
```
mark_as_active!
-> EmitFixedChargeEventsService
-> SendWebhookJob("subscription.started")
-> if plan.pay_in_advance && !trial -> BillSubscriptionJob(:subscription_starting)
-> elsif fixed_charges.pay_in_advance -> CreatePayInAdvanceFixedChargesJob
```

**Entry Point C — `Subscriptions::PlanUpgradeService#call` (line 14-57)**
```
TerminateService(current, upgrade: true)
new_subscription.mark_as_active!
-> EmitFixedChargeEventsService
-> if plan.pay_in_advance || fixed_charges.pay_in_advance -> BillSubscriptionJob(:upgrading)
-> SendWebhookJob("subscription.started")
```

**Entry Point D — `Subscriptions::TerminateService#terminate_and_start_next`**
Downgrade rotation on billing date:
```
subscription.mark_as_terminated!
next_subscription.mark_as_active!
-> EmitFixedChargeEventsService
-> BillSubscriptionJob([old, new], :upgrading)
-> BillNonInvoiceableFeesJob([old], rotation_date)
-> SendWebhookJob("subscription.terminated", old)
-> SendWebhookJob("subscription.started", new)
```

### 1.2 Observation: Duplicated Logic

The "activate + bill + webhook" sequence is repeated 4 times with slight variations. This is the **primary refactoring opportunity**: extract a single `Subscriptions::ActivateAndBillService` that all entry points call, which becomes the natural interception point for activation rules.

### 1.3 Invoice Status After Billing (today)

When billing happens, the invoice flows through:
```
CreateGeneratingService -> status: :generating
CalculateFeesService -> computes fees
TransitionToFinalStatusService:
  -> fees > 0 -> FinalizeService -> status: :finalized
  -> fees = 0 -> status: :closed (or finalized per customer setting)
After finalization:
  -> Invoices::Payments::CreateService.call_async -> sends to PSP
```

Invoices are immediately finalized and visible to the customer. There is no mechanism today to create a subscription invoice in a "hidden" state.

### 1.4 Payment Callback Chain (today)

```
PSP webhook -> InboundWebhooks::ProcessService
  -> PaymentProviders::Stripe::HandleEventService
    -> PaymentIntentSucceededService
      -> Invoices::Payments::StripeService#update_payment_status
        -> Payment.save!(payable_payment_status: :succeeded)
        -> Invoices::UpdateService.call(payment_status: :succeeded)
          -> invoice.save!
          -> schedule_post_processing_jobs
            -> handle_prepaid_credits (for credit invoices)
            -> update_fees_payment_status
            -> deliver_webhook("invoice.payment_status_updated")
```

The `handle_prepaid_credits` pattern in `Invoices::UpdateService` is the **exact template** for adding a payment-gated activation hook.

---

## 2. Proposed Data Model

### 2.1 API Surface: Rules as jsonb on Subscription

Product spec defines activation rules as a jsonb attribute on the subscription using the name `activate_on_payment` for the payment rule. The technical implementation uses `payment_required` as the `rule_type` for clarity in the codebase. The API format below is a technical proposal — final API naming may differ from both product spec and this document.

The API accepts and returns rules as an array:

**REST API (create/update):**
```json
{
  "subscription": {
    "plan_code": "premium",
    "external_customer_id": "cust_123",
    "activation_rules": [
      { "rule_type": "payment_required", "timeout_hours": 48 },
      { "rule_type": "approval_required", "timeout_hours": 168 }
    ]
  }
}
```

**GraphQL mutation input:**
```graphql
input ActivationRuleInput {
  ruleType: ActivationRuleTypeEnum!   # PAYMENT_REQUIRED, APPROVAL_REQUIRED
  timeoutHours: Int                   # optional
}

input CreateSubscriptionInput {
  # ... existing fields ...
  activationRules: [ActivationRuleInput!]
}
```

**Response (REST serializer / GraphQL type):**
```json
{
  "activation_rules": [
    {
      "lago_id": "uuid",
      "rule_type": "payment_required",
      "timeout_hours": 48,
      "status": "pending",
      "expires_at": "2026-02-28T12:00:00Z"
    }
  ]
}
```

The response includes runtime state (`status`, `expires_at`) so the API consumer can see where each rule stands.

### 2.2 Storage: Separate Table for Rules

Despite the jsonb API surface, rules are stored in a dedicated table. The jsonb format is a **serialization concern** handled by the controller/serializer layer, not a storage decision.

```ruby
# Table: subscription_activation_rules
create_table :subscription_activation_rules, id: :uuid do |t|
  t.references :subscription, null: false, foreign_key: true, type: :uuid, index: true
  t.references :organization, null: false, foreign_key: true, type: :uuid

  t.string :rule_type, null: false    # e.g., "payment_required", "approval_required"
  t.string :status, null: false       # "pending", "satisfied", "failed", "not_applicable", "expired"
  t.integer :timeout_hours            # nil means no expiration
  t.datetime :expires_at              # computed at evaluation time from timeout_hours

  t.timestamps
end

add_index :subscription_activation_rules, [:subscription_id, :rule_type], unique: true
add_index :subscription_activation_rules, [:status, :expires_at],
  where: "status = 'pending' AND expires_at IS NOT NULL",
  name: "index_activation_rules_pending_with_expiry"
```

**Why a separate table instead of jsonb on subscriptions?**

| Concern | jsonb column | Separate table |
|---------|-------------|----------------|
| Query expired rules (clock job) | Requires `jsonb_array_elements`, slow, hard to index | Simple `WHERE status = 'pending' AND expires_at <= now`, indexable |
| Rule status tracking | Mutable nested JSON, easy to corrupt | Each rule is an ActiveRecord with validations and enum |
| Adding new rule types | New keys in JSON, no schema validation | New records, validated by model |
| API shape | Matches product spec directly | Serializer maps table rows to JSON array (trivial) |
| Consistency with codebase | Subscription table has **zero** jsonb columns today; all flexible data uses related tables (plan overrides, custom sections, entitlements) | Follows existing patterns |

The subscription table currently stores all flexible associations in related tables (e.g., `Subscription::AppliedInvoiceCustomSection`, `Entitlement::Entitlement`, `UsageThreshold`). A jsonb column would be a pattern outlier.

**Rule configuration per type:**

| Rule Type | Configuration Fields | Example |
|-----------|---------------------|---------|
| `payment_required` | `timeout_hours` (integer, optional) | `timeout_hours: 48` |
| `approval_required` | `timeout_hours` (integer, optional) | `timeout_hours: 168` |

When `timeout_hours` is set and the rule becomes `pending`, `expires_at` is computed as `Time.current + timeout_hours.hours`. When `timeout_hours` is `nil`, the rule never expires (no automatic cancellation).

**Note:** If future rule types require configuration fields beyond `timeout_hours`, we can either add columns to the table or introduce a `configuration` jsonb column at that point. For now, `timeout_hours` is a first-class column shared by all rule types since every rule type could reasonably support a timeout.

### 2.3 Rule Lifecycle: Creation, Updates, and Mutability

Rules are created at subscription creation time and can be updated via the subscription update API, with restrictions based on subscription status:

**On subscription create:**
- `Subscriptions::CreateService` receives `activation_rules` params
- Rule records are created in the same transaction as the subscription with `status: :pending`
- Rules are evaluated when activation time arrives (either immediately if `subscription_at <= now`, or when the clock job fires for future-dated subscriptions). `EvaluateService` then transitions each rule to either confirmed `pending` (applicable, waiting to be resolved) or `not_applicable`

**On subscription update — mutability by status:**

| Subscription Status | Can modify rules? | Behavior |
|--------------------|-------------------|----------|
| `pending` | Yes, freely | Rules haven't been evaluated yet. Add, remove, or change configuration (e.g., `timeout_hours`). This is the safe window. |
| `activating` | Limited | See analysis below |
| `active` | No | Subscription is already active, rules are irrelevant. Reject with validation error. |
| `terminated` / `canceled` | No | Subscription is in terminal state. Reject. |

**Updating rules on `activating` subscriptions — impact analysis:**

When a subscription is `activating`, rules have been evaluated and side effects may be in flight (invoice created, payment issued to PSP). Changing rules at this point is complex:

| Change | Impact | Recommendation |
|--------|--------|----------------|
| Add a new rule | Would need to block activation further. But the invoice/payment for the payment rule is already in progress. New rule evaluation would need to happen without re-billing. | Reject for v1 |
| Remove the only pending rule | Subscription should activate immediately. But need to finalize the gated invoice and complete activation. | Reject for v1 — user can wait for payment or cancel |
| Change `timeout_hours` | Would need to recompute `expires_at` on the rule. Relatively safe if the rule is still pending. | Could allow, low risk |
| Remove a `not_applicable` rule | No impact on activation flow. | Allow (it's a no-op for activation) |

**Recommendation for v1:** Reject rule modifications on `activating` subscriptions entirely. Return a validation error: `"activation_rules cannot be modified while subscription is activating"`. This is simple, safe, and avoids edge cases. The user can cancel the subscription and create a new one with different rules.

**Future consideration:** Allow specific safe mutations (like extending timeout) on `activating` subscriptions. This can be unlocked incrementally once the core flow is stable.

**Validation in UpdateService:**
```ruby
# In Subscriptions::UpdateService or Subscriptions::ValidateService
def validate_activation_rules_update
  return if params[:activation_rules].blank?

  if subscription.activating?
    result.single_validation_failure!(
      field: :activation_rules,
      error_code: "cannot_modify_while_activating"
    )
    return false
  end

  if subscription.active? || subscription.terminated? || subscription.canceled?
    result.single_validation_failure!(
      field: :activation_rules,
      error_code: "cannot_modify_after_activation"
    )
    return false
  end

  true
end
```

**Service flow for rule updates on `pending` subscriptions:**
```ruby
# In Subscriptions::UpdateService
def update_activation_rules
  return if params[:activation_rules].nil?  # nil = not provided, don't touch

  # Replace all existing rules with the new set
  subscription.activation_rules.destroy_all
  params[:activation_rules].each do |rule_params|
    subscription.activation_rules.create!(
      organization: subscription.organization,
      rule_type: rule_params[:rule_type],
      timeout_hours: rule_params[:timeout_hours],
      status: :pending  # will be properly evaluated at activation time
    )
  end
end
```

Rules use a **replace-all** strategy (not patch): the API consumer sends the full desired array of rules, and we replace whatever was there. This matches the pattern used for other nested resources in the codebase (e.g., `plan_overrides.charges`).

### 2.4 Subscription Status: Add `activating`

```ruby
# IMPORTANT: :activating MUST be appended at the end to preserve existing integer mappings.
# Current model uses `enum :status, STATUSES` with an array, so Rails maps by position:
# pending=0, active=1, terminated=2, canceled=3, activating=4
STATUSES = [
  :pending,       # 0 — future start date, not yet reached
  :active,        # 1 — fully active, billing normal
  :terminated,    # 2
  :canceled,      # 3
  :activating     # 4 — subscription_at reached, rules being evaluated
].freeze
```

**Impact on existing code:**
- `default_scope` — subscription model has no default_scope, so no impact
- `editable_subscriptions` in CreateService queries `active` and `starting_in_the_future` — needs to also include `activating` (a customer might try to upgrade/downgrade while activation is pending)
- API serializers — `activating` should be visible to customers as a distinct state
- `active_subscriptions` checks in `Invoices::SubscriptionService` — `activating` subscriptions should **not** be treated as active for regular periodic billing
- `Invoices::CreatePayInAdvanceFixedChargesService` has `return result unless subscription.active?` guard (line 17) — must be updated to also allow `activating?` subscriptions, otherwise gated invoices for arrears plans with advance fixed charges would never be created

New model methods:
```ruby
def mark_as_activating!(timestamp = Time.current)
  self.started_at ||= timestamp
  activating!
end
```

Note: `mark_as_activating!` sets `started_at` just like `mark_as_active!`. This is important because billing period boundaries are calculated from `started_at`. The subscription "started" even though it's not yet fully active — we need dates anchored to when it was supposed to start.

### 2.5 Invoice Gating: The `gated` Parameter

No new invoice statuses are needed. Use the existing `open` status for gated invoices — it's already invisible to customers (`INVISIBLE_STATUS`), and `status_changed_to_finalized?` already handles `open -> finalized` transitions.

**Two billing paths need gating awareness:**

There are two mutually exclusive billing services that fire at subscription activation. Both need to support gated invoices:

| Scenario | Billing Service | Why |
|----------|----------------|-----|
| Plan pay_in_advance, no trial | `Invoices::SubscriptionService` (via `BillSubscriptionJob`) | Bills the subscription fee upfront |
| Plan pay_in_arrears + advance fixed charges | `Invoices::CreatePayInAdvanceFixedChargesService` | Bills only the fixed charges upfront |
| Plan pay_in_advance + trial + advance fixed charges | `Invoices::CreatePayInAdvanceFixedChargesService` | Trial exempts subscription fee, but fixed charges still bill |
| subscription_at in the past | Neither (`subscription_at.today?` / `started_at.today?` = false) | Migration scenario — subscription already paid, no gating |

Both services converge on `Invoices::TransitionToFinalStatusService` and share the same post-finalization pipeline (webhooks, documents, payment). The `gated` parameter flows through this shared path:

```ruby
# TransitionToFinalStatusService with gated support
def call
  if gated
    invoice.status = :open
  elsif should_finalize_invoice?
    Invoices::FinalizeService.call!(invoice:)
  else
    invoice.status = :closed
  end
  result.invoice = invoice
  result
end
```

**Post-finalization pipeline behavior when gated:**

Both `Invoices::SubscriptionService` and `CreatePayInAdvanceFixedChargesService` have a post-transaction block that sends webhooks, generates documents, and triggers payment. When the invoice is `open` (gated), only payment should fire:

```ruby
# Replaces the existing `unless invoice.closed?` block in both services
if invoice.finalized?
  # Full pipeline (current behavior)
  SendWebhookJob.perform_after_commit("invoice.created", invoice)
  GenerateDocumentsJob.perform_after_commit(invoice:)
  Integrations::Aggregator::Invoices::CreateJob.perform_after_commit(invoice:)
  Invoices::Payments::CreateService.call_async(invoice:)
elsif invoice.open?
  # Gated: only trigger payment (need PSP to charge), skip everything else
  Invoices::Payments::CreateService.call_async(invoice:)
end
```

This ensures the PSP receives the payment request while the invoice remains invisible to the customer.

**Zero-amount and no-provider edge cases:**

After the gated invoice is created, two special cases need immediate handling:

1. **Zero-amount invoice** (coupons/credits cover everything): The payment rule is auto-satisfied. `Invoices::Payments::CreateService#call` already auto-succeeds for zero-amount invoices (line 20-22), which triggers the payment callback chain and activates the subscription. However, `call_async` (used in the gated pipeline) returns early when no payment provider is configured (line 88). To handle zero-amount invoices reliably regardless of provider configuration, `ActivateAndBillService` should check the invoice amount after creation and auto-satisfy the payment rule immediately if zero — bypassing the PSP entirely.

2. **No payment provider configured** (and amount > 0): `call_async` returns early, the payment is never sent to a PSP, and the subscription would be stuck in `activating` indefinitely. This is checked eagerly in `EvaluateService#payment_rule_applicable?` — if the customer has no payment provider and the plan requires upfront payment, the rule cannot be met. The service returns an error and the subscription is not created. See section 4.2.

**`BillNonInvoiceableFeesJob` — not gated:**

`BillNonInvoiceableFeesJob` handles pay-in-arrears non-invoiceable fees. It is called on termination and downgrade rotation (Entry Point D), never on initial activation. These fees are billed AFTER usage occurs and should not be gated. The refactored `ActivateAndBillService` does not call this job — it remains in `TerminateService` where it fires when the old subscription is terminated (after the new subscription's payment clears).

---

## 3. Proposed State Machine

```
  API: subscription_at       API: subscription_at       API: subscription_at
      in the future               = today                  in the past
           |                        |                        |
           v                        v                        v
     +===========+            +============+           +=========+
     |  PENDING  |            |  DECISION  |           |  ACTIVE |
     | (wait for |            |            |           | (no     |
     |  clock)   |            +-----+------+           | billing,|
     +=====+=====+                  |                   | no gate)|
           |                  +-----+------+           +=========+
    clock: subscription_at    |            |
        reached               |            |
           |            rules present   no rules (or
           v            AND applicable  not applicable)
     +============+           |            |
     |  DECISION  |     +-----v-----+ +---v--------+
     +-----+------+     | ACTIVATING| |   ACTIVE   |
           |             |           | | (current   |
     (same as above)     | invoice:  | |  flow)     |
                         |  open     | +------------+
                         | payment:  |
                         |  issued   |
                         +-----+-----+
                               |
                    all rules satisfied
                               |
                         +-----v-----+
                         |   ACTIVE  |
                         | invoice:  |
                         |  open ->  |
                         |  finalized|
                         +-----------+
```

**Transition triggers:**

| From | To | Trigger |
|------|----|---------|
| (creation) | `pending` | `subscription_at` is in the future |
| (creation) | `active` | `subscription_at` is in the past (migration scenario, no billing, no gating) |
| (creation) | `active` | `subscription_at` is today + no applicable rules |
| (creation) | `activating` | `subscription_at` is today + rules present and applicable |
| `pending` | `activating` | Clock job: `subscription_at` reached + rules present and applicable |
| `pending` | `active` | Clock job: `subscription_at` reached + no applicable rules (current behavior) |
| `activating` | `active` | All rules satisfied (e.g., payment succeeded) |
| `activating` | `canceled` | Manual cancellation or rule expiration (timeout) |
| `pending` | `canceled` | Canceled before start date |

---

## 4. Service Design

### 4.1 Refactoring: Extract Activation Logic

**New service: `Subscriptions::ActivateAndBillService`**

This consolidates the duplicated activate+bill+webhook logic from the 4 entry points:

```ruby
module Subscriptions
  class ActivateAndBillService < BaseService
    def initialize(subscription:, timestamp:, invoicing_reason:, previous_subscription: nil)
      # ...
    end

    def call
      # 1. Evaluate activation rules
      rules_result = ActivationRules::EvaluateService.call(subscription:)

      if rules_result.has_applicable_rules?
        # GATED PATH
        activate_with_rules(rules_result)
      else
        # CURRENT PATH (unchanged behavior)
        activate_immediately
      end
    end

    private

    def activate_with_rules(rules_result)
      subscription.mark_as_activating!(timestamp)
      emit_fixed_charge_events

      # Create gated invoice via the appropriate billing path
      # Both paths propagate gated: true to TransitionToFinalStatusService
      # which holds the invoice at 'open' status
      if subscription.plan.pay_in_advance? && !subscription.in_trial_period?
        after_commit do
          BillSubscriptionJob.perform_later(
            [subscription], timestamp,
            invoicing_reason:, skip_charges: true, gated: true
          )
        end
      elsif subscription.fixed_charges.pay_in_advance.any?
        after_commit do
          Invoices::CreatePayInAdvanceFixedChargesJob.perform_later(
            subscription, timestamp, gated: true
          )
        end
      end

      after_commit do
        SendWebhookJob.perform_later("subscription.activating", subscription)
      end
    end

    def activate_immediately
      # IMPORTANT: This path must preserve ALL current behaviors and side effects
      # exactly as they exist in each entry point today, including ordering.
      # Webhooks must fire at the same point relative to billing as they do now.
      subscription.mark_as_active!(timestamp)
      emit_fixed_charge_events
      send_started_webhook  # webhook fires before billing (matches ActivateService ordering)
      bill_subscription     # existing billing logic per entry point, unchanged
    end
  end
end
```

**Callers after refactoring:**
- `CreateService#create_subscription` -> calls `ActivateAndBillService`
- `ActivateService#activate_all_pending` -> calls `ActivateAndBillService`
- `PlanUpgradeService#call` -> calls `ActivateAndBillService` for the new subscription (does NOT terminate old subscription when gated — termination is deferred until payment succeeds, see section 5.4)
- `TerminateService#terminate_and_start_next` -> calls `ActivateAndBillService` for the next subscription (does NOT terminate old subscription when gated — termination is deferred, see section 5.5)

### 4.2 Rule Evaluation

**New service: `Subscriptions::ActivationRules::EvaluateService`**

```ruby
module Subscriptions
  module ActivationRules
    class EvaluateService < BaseService
      def initialize(subscription:)
        @subscription = subscription
      end

      def call
        rules = subscription.activation_rules

        # No rules configured -> current behavior
        return result if rules.empty?

        rules.each do |rule|
          if applicable?(rule)
            rule.update!(
              status: :pending,
              expires_at: compute_expires_at(rule)
            )
          else
            rule.update!(status: :not_applicable)
          end
        end

        result.has_applicable_rules = rules.any?(&:pending?)
        result
      end

      private

      def applicable?(rule)
        case rule.rule_type
        when "payment_required"
          payment_rule_applicable?
        when "approval_required"
          true  # always applicable when configured
        end
      end

      def payment_rule_applicable?
        has_upfront_billing = (subscription.plan.pay_in_advance? && !subscription.in_trial_period?) ||
          subscription.fixed_charges.pay_in_advance.any?

        # Nothing to pay upfront -> rule is not applicable
        return false unless has_upfront_billing

        # Something to pay but no payment provider -> rule can never be met
        unless subscription.customer.payment_provider.present?
          raise_payment_provider_missing_error!
        end

        true
      end

      def raise_payment_provider_missing_error!
        result.single_validation_failure!(
          field: :activation_rules,
          error_code: "payment_provider_required_for_payment_rule"
        )
        raise BaseService::FailedResult, result
      end

      def compute_expires_at(rule)
        return nil if rule.timeout_hours.blank?

        Time.current + rule.timeout_hours.hours
      end
    end
  end
end
```

### 4.3 Gated Invoice Creation

No new service needed. The existing billing services (`Invoices::SubscriptionService` and `Invoices::CreatePayInAdvanceFixedChargesService`) are modified to accept a `gated:` parameter that propagates through to `TransitionToFinalStatusService`.

The `gated` parameter cannot be applied after the fact — both billing services send webhooks, generate documents, and trigger integrations in their post-transaction block. A post-hoc status override would be too late; those side effects would have already fired. The parameter must flow through the chain so that:

1. `TransitionToFinalStatusService` holds the invoice at `open` instead of `finalized`
2. The post-transaction block detects `open` status and only triggers payment (skipping webhooks, documents, integrations)

**Which billing path is called depends on the subscription:**

```ruby
# In ActivateAndBillService#activate_with_rules
def create_gated_invoice
  if subscription.plan.pay_in_advance? && !subscription.in_trial_period?
    # Same as current flow, but with gated: true
    BillSubscriptionJob.perform_later(
      [subscription], timestamp,
      invoicing_reason:, skip_charges: true, gated: true
    )
  elsif subscription.fixed_charges.pay_in_advance.any?
    Invoices::CreatePayInAdvanceFixedChargesJob.perform_later(
      subscription, timestamp, gated: true
    )
  end
end
```

Both jobs propagate `gated:` to their respective services, which propagate it to `TransitionToFinalStatusService`. See section 2.5 for the implementation details.

### 4.4 Payment Success Callback

**New service: `Subscriptions::ActivationRules::ProcessPaymentService`**

Inserted into `Invoices::UpdateService#schedule_post_processing_jobs`:

```ruby
# In Invoices::UpdateService
def schedule_post_processing_jobs(old_payment_status)
  if params.key?(:payment_status)
    handle_prepaid_credits(params[:payment_status])
    handle_gated_activation(params[:payment_status])  # NEW
    update_fees_payment_status
    # ...
  end
end

def handle_gated_activation(payment_status)
  return unless invoice.open? && invoice.subscription?
  return unless %i[succeeded failed].include?(payment_status.to_sym)

  Subscriptions::ActivationRules::ProcessPaymentJob.perform_after_commit(
    invoice, payment_status.to_sym
  )
end
```

**The ProcessPaymentService:**

```ruby
module Subscriptions
  module ActivationRules
    class ProcessPaymentService < BaseService
      def call
        subscription = invoice.subscriptions.first
        rule = subscription.activation_rules.find_by(rule_type: "payment_required")
        # NOTE: Check both pending and failed — on retry after failure,
        # the rule is already failed but should still be resolvable
        return result unless rule&.pending? || rule&.failed?

        if payment_status == :succeeded
          rule.update!(status: :satisfied)
          TryActivateService.call!(subscription:, invoice:)
        else
          rule.update!(status: :failed)
          # subscription stays in activating, customer can retry via payment retry
        end
      end
    end
  end
end
```

**`TryActivateService` — separate service for reuse by future rule types:**

```ruby
module Subscriptions
  module ActivationRules
    class TryActivateService < BaseService
      def initialize(subscription:, invoice:)
        @subscription = subscription
        @invoice = invoice
      end

      def call
        # Check if ALL rules are satisfied (none still pending)
        return result if subscription.activation_rules.pending.any?

        # Finalize the gated invoice (open -> finalized)
        Invoices::FinalizeService.call!(invoice:)

        # Run the standard post-finalization pipeline
        SendWebhookJob.perform_later("invoice.created", invoice)
        Invoices::GenerateDocumentsJob.perform_later(invoice:)
        Invoices::Payments::CreateService.call_async(invoice:) # no-op, already paid
        # ... integrations (Aggregator, Hubspot)

        # Activate the subscription
        subscription.mark_as_active!

        # If this is an upgrade/downgrade, NOW terminate the old subscription
        # (it was kept active during the payment window)
        terminate_previous_subscription

        SendWebhookJob.perform_later("subscription.started", subscription)
        Utils::ActivityLog.produce(subscription, "subscription.started")
      end

      private

      def terminate_previous_subscription
        previous = subscription.previous_subscription
        return unless previous&.active?

        Subscriptions::TerminateService.call(
          subscription: previous,
          upgrade: true
        )
      end
    end
  end
end
```

### 4.5 Complete Service Map

| Service | Responsibility |
|---------|---------------|
| `Subscriptions::ActivateAndBillService` | Single entry point for activation (replaces duplicated logic in 4 places) |
| `ActivationRules::EvaluateService` | Checks which rules are configured and applicable; validates payment provider exists |
| `ActivationRules::ProcessPaymentService` | Handles PSP payment callback, satisfies/fails payment rule |
| `ActivationRules::TryActivateService` | Checks if all rules are satisfied; finalizes invoice, activates subscription, terminates previous |
| `ActivationRules::ExpireService` | Expires a single rule that has timed out, cancels subscription if no pending rules remain |
| `ActivationRules::CancelService` | Cancels an activating subscription (closes gated invoice, cancels subscription) |
| `Clock::ActivationRulesExpirationJob` | Clock job that finds expired pending rules and calls `ExpireService` for each |

**Note:** No separate `CreateGatedInvoiceService` exists. The existing billing services (`Invoices::SubscriptionService` and `CreatePayInAdvanceFixedChargesService`) are modified to accept a `gated:` parameter — see section 4.3.

---

## 5. Sequence Diagrams

### 5.1 New Subscription with Payment Rule (pay-in-advance plan)

```
API Request: Create Subscription
    |
    v
CreateService
    | subscription_at = now
    v
ActivateAndBillService
    |
    v
EvaluateService
    | payment_required rule configured
    | plan.pay_in_advance? = true -> APPLICABLE
    v
subscription.mark_as_activating!(now)
    |
    v
Create invoice (status: open, invisible)
    | fees calculated, taxes applied
    | NO sequential number assigned (not finalized)
    v
Invoices::Payments::CreateService.call_async
    | Payment created (status: pending)
    | Sent to Stripe/Adyen/etc.
    v
SendWebhookJob("subscription.activating", subscription)
    |
    v
[WAIT FOR PSP RESPONSE]
    |
    v
PSP webhook: payment_intent.succeeded
    |
    v
Invoices::Payments::StripeService#update_payment_status
    | Payment -> succeeded
    v
Invoices::UpdateService
    | invoice.payment_status = :succeeded
    | invoice is open (invisible), so no "payment_status_updated" webhook
    v
handle_gated_activation(:succeeded)
    |
    v
ProcessPaymentService
    | rule.status -> satisfied
    | all rules satisfied? YES
    v
invoice.status -> finalized (open -> finalized)
    | sequential number assigned
    | invoice.created webhook sent
    | PDF generated
    v
subscription.mark_as_active!
    |
    v
SendWebhookJob("subscription.started", subscription)
```

### 5.2 New Subscription with Payment Rule (pay-in-arrears, no advance fixed charges)

```
API Request: Create Subscription
    |
    v
CreateService
    | subscription_at = now
    v
ActivateAndBillService
    |
    v
EvaluateService
    | payment_required rule configured
    | plan.pay_in_arrears? = true
    | fixed_charges.pay_in_advance = none
    | -> NOT APPLICABLE
    v
subscription.mark_as_active!(now)  <-- CURRENT BEHAVIOR
    | no invoice created (arrears)
    v
SendWebhookJob("subscription.started", subscription)
```

### 5.3 Payment Failure -> Retry -> Success -> Activation

```
[After initial payment sent to PSP]
    |
PSP webhook: payment_intent.payment_failed
    |
    v
Invoices::UpdateService
    | invoice.payment_status = :failed
    | invoice remains open (invisible)
    v
handle_gated_activation(:failed)
    | rule.status -> failed
    | subscription stays activating
    v
SendWebhookJob("subscription.activation_expired", subscription)
    | (customer/org notified, can retry)

[Customer triggers retry via API or new payment method]
    |
    v
Invoices::Payments::RetryService (or new CreateService)
    | new Payment sent to PSP
    |
    v
PSP webhook: payment_intent.succeeded
    |
    v
[Same flow as 5.1 from "PSP webhook" onwards]
    | rule reset to satisfied
    | invoice finalized
    | subscription activated
```

### 5.4 Upgrade with Payment Rule on New Plan

Product vision: upgrades are applied **immediately when payment succeeds**. The customer stays on their current plan until payment clears. A proration invoice is created in `open` (invisible) status. On failure or timeout, the upgrade is cancelled and the customer keeps their current plan.

Technically, `PlanUpgradeService` creates a new subscription in `activating` state (the "pending upgrade"). The old subscription is NOT terminated until payment succeeds.

```
API Request: Upgrade Subscription (plan A -> plan B with payment rule)
    |
    v
CreateService -> detects upgrade -> PlanUpgradeService
    |
    v
PlanUpgradeService (gated path):
    | DO NOT terminate current_subscription yet
    | current_subscription stays ACTIVE
    v
ActivateAndBillService(new_subscription)
    |
    v
EvaluateService
    | payment_required rule on new subscription
    | new plan.pay_in_advance? -> APPLICABLE
    v
new_subscription.mark_as_activating!
    | new_subscription.previous_subscription_id = current_subscription.id
    v
Create proration invoice for upgrade (status: open, invisible)
    | fees: prorated new plan subscription fee
    | NO termination charges for old subscription yet
    v
Invoices::Payments::CreateService.call_async
    | Payment issued to PSP
    v
SendWebhookJob("subscription.activating", new_subscription)
    |
    v
[WAIT FOR PSP RESPONSE — old subscription remains ACTIVE]
    |
    +--- payment_intent.succeeded ------+--- payment_intent.failed --------+
    |                                   |                                  |
    v                                   v                                  |
ProcessPaymentService               ProcessPaymentService                 |
    | rule -> satisfied                 | rule -> failed                   |
    v                                   v                                  |
TryActivateService                  subscription stays activating          |
    | invoice: open -> finalized        | customer can retry               |
    | (invoice.created webhook, PDF)    +----------------------------------+
    v                                   |
new_subscription.mark_as_active!        |   [timeout_hours expires]
    v                                   |         |
NOW terminate old subscription:         |         v
    | TerminateService.call(old,        |   ExpireService -> CancelService
    |   upgrade: true)                  |     | rule -> expired
    | Termination invoice created       |     | invoice: open -> closed
    |   (finalized normally, separate)  |     | new_subscription -> canceled
    v                                   |     | old subscription unchanged
"subscription.started" (new)            |     v
"subscription.terminated" (old)         |   "subscription.activation_expired"
                                        |   customer keeps current plan
```

**Key design decisions:**
- The old subscription stays **active** during the payment window — no gap in service
- The new subscription's proration invoice is created and paid **before** the old one is terminated — separate invoices avoid mixed gated/non-gated billing
- The termination invoice for the old subscription is a separate, normal (non-gated) invoice created after the new subscription activates
- `PlanUpgradeService` needs two code paths: the current flow (no rules) and the gated flow (defer termination)

**On payment failure or timeout:**
- The new `activating` subscription is canceled (via `CancelService` on timeout, or left for retry on failure)
- The gated invoice is **closed** (it was `open`/invisible, never finalized — no AR impact)
- The old subscription was **never terminated** — customer keeps their current plan
- No termination invoice was ever created — clean rollback

### 5.5 Downgrade Rotation with Payment Rule

Product vision: downgrades are applied **at the end of the current billing period** when payment succeeds. If payment fails or times out, the current plan is **extended** and the downgrade is cancelled.

The downgrade was already stored as a `pending` `next_subscription` at request time (current behavior). At billing period end, `terminate_and_start_next` fires but defers termination when the next subscription is gated.

```
[Billing date arrives, OrganizationBillingService detects pending downgrade]
    |
    v
TerminateService#terminate_and_start_next (gated path)
    | DO NOT terminate old subscription yet
    v
ActivateAndBillService(next_subscription)
    |
    v
EvaluateService
    | payment_required rule on next_subscription
    | next plan.pay_in_advance? -> APPLICABLE
    v
next_subscription.mark_as_activating!
    v
Create invoice for new plan (status: open, invisible)
    v
Invoices::Payments::CreateService.call_async
    |
    v
[WAIT FOR PSP RESPONSE — old subscription remains ACTIVE]
    |
    +--- payment_intent.succeeded ------+--- payment_intent.failed --------+
    |                                   |                                  |
    v                                   v                                  |
TryActivateService                  rule -> failed                         |
    | invoice: open -> finalized        | customer can retry               |
    v                                   +----------------------------------+
next_subscription.mark_as_active!       |   [timeout_hours expires]
    v                                   |         |
NOW terminate old subscription:         |         v
    | old.mark_as_terminated!           |   ExpireService -> CancelService
    | Termination invoice created       |     | rule -> expired
    |   (finalized normally)            |     | invoice: open -> closed
    | BillNonInvoiceableFeesJob(old)    |     | next_subscription -> canceled
    v                                   |     | old subscription EXTENDED
"subscription.started" (next)           |     |   (continues on current plan,
"subscription.terminated" (old)         |     |    downgrade cancelled)
                                        |     v
                                        |   "subscription.activation_expired"
```

**Key design decisions:**
- The old subscription stays active (slightly beyond its billing period boundary) until the new subscription's payment clears. A brief overlap is safer than a gap.
- `terminate_and_start_next` needs a gated code path that defers termination until `TryActivateService` triggers it.
- `BillNonInvoiceableFeesJob` for the old subscription fires when it is finally terminated (arrears fees, not gated).

**On payment failure or timeout:**
- The `next_subscription` is **canceled** — the downgrade is cancelled entirely
- The gated invoice is **closed** (invisible, never finalized)
- The old subscription **continues on the current plan** ("extended") — next billing cycle bills it normally
- Since the `next_subscription` was canceled (not pending), `terminate_and_start_next` won't attempt another rotation next cycle

**Double-billing concern:** During the payment window, the old subscription is still active. For practical purposes, `timeout_hours` should be much shorter than the billing period (e.g., 24-48h for a monthly plan). If the timeout exceeds the billing period, the next billing cycle could attempt to bill the old subscription again — this should be documented as a constraint.

### 5.6 Payment Rule Expiration (timeout)

```
[Subscription created with payment_required rule, timeout_hours: 48]
    |
    v
EvaluateService
    | rule.status = :pending
    | rule.expires_at = now + 48.hours
    v
subscription.mark_as_activating!
invoice created (open), payment issued to PSP
    |
    v
[48 hours pass, no successful payment received]
    |
    v
Clock::ActivationRulesExpirationJob (runs periodically)
    | finds: activation_rules.pending.where("expires_at <= ?", Time.current)
    v
ActivationRules::ExpireService.call(rule:)
    | rule.status -> expired
    | subscription has no remaining pending rules? YES (all expired/failed)
    v
ActivationRules::CancelService.call(subscription:)
    | gated invoice: open -> closed (never finalized, no AR impact)
    | subscription.mark_as_canceled!
    v
SendWebhookJob("subscription.activation_expired", subscription)
    | org/customer notified that activation timed out
```

**Clock job design:**

```ruby
module Clock
  class ActivationRulesExpirationJob < ApplicationJob
    queue_as "clock"

    def perform
      SubscriptionActivationRule
        .pending
        .where("expires_at <= ?", Time.current)
        .find_each do |rule|
          Subscriptions::ActivationRules::ExpireService.call(rule:)
        end
    end
  end
end
```

**ExpireService:**

```ruby
module Subscriptions
  module ActivationRules
    class ExpireService < BaseService
      def initialize(rule:)
        @rule = rule
        @subscription = rule.subscription
      end

      def call
        return result unless rule.pending?
        return result unless rule.expires_at && rule.expires_at <= Time.current

        rule.update!(status: :expired)

        # If no pending rules remain, the activation has fully failed
        if subscription.activation_rules.pending.none?
          CancelService.call(subscription:)
        end

        result
      end
    end
  end
end
```

**Key behaviors:**
- Only rules with `timeout_hours` configured get an `expires_at` timestamp
- Rules without `timeout_hours` never expire (wait indefinitely for manual resolution)
- Expiration marks the rule as `expired` (distinct from `failed` — failed means the PSP rejected the payment, expired means time ran out)
- When all rules are either satisfied, expired, or failed (none remain pending), and at least one is not satisfied, the subscription is canceled
- The gated invoice is **closed** (not voided — the AASM `void` event requires `finalized` status; since gated invoices are `open`, we set status to `:closed` directly). No AR impact since the invoice was never finalized or visible.

---

## 6. Edge Cases and Open Questions

### 6.1 Resolved

| Edge Case | Resolution |
|-----------|-----------|
| Pay-in-arrears with no advance charges + payment rule | Rule is `not_applicable`, current behavior preserved |
| Trial period with payment rule | Not applicable (nothing to pay upfront), unless there are pay-in-advance fixed charges |
| Zero-amount invoice (100% coupon, prepaid credits cover total) | Payment auto-succeeds in `Payments::CreateService#call` (line 20-22). If no payment provider, `ActivateAndBillService` detects zero amount after invoice creation and auto-satisfies the rule directly. |
| No payment provider + payment due | `EvaluateService` validates provider exists. Returns validation error — subscription not created. |
| Subscription started in the past (`subscription_at < now`) | No gating — no billing happens (migration scenario, subscription already paid for this period). Subscription goes directly to `active`. |
| Upgrade with payment rule | Proration invoice created as `open`. Old stays active. On success: upgrade applied, old terminated. On failure/timeout: upgrade cancelled, gated invoice closed, customer keeps current plan. |
| Downgrade rotation with payment rule | At billing period end, invoice for new plan created as `open`. Old stays active. On success: downgrade applied. On failure/timeout: current plan extended, downgrade cancelled. |
| Failed upgrade/downgrade payment | New subscription canceled, gated invoice closed. Old subscription was never terminated — customer keeps current plan. Clean rollback. |
| Multiple subscriptions for same customer | Each subscription has its own rules, evaluated independently |
| Payment timeout configured | Clock job expires the rule, cancels subscription and closes the gated invoice |
| Payment timeout not configured | Rule waits indefinitely for manual resolution or retry |
| Payment fails then timeout expires | Rule already `failed`, expiration is a no-op; subscription canceled when no pending rules remain |
| Rule update on `pending` subscription | Allowed freely — rules haven't been evaluated yet |
| Rule update on `activating` subscription | Rejected — side effects (invoice, payment) are in flight |
| Rule update on `active`/`terminated`/`canceled` | Rejected — rules are irrelevant after activation |
| Rules sent as empty array `[]` | Removes all rules — subscription activates with current behavior (no gating) |
| Rules param not provided (`nil`) | No change to existing rules (distinction between `nil` and `[]`) |

### 6.2 Open Questions

**Q1: Upgrade/downgrade during `activating` state**
What if a customer upgrades again while the subscription is still `activating`?
- **Recommendation:** Allow it. Cancel the activating subscription (close its gated invoice), create a new one with the new plan. Add `activating` to `editable_subscriptions` scope. Since the old subscription was never terminated (per the upgrade flow in 5.4), there's no mess to clean up.

**Q2: Approval + Payment rules together -- ordering**
- If both are present, what order?
- **Option A (recommended):** Approval first, then payment. Rationale: don't charge the customer until the subscription is approved. If approval is denied, no payment to refund.
- **Option B:** Parallel -- both can be satisfied independently. Simpler but means payment might happen before approval.
- The data model supports both (each rule has independent status, `TryActivateService` checks all are satisfied).

**Q3: Billing before approval?**
- If approval is required, should an invoice exist before approval?
- **Recommendation:** No. The invoice should only be created when the approval rule is satisfied. This avoids creating invoices that may never be needed. For the combined case: approval satisfied -> create gated invoice -> payment rule kicks in.

**Q4: Retry mechanism for failed payments**
- Can the customer retry with a different payment method?
- **Recommendation:** Yes. Expose a retry endpoint. The existing `Invoices::Payments::RetryService` can be reused since the invoice exists (in `open` status).

**Q5: Webhook visibility for `open` invoices**
- `open` invoices are invisible (`INVISIBLE_STATUS`). The `deliver_webhook` method in `Invoices::UpdateService` checks `invoice.visible?` before sending `payment_status_updated`.
- **This means:** When a gated invoice's payment succeeds, no `invoice.payment_status_updated` webhook is sent (because the invoice is `open`). Instead, the `invoice.created` webhook fires when the invoice transitions to `finalized`. This is correct behavior.

**Q6: Plan-level default rules?**
- Should plans define default activation rules that subscriptions inherit?
- **Recommendation:** Not for v1. Rules are explicitly passed per-subscription via the API. Plan-level defaults could be added later as a convenience — the subscription would inherit rules from the plan when `activation_rules` is not provided. For now, explicit is better than implicit.

---

## 7. Migration Plan

### Phase 1: Foundation (no behavior change)

1. **Migration:** Create `subscription_activation_rules` table
2. **Migration:** Add `activating` to subscription status enum
3. **Model:** Add `SubscriptionActivationRule` model, associations, and enum validations
4. **Model:** Add `mark_as_activating!` method to `Subscription`
5. **API:** Accept `activation_rules` param in create/update (REST controller + GraphQL mutations). Create rule records, but don't evaluate them yet — they're inert.
6. **Serializer:** Expose `activation_rules` in subscription REST serializer and GraphQL type (with `rule_type`, `timeout_hours`, `status`, `expires_at`)
7. **Validation:** Reject rule modifications on non-pending subscriptions in `UpdateService`
8. **Refactor:** Extract `Subscriptions::ActivateAndBillService` from the 4 duplicated entry points -- this refactoring should be a **separate PR** that doesn't change behavior, just consolidates. All existing tests must continue to pass.

### Phase 2: Payment Rule Implementation

1. **Modify:** `Invoices::TransitionToFinalStatusService` to accept `gated:` parameter — holds invoice at `open` instead of finalizing
2. **Modify:** `Invoices::SubscriptionService` and `CreatePayInAdvanceFixedChargesService` to propagate `gated:` parameter and only trigger payment (not webhooks/documents) for `open` invoices
3. **Modify:** `CreatePayInAdvanceFixedChargesService` guard to allow `activating?` subscriptions (currently only allows `active?`)
4. **Service:** `ActivationRules::EvaluateService` (with `expires_at` computation, payment provider validation)
5. **Hook:** Add `handle_gated_activation` to `Invoices::UpdateService#schedule_post_processing_jobs`
6. **Service:** `ActivationRules::ProcessPaymentService`
7. **Service:** `ActivationRules::TryActivateService` — finalizes invoice, activates subscription, terminates previous
8. **Service:** `ActivationRules::ExpireService`
9. **Clock job:** `Clock::ActivationRulesExpirationJob` — runs periodically, expires timed-out rules
10. **Service:** `ActivationRules::CancelService` — cancels subscription and closes gated invoice
11. **Modify:** `PlanUpgradeService` — gated code path that defers old subscription termination
12. **Modify:** `TerminateService#terminate_and_start_next` — gated code path that defers termination
13. **Webhook:** `subscription.activating` (new), `subscription.activation_expired` (new — used for all failure/timeout/expiration cases)
14. **Tests:** Cover the full matrix (see below)

### Phase 3: Edge Cases

1. Handle upgrade/downgrade during `activating` state (cancel activating subscription, start new upgrade/downgrade)
2. Manual cancellation of `activating` subscriptions (close gated invoice, cancel subscription)

### Testing Matrix

| Scenario | Rules | Plan Type | Trial | Fixed Charges | Expected |
|----------|-------|-----------|-------|---------------|----------|
| No rules | none | advance | no | none | active immediately (current) |
| No rules | none | arrears | no | none | active immediately (current) |
| Payment rule | payment | advance | no | none | activating -> wait for payment |
| Payment rule | payment | arrears | no | none | not applicable -> active immediately |
| Payment rule | payment | arrears | no | advance | activating -> wait for payment |
| Payment rule | payment | advance | yes | none | not applicable -> active immediately |
| Payment rule | payment | advance | yes | advance | activating -> wait for payment |
| Payment rule + upgrade | payment | advance | no | none | old stays active, new activating; on success: new active, old terminated |
| Payment rule + downgrade | payment | advance | no | none | old stays active, new activating; on success: new active, old terminated |
| Upgrade payment fails | payment | advance | no | none | new canceled, gated invoice closed, old stays active |
| Downgrade payment fails | payment | advance | no | none | new canceled, gated invoice closed, old extended |
| No payment provider + payment rule | payment | advance | no | none | validation error, subscription not created |
| Payment + approval | both | advance | no | none | depends on ordering decision |
| Zero amount | payment | advance | no | none | auto-satisfied -> active immediately |
| Payment timeout (48h) | payment | advance | no | none | activating -> expired -> canceled after 48h |
| Payment timeout (nil) | payment | advance | no | none | activating -> wait indefinitely |
| Payment fails then expires | payment | advance | no | none | failed -> expired -> canceled |
| Payment succeeds before timeout | payment | advance | no | none | activating -> active (timer irrelevant) |
| Update rules on pending sub | payment | advance | no | none | rules replaced, old rules destroyed |
| Update rules on activating sub | payment | advance | no | none | rejected with validation error |
| Update rules on active sub | payment | advance | no | none | rejected with validation error |
| Send empty rules array `[]` | none | advance | no | none | all rules removed, no gating |
