# frozen_string_literal: true

module Subscriptions
  module FixedChargeUnitsOverrides
    # Writes (or updates) one Subscription::FixedChargeUnitsOverride row for
    # the given (subscription, fixed_charge) pair, emits a FixedChargeEvent
    # for the subscription, and — when `apply_units_immediately` is set on a
    # pay-in-advance fixed charge — dispatches the mid-period delta billing
    # job after the surrounding transaction commits.
    #
    # The service is the shared building block for the two write surfaces
    # that record units-only overrides mid-cycle: the dedicated subscription
    # fixed_charge endpoint (`UpdateOrOverrideFixedChargeService`) and the
    # subscription update endpoint (`UpdateService`). Subscription creation
    # has different lifecycle constraints (events emit through the
    # activation path) and writes override rows directly without this
    # service.
    #
    class WriteService < BaseService
      Result = BaseResult[:units_override]

      def initialize(subscription:, fixed_charge:, units:, apply_units_immediately: false, timestamp: nil)
        @subscription = subscription
        @fixed_charge = fixed_charge
        @units = units
        @apply_units_immediately = !!apply_units_immediately
        @timestamp = (timestamp || Time.current.to_i).to_i
        super
      end

      def call
        ActiveRecord::Base.transaction do
          units_override = ::Subscription::FixedChargeUnitsOverride.find_or_initialize_by(
            subscription:,
            fixed_charge:
          )
          units_override.organization = subscription.organization
          units_override.units = units
          units_override.save!

          FixedCharges::EmitEventsService.call!(
            fixed_charge:,
            subscription:,
            apply_units_immediately:,
            timestamp:
          )

          if apply_units_immediately && fixed_charge.pay_in_advance? && subscription.active?
            after_commit do
              Invoices::CreatePayInAdvanceFixedChargesJob.perform_later(subscription, timestamp)
            end
          end

          result.units_override = units_override
        end

        result
      end

      private

      attr_reader :subscription, :fixed_charge, :units, :apply_units_immediately, :timestamp
    end
  end
end
