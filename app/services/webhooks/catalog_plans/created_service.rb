# frozen_string_literal: true

module Webhooks
  module CatalogPlans
    class CreatedService < Webhooks::BaseService
      private

      def object_serializer
        ::V1::CatalogPlanSerializer.new(object, root_name: "catalog_plan")
      end

      def webhook_type
        "catalog_plan.created"
      end

      def object_type
        "catalog_plan"
      end
    end
  end
end
