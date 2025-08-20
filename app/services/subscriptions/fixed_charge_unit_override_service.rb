# frozen_string_literal: true

module Subscriptions
  class FixedChargeUnitOverrideService < BaseService 
    Result = BaseResult[:fixed_charge_unit_override]

    def initialize(subscription:, fixed_charge:, units:)
      @subscription = subscription
      @fixed_charge = fixed_charge
      @units = units

      super()
    end

    def call
      return result.not_found_failure!(resource: "subscription") unless subscription

      result.fixed_charge_unit_override = build_fixed_charge_unit_override
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :subscription, :fixed_charge, :units

    def build_fixed_charge_unit_override
      SubscriptionFixedChargeUnitsOverride.create!(
        organization: subscription.organization,
        billing_entity: subscription.billing_entity,
        subscription:,
        fixed_charge:,
        units:
      )
    end
  end
end
