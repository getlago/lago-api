# frozen_string_literal: true

module Webhooks
  module Plans
    class UpdatedDetailsService < Webhooks::BaseService
      private

      def object_serializer
        ::V1::PlanUpdatedDetailsSerializer.new(
          object,
          root_name: "plan",
          changes: options[:changes] || {}
        )
      end

      def webhook_type
        "plan.updated_details"
      end

      def object_type
        "plan"
      end
    end
  end
end
