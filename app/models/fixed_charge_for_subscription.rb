# frozen_string_literal: true

# Lightweight wrapper that exposes a FixedCharge with its units overridden
# by any per-subscription override (SubscriptionFixedChargeUnitsOverride).
# Used at presentation/serialization time when a subscription context is
# available — primarily by the GraphQL Subscription type's `fixed_charges`
# resolver. Every method other than `units` is delegated to the underlying
# FixedCharge record.
class FixedChargeForSubscription < SimpleDelegator
  attr_reader :subscription

  def initialize(fixed_charge, subscription)
    super(fixed_charge)
    @subscription = subscription
  end

  def units
    __getobj__.units_for(subscription)
  end
end
