# frozen_string_literal: true

module Fees
  class ChargeService
    module Sources
      Charge = Data.define(:charge, :boundaries, :charge_filter, :properties_override) do
        def initialize(charge:, boundaries:, charge_filter: nil, properties_override: nil)
          super
        end

        delegate :billable_metric,
          :pay_in_advance?,
          :prorated?,
          :invoiceable?,
          :applied_pricing_unit,
          :organization_id,
          :presentation_group_keys_values,
          to: :charge

        delegate :id, to: :charge, prefix: true

        def with_filter(charge_filter, properties: nil)
          self.class.new(
            charge:,
            boundaries:,
            charge_filter:,
            properties_override: properties
          )
        end

        def selected_filter
          charge_filter
        end

        def fee_type
          :charge
        end

        def invoiceable
          charge
        end

        def properties
          properties_override || charge_filter&.properties || charge.properties
        end

        def pricing_structure
          ChargeModels::PricingStructure.from_charge(charge).with(properties:)
        end

        def period_ratio
          from_date = boundaries.charges_from_datetime.to_date
          to_date = boundaries.charges_to_datetime.to_date
          current_date = Time.current.to_date

          total_days = (to_date - from_date).to_i + 1
          charges_duration = boundaries.charges_duration || total_days

          return 1.0 if current_date >= to_date
          return 0.0 if current_date < from_date

          days_passed = (current_date - from_date).to_i + 1
          days_passed.fdiv(charges_duration).clamp(0.0, 1.0)
        end

        def pricing_group_keys
          keys = (charge_filter.presence || charge).pricing_group_keys&.dup || []

          if charge.accepts_target_wallet && !keys.include?(::Charge::EVENT_TARGET_WALLET_CODE)
            keys << ::Charge::EVENT_TARGET_WALLET_CODE
          end

          keys
        end

        def matching_and_ignored_filters
          ChargeFilters::MatchingAndIgnoredService.call(
            charge:,
            filter: charge_filter
          )
        end

        def currency
          charge.plan.amount.currency
        end
      end
    end
  end
end
