# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Webhooks
  module BillableMetrics
    class CreatedService < Webhooks::BaseService
      private

      def object_serializer
        ::V1::BillableMetricSerializer.new(
          object,
          root_name: "billable_metric"
        )
      end

      def webhook_type
        "billable_metric.created"
      end

      def object_type
        "billable_metric"
      end
    end
  end
end
