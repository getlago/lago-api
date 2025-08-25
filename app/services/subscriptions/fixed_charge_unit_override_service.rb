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

      result.fixed_charge_unit_override = create_or_update_fixed_charge_unit_override
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :subscription, :fixed_charge, :units

    def create_or_update_fixed_charge_unit_override
      fixed_charges_units_overrides = subscription.subscription_fixed_charge_units_overrides
        .find_or_initialize_by(fixed_charge:, subscription:, billing_entity: subscription.billing_entity,
          organization: subscription.organization)
      fixed_charges_units_overrides.units = units
      fixed_charges_units_overrides.save!
      fixed_charges_units_overrides
    end
  end
end
