# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class BaseService < ::BaseService
      def initialize(billable_metric:, subscription:)
        super(nil)
        @billable_metric = billable_metric
        @subscription = subscription
      end

      def aggregate(from_date:, to_date:)
        raise NotImplementedError
      end

      protected

      attr_accessor :billable_metric, :subscription

      delegate :customer, to: :subscription
    end
  end
end
