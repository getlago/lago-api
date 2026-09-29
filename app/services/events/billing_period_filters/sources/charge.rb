# frozen_string_literal: true

module Events
  module BillingPeriodFilters
    module Sources
      Charge = Data.define(:charge, :filter) do
        delegate :billable_metric, to: :charge

        # A filter without values matches no event.
        def filters
          filters = if charge.association_cached?(:filters)
            charge.filters
          else
            charge.filters.includes(values: :billable_metric_filter)
          end

          filters.reject { filter_values(it).empty? }
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

        def filter_precedence(filter)
          filter.precedence
        end

        delegate :target_key, to: :charge

        def with_filter(filter)
          self.class.new(charge:, filter:)
        end
      end
    end
  end
end
