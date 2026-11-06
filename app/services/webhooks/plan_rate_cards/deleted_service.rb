# frozen_string_literal: true

module Webhooks
  module PlanRateCards
    class DeletedService < Webhooks::BaseService
      private

      def object_serializer
        ::V2::PlanRateCardSerializer.new(object, root_name: "plan_rate_card")
      end

      def webhook_type
        "plan_rate_card.deleted"
      end

      def object_type
        "plan_rate_card"
      end
    end
  end
end
