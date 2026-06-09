# frozen_string_literal: true

module Webhooks
  module Plans
    # NOTE: Sent alongside `plan.updated`. Unlike `plan.updated`, which carries the
    #       whole serialized plan, this webhook carries only the fields that changed
    #       during the update (with their previous and new values), plus flags for
    #       which associations were modified.
    class UpdatedDetailsService < Webhooks::BaseService
      private

      def object_serializer
        ::V1::PlanUpdatedDetailsSerializer.new(
          object,
          root_name: object_type,
          changes: options[:changes],
          associations_changed: options[:associations_changed]
        )
      end

      def webhook_type
        "plan.updated_details"
      end

      def object_type
        "plan_updated_details"
      end
    end
  end
end
