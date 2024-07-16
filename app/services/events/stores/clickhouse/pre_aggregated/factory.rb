# frozen_string_literal: true

module Events
  module Stores
    module Clickhouse
      module PreAggregated
        class Factory
          def self.new_instance(aggregation_type:, subscription:, boundaries:)
            klass = service_class(aggregation_type)
            return nil unless klass

            klass.new(subscription: subscription, boundaries: boundaries)
          end

          def self.service_class(aggregation_type)
            case aggregation_type.to_sym
            when :count_agg
              CountQuery
            when :last_agg
              LastQuery
            when :max_agg
              MaxQuery
            when :sum_agg
              SumQuery
            end
          end
        end
      end
    end
  end
end
