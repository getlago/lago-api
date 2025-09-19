# frozen_string_literal: true

module FixedChargeEvents
  class CreateService < BaseService
    Result = BaseResult[:fixed_charge_event]

    def initialize(subscription:, fixed_charge:, timestamp: Time.current)
      @organization = subscription&.organization
      @subscription = subscription
      @fixed_charge = fixed_charge
      @timestamp = timestamp
      super
    end

    def call
      fixed_charge_event = FixedChargeEvent.create!(
        organization:,
        subscription:,
        fixed_charge:,
        units: fixed_charge.units,
        timestamp:
      )

      result.fixed_charge_event = fixed_charge_event
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :organization, :subscription, :fixed_charge, :timestamp
  end
end
