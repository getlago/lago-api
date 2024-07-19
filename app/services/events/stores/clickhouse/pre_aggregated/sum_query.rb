# frozen_string_literal: true

module Events
  module Stores
    module Clickhouse
      module PreAggregated
        class SumQuery < Base
          protected

          def aggregation_type
            @aggregation_type ||= 'sum_agg'
          end

          def pre_aggregated_model
            @pre_aggregated_model ||= ::Clickhouse::EventsSumAgg
          end

          def clickhouse_aggregation
            @clickhouse_aggregation ||= 'sum'
          end

          def assign_units(bucket, units)
            bucket[:units] += units
          end
        end
      end
    end
  end
end
