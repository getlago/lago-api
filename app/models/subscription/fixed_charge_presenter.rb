# frozen_string_literal: true

# Wraps a FixedCharge with subscription context so #units returns the
# per-subscription override when one exists. Used by the GraphQL
# Subscription type to expose subscription-aware units without changing
# the FixedCharge GraphQL type's contract. Every other method is
# delegated to the wrapped FixedCharge record.
class Subscription::FixedChargePresenter < SimpleDelegator
  attr_reader :subscription

  def initialize(fixed_charge, subscription)
    super(fixed_charge)
    @subscription = subscription
  end

  def units
    __getobj__.effective_units_for(subscription)
  end
end
