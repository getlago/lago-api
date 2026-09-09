# frozen_string_literal: true

module Fees
  class ChargeService
    module Sources
      BillingSegment = Data.define(:billing_segment, :product_filter) do
        def initialize(billing_segment:, product_filter: billing_segment.contract_rate_card.rate_card.product_filter)
          super
        end

        delegate :organization_id,
          :contract,
          :rate_card_rate,
          :rate_override,
          :pricing_unit,
          to: :billing_segment

        delegate :charge, :charge_id, to: :product
        delegate :billable_metric, to: :product

        def fee_type
          :product
        end

        def invoiceable
          product
        end

        def selected_filter
          product_filter
        end

        def with_filter(filter)
          self.class.new(billing_segment:, product_filter: filter)
        end

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

        # Segment proration is persisted by the billing schedule, not elapsed current usage.
        def period_ratio
          billing_segment.proration_ratio
        end

        # NOTE: Product-catalog pricing groups will move to product/plan data once that feature is supported.
        def pricing_group_keys
          keys = properties["pricing_group_keys"]&.dup || []

          if rate_card.wallet_targetable? && !keys.include?(::Charge::EVENT_TARGET_WALLET_CODE)
            keys << ::Charge::EVENT_TARGET_WALLET_CODE
          end

          keys
        end

        # NOTE: Product-catalog presentation groups will move to product/plan data once that feature is supported.
        def presentation_group_keys_values
          []
        end

        def matching_and_ignored_filters
          ChargeFilters::MatchingAndIgnoredService::Result.new.tap do |result|
            result.matching_filters = product_filter&.to_h || {}
            result.ignored_filters = []
          end
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
      end
    end
  end
end
