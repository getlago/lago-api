# frozen_string_literal: true

module Events
  module Stores
    module Clickhouse
      module PreAggregated
        class MaxQuery < Base
          protected

          def aggregation_type
            @aggregation_type ||= 'max_agg'
          end

          def pre_aggregated_model
            @pre_aggregated_model ||= ::Clickhouse::EventsMaxAgg
          end

          def clickhouse_aggregation
            @clickhouse_aggregation ||= 'max'
          end

          def assign_units(bucket, units)
            bucket[:units] = units if units > bucket[:units]
          end
        end
      end
    end
  end
end
