# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class CountService < BillableMetrics::Aggregations::BaseService
      def aggregate(from_date:, to_date:)
        customer.events
          .from_date(from_date)
          .to_date(to_date)
          .where(code: billable_metric.code)
          .count
      end
    end
  end
end
