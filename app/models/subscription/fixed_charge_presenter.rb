# frozen_string_literal: true

# Wraps a FixedCharge with subscription context so #units returns the
# per-subscription override when one exists. Used by the GraphQL
# Subscription type to expose subscription-aware units without changing
# the FixedCharge GraphQL type's contract. Every other method is
# delegated to the wrapped FixedCharge record.
class Subscription::FixedChargePresenter < SimpleDelegator
  attr_reader :subscription

  # Accepts an optional pre-resolved override units value via `effective_units:`.
  # Collection callers (GraphQL Subscription type) pass the value from a batched
  # lookup to avoid an N+1 against subscription_fixed_charge_units_overrides;
  # standalone callers can omit it and the presenter resolves it on its own.
  def initialize(fixed_charge, subscription, **opts)
    super(fixed_charge)
    @subscription = subscription
    @effective_units = opts.fetch(:effective_units) { fixed_charge.effective_units_for(subscription) }
  end

  def units
    @effective_units || __getobj__.units
  end
end
