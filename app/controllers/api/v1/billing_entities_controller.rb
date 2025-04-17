# frozen_string_literal: true

module Api
  module V1
    class BillingEntitiesController < Api::BaseController
      def index
        render(
          json: ::CollectionSerializer.new(
            current_organization.billing_entities,
            ::V1::BillingEntitySerializer,
            collection_name: "billing_entities"
          )
        )
      end

      def show
        entity = BillingEntity.find_by(code: params[:code], organization: current_organization)

        return not_found_error(resource: "billing_entity") if entity.blank?

        render(
          json: ::V1::BillingEntitySerializer.new(entity, root_name: "billing_entity", includes: [:taxes])
        )
      end
    end
  end
end
