# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class RecurringCountService < BillableMetrics::Aggregations::BaseService
      def aggregate(from_date:, to_date:, options: {})
        # TODO: implement aggregation logic
        result.aggregation = 0
        result.count = 0
        result
      end
    end
  end
end
