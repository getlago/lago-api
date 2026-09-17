# frozen_string_literal: true

module Events
  module BillingPeriodFilters
    module Sources
      Charge = Data.define(:charge, :filter) do
        delegate :billable_metric, to: :charge

        def filters
          return charge.filters if charge.association_cached?(:filters)

          charge.filters.includes(values: :billable_metric_filter)
        end

        def selected_filter
          filter
        end

        def filter_values(filter)
          filter.to_h_with_all_values
        end

        def filter_match_values(filter)
          filter.to_h
        end

        def filter_specificity(filter)
          filter.to_h.keys.size
        end

        def all_filter_values?(filter, key)
          filter.to_h[key] == [ChargeFilterValue::ALL_FILTER_VALUES]
        end

        delegate :target_key, to: :charge

        def with_filter(filter)
          self.class.new(charge:, filter:)
        end
      end
    end
  end
end
