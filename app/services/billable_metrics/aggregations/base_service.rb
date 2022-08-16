# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class BaseService < ::BaseService
      def initialize(billable_metric:, subscription:)
        super(nil)
        @billable_metric = billable_metric
        @subscription = subscription
      end

      def aggregate(from_date:, to_date:, free_units_count: 0)
        raise NotImplementedError
      end

      protected

      attr_accessor :billable_metric, :subscription

      delegate :customer, to: :subscription

      def events_scope(from_date:, to_date:)
        subscription.events
          .from_date(from_date)
          .to_date(to_date)
          .where(code: billable_metric.code)
      end
    end
  end
end
