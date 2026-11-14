# frozen_string_literal: true

module Webhooks
  module Plans
    class EntitlementsUpdatedService < Webhooks::BaseService
      private

      def object_serializer
        ::V2::CatalogPlans::EntitlementsUpdatedSerializer.new(object, root_name: "plan")
      end

      def webhook_type
        "plan.entitlements_updated"
      end

      def object_type
        "plan"
      end
    end
  end
end
