# frozen_string_literal: true

module Fees
  class ChargeService
    module Sources
      Charge = Data.define(:charge, :boundaries, :charge_filter, :properties_override) do
        def initialize(charge:, boundaries:, charge_filter: nil, properties_override: nil)
          validate_charge!(charge)
          validate_boundaries!(boundaries)
          validate_charge_filter!(charge, charge_filter)

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

        def with_charge_filter(charge_filter, properties: nil)
          self.class.new(
            charge:,
            boundaries:,
            charge_filter:,
            properties_override: properties
          )
        end

        def billing_segment
          nil
        end

        def product_filter
          nil
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

        def matching_filters
          return {} unless charge_filter

          matching_and_ignored_filters.matching_filters
        end

        def ignored_filters
          return [] unless charge_filter

          matching_and_ignored_filters.ignored_filters
        end

        def matching_and_ignored_filters
          ChargeFilters::MatchingAndIgnoredService.call(
            charge:,
            filter: charge_filter
          )
        end

        def aggregation_options(current_usage:)
          {
            free_units_per_events: properties["free_units_per_events"].to_i,
            free_units_per_total_aggregation: BigDecimal(properties["free_units_per_total_aggregation"] || 0),
            is_current_usage: current_usage,
            is_pay_in_advance: pay_in_advance?
          }
        end

        def accepts_target_wallet?
          charge.accepts_target_wallet
        end

        def currency
          charge.plan.amount.currency
        end

        private

        def validate_charge!(charge)
          return if charge.is_a?(::Charge)

          raise ArgumentError, "charge must be a Charge"
        end

        def validate_boundaries!(boundaries)
          if boundaries&.charges_from_datetime && boundaries.charges_to_datetime
            return
          end

          raise ArgumentError, "charge boundaries are mandatory"
        end

        def validate_charge_filter!(charge, charge_filter)
          return unless charge_filter

          unless charge_filter.is_a?(::ChargeFilter)
            raise ArgumentError, "charge_filter must be a ChargeFilter"
          end

          return if charge_filter.charge.nil? || charge_filter.charge == charge

          raise ArgumentError, "charge_filter must belong to charge"
        end
      end
    end
  end
end
