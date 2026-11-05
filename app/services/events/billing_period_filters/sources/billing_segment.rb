# frozen_string_literal: true

module Events
  module BillingPeriodFilters
    module Sources
      BillingSegment = Data.define(:billing_segment, :filter) do
        include FilterSource

        def initialize(billing_segment:, filter: nil)
          @cache = {}
          super
        end

        delegate :billable_metric, to: :product
        delegate :target_key, to: :billing_segment

        # A filter the contract prices wins over one it does not, which has no bucket to bill on.
        # Usage matching only unpriced filters still stays out of the default bucket.
        def filter_precedence(filter)
          [priced_filter_ids.include?(filter.id) ? 0 : 1, *super]
        end

        def with_filter(filter)
          self.class.new(billing_segment:, filter:)
        end

        private

        def filter_owner
          product
        end

        def product
          billing_segment.contract_rate_card.product
        end

        def priced_filter_ids
          @cache[:priced_filter_ids] ||= billing_segment.priced_product_filter_ids.to_set
        end
      end
    end
  end
end
