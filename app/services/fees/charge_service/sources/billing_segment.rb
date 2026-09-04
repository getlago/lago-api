# frozen_string_literal: true

module Fees
  class ChargeService
    module Sources
      BillingSegment = Data.define(:billing_segment) do
        def initialize(billing_segment:)
          validate_billing_segment!(billing_segment)

          super
        end

        delegate :organization_id,
          :rate,
          :rate_card_rate,
          :rate_override,
          :pricing_unit,
          :proration_ratio,
          to: :billing_segment

        delegate :charge, to: :product

        def charge_filter
          nil
        end

        delegate :product_filter, to: :rate_card

        delegate :billable_metric, to: :product

        def boundaries
          BillingPeriodBoundaries.new(
            from_datetime: billing_segment.started_at,
            to_datetime: billing_segment.ended_at,
            charges_from_datetime: billing_segment.started_at,
            charges_to_datetime: billing_segment.ended_at,
            charges_duration: billing_segment.duration_in_days,
            timestamp: billing_segment.billing_at
          )
        end

        def properties
          billing_segment.rate_properties
        end

        def currency
          Money::Currency.new(billing_segment.currency)
        end

        def pricing_structure
          ChargeModels::PricingStructure.from_billing_segment(billing_segment)
        end

        def period_ratio
          billing_segment.proration_ratio
        end

        # NOTE: Product-catalog pricing groups will move to product/plan data once that feature is supported.
        def pricing_group_keys
          keys = properties["pricing_group_keys"]&.dup || []

          if accepts_target_wallet? && !keys.include?(::Charge::EVENT_TARGET_WALLET_CODE)
            keys << ::Charge::EVENT_TARGET_WALLET_CODE
          end

          keys
        end

        # NOTE: Product-catalog presentation groups will move to product/plan data once that feature is supported.
        def presentation_group_keys_values
          []
        end

        def matching_filters
          product_filter&.to_h || {}
        end

        def ignored_filters
          []
        end

        def matching_and_ignored_filters
          BaseResult[:matching_filters, :ignored_filters].new.tap do |result|
            result.matching_filters = matching_filters
            result.ignored_filters = ignored_filters
          end
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
          rate_card.wallet_targetable?
        end

        def pay_in_advance?
          rate_card.advance?
        end

        def prorated?
          rate_card.proration?
        end

        def invoiceable?
          rate_card.display_on_invoice?
        end

        def applied_pricing_unit
          return nil unless pricing_unit

          AppliedPricingUnit.new(
            organization_id: organization_id,
            pricing_unit:,
            pricing_unitable: billing_segment,
            conversion_rate: billing_segment.pricing_unit_conversion_rate
          )
        end

        private

        def product
          rate_card.product
        end

        def rate_card
          billing_segment.contract_rate_card.rate_card
        end

        def validate_billing_segment!(billing_segment)
          if billing_segment.is_a?(::BillingSegment)
            return
          end

          raise ArgumentError, "billing_segment must be a BillingSegment"
        end
      end
    end
  end
end
