# frozen_string_literal: true

module Fees
  class ChargeService
    module Sources
      Charge = Data.define(:charge, :boundaries, :charge_filter, :properties_override) do
        def initialize(charge:, boundaries:, charge_filter: nil, properties_override: nil)
          @cache = {}
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

        def filter_association
          :charge_filter
        end

        def with_default_filter
          with_filter(
            ChargeFilter.new(charge:, properties: {"pricing_group_keys" => charge.pricing_group_keys}),
            properties: charge.properties
          )
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

        def elapsed_period_ratio
          Billing::ElapsedPeriodRatio.calculate(
            from_date: boundaries.charges_from_datetime.to_date,
            to_date: boundaries.charges_to_datetime.to_date,
            current_date: Time.current.to_date,
            duration_in_days: boundaries.charges_duration
          )
        end

        def pricing_group_keys
          keys = (charge_filter.presence || charge).pricing_group_keys&.dup || []

          if charge.accepts_target_wallet && !keys.include?(::Charge::EVENT_TARGET_WALLET_CODE)
            keys << ::Charge::EVENT_TARGET_WALLET_CODE
          end

          keys
        end

        def matching_and_ignored_filters
          @cache[:matching_and_ignored_filters] ||= Events::BillingPeriodFilters::MatchingAndIgnoredService.call(
            target_filter: Events::BillingPeriodFilters::FilterTarget.from_charge(charge:, filter: charge_filter)
          )
        end

        def currency
          charge.plan.amount.currency
        end
      end
    end
  end
end
