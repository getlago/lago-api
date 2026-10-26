# frozen_string_literal: true

module Events
  module BillingPeriodFilters
    module Sources
      module FilterSource
        def filters
          filters = if filter_owner.association_cached?(:filters)
            filter_owner.filters
          else
            filter_owner.filters.includes(values: :billable_metric_filter)
          end

          # An empty filter has no constraints and would otherwise match every event.
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
      end
    end
  end
end
