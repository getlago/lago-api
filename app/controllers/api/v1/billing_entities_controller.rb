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

      def manage_taxes
        entity = BillingEntity.find_by(code: params[:code], organization: current_organization)
        return not_found_error(resource: "billing_entity") if entity.blank?

        result = BillingEntities::Taxes::ManageTaxesService.call(billing_entity: entity, tax_codes: params[:tax_codes])

        if result.success?
          render(json: ::V1::BillingEntitySerializer.new(entity, root_name: "billing_entity"))
        else
          render_error_response(result)
        end
      end
    end
  end
end
