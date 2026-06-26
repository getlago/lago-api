# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Webhooks
  module Plans
    class CreatedService < Webhooks::BaseService
      private

      def object_serializer
        ::V1::PlanSerializer.new(
          object,
          root_name: "plan",
          includes: %i[charges usage_thresholds taxes minimum_commitment entitlements]
        )
      end

      def webhook_type
        "plan.created"
      end

      def object_type
        "plan"
      end
    end
  end
end
