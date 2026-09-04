# frozen_string_literal: true

module Events
  module BillingPeriodFilters
    module Sources
      BillingSegment = Data.define(:billing_segment, :filter) do
        delegate :billable_metric, to: :product

        def filters
          return product.filters if product.association_cached?(:filters)

          product.filters.includes(values: :billable_metric_filter)
        end

        def selected_filter
          filter
        end

        def filter_values(filter)
          filter.to_h
        end

        def filter_match_values(filter)
          filter.to_h
        end

        def filter_specificity(filter)
          filter.to_h.keys.size
        end

        def all_filter_values?(_filter, _key)
          false
        end

        delegate :target_key, to: :product

        def with_filter(filter)
          self.class.new(billing_segment:, filter:)
        end

        private

        def product
          billing_segment.contract_rate_card.product
        end
      end
    end
  end
end
